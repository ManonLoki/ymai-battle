#!/usr/bin/env python3
"""Locate an external executable the same way for every build and test script."""

from __future__ import annotations

from collections.abc import Iterable
import os
from pathlib import Path
import shutil


def find_executable(
    label: str,
    explicit: str | None,
    env_vars: Iterable[str],
    commands: Iterable[str] = (),
    candidates: Iterable[str] = (),
    hint: str = "",
) -> Path:
    """Return the first runnable path for ``label``.

    The lookup order is fixed on purpose so every caller behaves the same:
    an explicit ``--flag`` wins, then the environment variables in order, then
    ``PATH``, then the well-known install locations. ``env_vars`` takes several
    names because the same binary is already configured under different names
    elsewhere in the repo (``tools/build_android.sh`` uses ``GODOT``).
    """

    seen: list[str] = [explicit] if explicit else []
    for name in env_vars:
        configured = os.environ.get(name)
        if configured:
            seen.append(configured)
    for command in commands:
        found = shutil.which(command)
        if found:
            seen.append(found)
    seen.extend(candidates)
    for candidate in seen:
        path = Path(candidate).expanduser()
        if path.is_file() and os.access(path, os.X_OK):
            return path.resolve()
    raise FileNotFoundError(hint or f"{label} was not found")
