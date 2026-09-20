#!/usr/bin/env python3
"""Authoritative standard and embedded Web exporter for YMAIBattle."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

from exe_lookup import find_executable
from web_fetch_bridge import BridgePatchError, patch_file, verify_file


PROJECT_ROOT = Path(__file__).resolve().parents[1]
RELEASE_ROOT = PROJECT_ROOT / "Release"
EXPORTS = (
    ("Web", RELEASE_ROOT / "web", False),
    ("Web Embedded", RELEASE_ROOT / "web-embedded", True),
)
EMBEDDED_FILES = {
    "index.apple-touch-icon.png",
    "index.audio.position.worklet.js",
    "index.audio.worklet.js",
    "index.html",
    "index.icon.png",
    "index.js",
    "index.pck",
    "index.png",
    "index.wasm",
}
STANDARD_REQUIRED_FILES = EMBEDDED_FILES | {
    "index.144x144.png",
    "index.180x180.png",
    "index.512x512.png",
    "index.manifest.json",
    "index.offline.html",
    "index.service.worker.js",
    "index.side.wasm",
}


class ExportVerificationError(RuntimeError):
    """A generated Web directory violated its preset contract."""


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _godot_config(html_path: Path) -> tuple[dict[str, object], bool]:
    html = html_path.read_text(encoding="utf-8")
    prefix = "const GODOT_CONFIG = "
    suffix = ";\nconst GODOT_THREADS_ENABLED = "
    if html.count(prefix) != 1 or html.count(suffix) != 1:
        raise ExportVerificationError(f"cannot locate GODOT_CONFIG in {html_path}")
    raw_config, tail = html.split(prefix, 1)[1].split(suffix, 1)
    thread_value = tail.split(";", 1)[0]
    if thread_value not in {"true", "false"}:
        raise ExportVerificationError(
            f"invalid GODOT_THREADS_ENABLED value in {html_path}: {thread_value}"
        )
    config = json.loads(raw_config)
    if not isinstance(config, dict):
        raise ExportVerificationError(f"GODOT_CONFIG is not an object in {html_path}")
    return config, thread_value == "true"


def verify_export(output: Path, embedded: bool) -> str:
    """Verify one complete generated output and return its PCK digest."""

    if not output.is_dir():
        raise ExportVerificationError(f"missing export directory: {output}")
    names = {path.name for path in output.iterdir() if path.is_file()}
    if embedded:
        if names != EMBEDDED_FILES:
            missing = sorted(EMBEDDED_FILES - names)
            extra = sorted(names - EMBEDDED_FILES)
            raise ExportVerificationError(
                "embedded export must contain exactly 9 files; "
                f"missing={missing}, extra={extra}"
            )
    else:
        missing = sorted(STANDARD_REQUIRED_FILES - names)
        if missing:
            raise ExportVerificationError(
                f"standard Web export is missing required files: {missing}"
            )

    verify_file(output / "index.js")
    config, threads_enabled = _godot_config(output / "index.html")
    if embedded:
        if threads_enabled:
            raise ExportVerificationError("embedded export unexpectedly enables threads")
        if config.get("ensureCrossOriginIsolationHeaders") is not False:
            raise ExportVerificationError(
                "embedded export unexpectedly requests cross-origin isolation"
            )
        if config.get("gdextensionLibs") != []:
            raise ExportVerificationError("embedded export contains GDExtension libraries")
        forbidden_suffixes = (
            ".service.worker.js",
            ".manifest.json",
            ".offline.html",
            ".side.wasm",
        )
        if any(name.endswith(forbidden_suffixes) for name in names):
            raise ExportVerificationError(
                "embedded export contains PWA, service-worker, or side-module files"
            )
    else:
        if not threads_enabled:
            raise ExportVerificationError("standard Web export unexpectedly disables threads")
        if config.get("serviceWorker") != "index.service.worker.js":
            raise ExportVerificationError("standard Web export lost its service worker")

    file_sizes = config.get("fileSizes")
    if not isinstance(file_sizes, dict):
        raise ExportVerificationError("GODOT_CONFIG.fileSizes is missing")
    for name in ("index.pck", "index.wasm"):
        if file_sizes.get(name) != (output / name).stat().st_size:
            raise ExportVerificationError(
                f"GODOT_CONFIG size does not match generated {name}"
            )
    return _sha256(output / "index.pck")


def _find_godot(explicit: str | None) -> Path:
    # GODOT is what tools/build_android.sh already reads, so a machine configured
    # for the Android build needs no second variable for the Web build.
    return find_executable(
        "Godot",
        explicit,
        ("GODOT_BIN", "GODOT"),
        ("godot", "Godot"),
        (
            "/Applications/Godot.app/Contents/MacOS/Godot",
            "/Applications/Godot.app/Contents/MacOS/godot",
        ),
        "Godot was not found; pass --godot or set GODOT_BIN / GODOT",
    )


def _reset_output(output: Path) -> None:
    resolved_release = RELEASE_ROOT.resolve()
    resolved_output = output.resolve()
    if resolved_output.parent != resolved_release or resolved_output == resolved_release:
        raise RuntimeError(f"refusing to clear unsafe export path: {resolved_output}")
    if output.is_symlink() or (output.exists() and not output.is_dir()):
        raise RuntimeError(f"refusing to replace non-directory export path: {output}")
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)


def _export(godot: Path, preset: str, output: Path) -> None:
    _reset_output(output)
    command = [
        str(godot),
        "--headless",
        "--path",
        str(PROJECT_ROOT),
        "--export-release",
        preset,
        str(output / "index.html"),
    ]
    print(f"exporting {preset} -> {output}", flush=True)
    subprocess.run(command, cwd=PROJECT_ROOT, check=True)
    patch_file(output / "index.js")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Export and harden both YMAIBattle Web variants. Raw Godot Web exports "
            "are not publication-ready."
        )
    )
    parser.add_argument("--godot", help="path to the Godot 4.7 executable")
    parser.add_argument(
        "--verify-only",
        action="store_true",
        help="verify existing outputs without exporting or changing files",
    )
    args = parser.parse_args()

    try:
        if not args.verify_only:
            RELEASE_ROOT.mkdir(exist_ok=True)
            (RELEASE_ROOT / ".gdignore").write_text("", encoding="utf-8")
            godot = _find_godot(args.godot)
            version = subprocess.run(
                [str(godot), "--version"],
                check=True,
                capture_output=True,
                text=True,
            ).stdout.strip()
            if not version.startswith("4.7.2.stable"):
                raise RuntimeError(
                    "the locked bridge patch requires Godot 4.7.2.stable; "
                    f"found {version}"
                )
            for preset, output, _embedded in EXPORTS:
                _export(godot, preset, output)

        digests: dict[str, str] = {}
        for preset, output, embedded in EXPORTS:
            digest = verify_export(output, embedded)
            digests[preset] = digest
            count = sum(1 for path in output.iterdir() if path.is_file())
            print(f"verified {preset}: files={count}, index.pck sha256={digest}")
        if len(set(digests.values())) != 1:
            raise ExportVerificationError(
                "standard and embedded exports contain different index.pck bytes"
            )
    except (
        BridgePatchError,
        ExportVerificationError,
        FileNotFoundError,
        json.JSONDecodeError,
        OSError,
        RuntimeError,
        subprocess.CalledProcessError,
    ) as error:
        print(f"WEB_EXPORT_FAILED: {error}", file=sys.stderr)
        return 1

    print("WEB_EXPORT_VERIFIED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
