#!/usr/bin/env python3
"""Self-contained regression tests for the generated Godot Web Fetch bridge."""

from __future__ import annotations

import hashlib
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from web_fetch_bridge import (  # noqa: E402
    BRIDGE_END,
    BridgePatchError,
    GODOT_4_7_2_BRIDGE_SHA256,
    PATCHED_GODOT_FETCH,
    extract_bridge,
    patch_source,
    verify_source,
)


class WebFetchBridgeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.stock_bridge = (
            ROOT / "tests" / "fixtures" / "godot_fetch_4_7_2.js"
        ).read_text(encoding="utf-8").strip()
        cls.stock_source = f"prefix:{cls.stock_bridge}{BRIDGE_END}(tail)"

    def test_fixture_is_the_locked_godot_4_7_2_bridge(self) -> None:
        digest = hashlib.sha256(self.stock_bridge.encode("utf-8")).hexdigest()
        self.assertEqual(digest, GODOT_4_7_2_BRIDGE_SHA256)

    def test_exact_bridge_is_hardened_and_verifiable(self) -> None:
        patched = patch_source(self.stock_source)
        verify_source(patched)
        self.assertEqual(extract_bridge(patched), PATCHED_GODOT_FETCH)
        bridge = extract_bridge(patched)
        self.assertIn('redirect:"error"', bridge)
        self.assertIn("new AbortController()", bridge)
        self.assertIn("signal:controller.signal", bridge)
        self.assertIn("obj.reader.cancel()", bridge)
        self.assertIn("obj.controller.abort()", bridge)
        self.assertNotIn("response.abort()", bridge)

    def test_changed_upstream_bridge_fails_closed(self) -> None:
        changed = self.stock_source.replace("const init=", "let init=", 1)
        with self.assertRaisesRegex(BridgePatchError, "bridge changed"):
            patch_source(changed)

    def test_missing_or_duplicate_bridge_fails_closed(self) -> None:
        with self.assertRaisesRegex(BridgePatchError, "exactly one"):
            patch_source("no bridge")
        with self.assertRaisesRegex(BridgePatchError, "exactly one"):
            patch_source(self.stock_source + self.stock_source)

    @unittest.skipUnless(shutil.which("node"), "Node.js is unavailable")
    def test_patched_bridge_rejects_redirects_and_cancels_real_fetch(self) -> None:
        patched = patch_source(self.stock_source)
        with tempfile.TemporaryDirectory() as directory:
            generated = Path(directory) / "bridge.js"
            # Extract here rather than in the harness: the markers live in
            # tools/web_fetch_bridge.py and should only be written down once.
            generated.write_text(extract_bridge(patched), encoding="utf-8")
            result = subprocess.run(
                [
                    shutil.which("node") or "node",
                    str(ROOT / "tests" / "web_fetch_bridge_harness.js"),
                    str(generated),
                ],
                check=True,
                capture_output=True,
                text=True,
                timeout=20,
            )
        self.assertIn("WEB_FETCH_BRIDGE_RUNTIME_PASSED", result.stdout)


if __name__ == "__main__":
    unittest.main()
