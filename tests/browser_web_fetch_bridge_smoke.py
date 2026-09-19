#!/usr/bin/env python3
"""Run the generated Fetch bridge against loopback endpoints in real Chromium."""

from __future__ import annotations

import argparse
import base64
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time
from urllib.request import urlopen
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from web_fetch_bridge import extract_bridge, verify_file  # noqa: E402


def _find_chrome(explicit: str | None) -> Path:
    candidates = [explicit, os.environ.get("CHROME_BIN"), shutil.which("google-chrome")]
    candidates.extend(
        (
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            "/Applications/Chromium.app/Contents/MacOS/Chromium",
            "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
        )
    )
    for candidate in candidates:
        if not candidate:
            continue
        path = Path(candidate).expanduser()
        if path.is_file() and os.access(path, os.X_OK):
            return path.resolve()
    raise FileNotFoundError(
        "Chromium browser not found; pass --chrome or set task-specific CHROME_BIN"
    )


class LoopbackState:
    def __init__(self, bridge: str) -> None:
        self.bridge = bridge
        self.redirect_hits = 0
        self.redirect_target_hits = 0
        self.stream_closed = threading.Event()


def _page(bridge: str) -> bytes:
    script = f"""<!doctype html>
<meta charset="utf-8">
<title>RUNNING</title>
<body>RUNNING</body>
<script>
'use strict';
const objects = new Map();
let nextId = 1;
const IDHandler = {{
  add(object) {{ const id = nextId++; objects.set(id, object); return id; }},
  get(id) {{ return objects.get(id); }},
  remove(id) {{ objects.delete(id); }},
}};
const bridgeErrors = [];
const GodotRuntime = {{ error(error) {{ bridgeErrors.push(error); }} }};
{bridge};
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
async function waitFor(predicate, label) {{
  const deadline = performance.now() + 4000;
  while (!(await predicate())) {{
    if (performance.now() >= deadline) throw new Error(`timeout: ${{label}}`);
    await sleep(10);
  }}
}}
(async () => {{
  const redirectId = GodotFetch.create('GET', '/redirect', [], null);
  const redirectObject = objects.get(redirectId);
  await waitFor(() => redirectObject.error !== null, 'redirect rejection');
  GodotFetch.free(redirectId);
  if (!redirectObject.controller.signal.aborted) throw new Error('redirect controller not aborted');

  const streamId = GodotFetch.create('GET', '/stream', [], null);
  const streamObject = objects.get(streamId);
  await waitFor(() => streamObject.reader !== null, 'stream reader');
  let cancelCalls = 0;
  const cancel = streamObject.reader.cancel.bind(streamObject.reader);
  streamObject.reader.cancel = (...args) => {{ cancelCalls += 1; return cancel(...args); }};
  GodotFetch.read(streamId);
  await waitFor(() => streamObject.chunks.length > 0, 'stream chunk');
  GodotFetch.free(streamId);
  if (cancelCalls !== 1) throw new Error(`reader cancel count ${{cancelCalls}}`);
  if (!streamObject.controller.signal.aborted) throw new Error('stream controller not aborted');

  await waitFor(async () => (await (await fetch('/state')).json()).streamClosed, 'stream socket close');
  const state = await (await fetch('/state')).json();
  if (state.redirectTargetHits !== 0) throw new Error('redirect target was reached');
  document.title = 'WEB_FETCH_BROWSER_PASSED';
  document.body.textContent = 'WEB_FETCH_BROWSER_PASSED';
}})().catch((error) => {{
  document.title = 'WEB_FETCH_BROWSER_FAILED';
  document.body.textContent = `WEB_FETCH_BROWSER_FAILED: ${{error.stack || error}}`;
}});
</script>"""
    return script.encode("utf-8")


def _handler_type(state: LoopbackState) -> type[BaseHTTPRequestHandler]:
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def handle(self) -> None:
            try:
                super().handle()
            except (BrokenPipeError, ConnectionResetError):
                return

        def do_GET(self) -> None:  # noqa: N802
            if self.path == "/test.html":
                body = _page(state.bridge)
                self._send(200, body, "text/html; charset=utf-8")
                return
            if self.path == "/redirect":
                state.redirect_hits += 1
                self.send_response(302)
                self.send_header("Location", "/redirect-target")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            if self.path == "/redirect-target":
                state.redirect_target_hits += 1
                self._send(200, b"unexpected", "text/plain")
                return
            if self.path == "/stream":
                self.send_response(200)
                self.send_header("Content-Type", "application/octet-stream")
                self.send_header("Transfer-Encoding", "chunked")
                self.end_headers()
                try:
                    while True:
                        chunk = bytes([7]) * 1024
                        self.wfile.write(f"{len(chunk):x}\r\n".encode("ascii"))
                        self.wfile.write(chunk + b"\r\n")
                        self.wfile.flush()
                        time.sleep(0.02)
                except (BrokenPipeError, ConnectionResetError):
                    state.stream_closed.set()
                return
            if self.path == "/state":
                body = json.dumps(
                    {
                        "redirectTargetHits": state.redirect_target_hits,
                        "streamClosed": state.stream_closed.is_set(),
                    }
                ).encode("utf-8")
                self._send(200, body, "application/json")
                return
            self._send(404, b"not found", "text/plain")

        def _send(self, status: int, body: bytes, content_type: str) -> None:
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, _format: str, *_args: object) -> None:
            return

    return Handler


def _free_loopback_port() -> int:
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return int(probe.getsockname()[1])


class _WebSocket:
    def __init__(self, url: str) -> None:
        parsed = urlparse(url)
        self.socket = socket.create_connection((parsed.hostname, parsed.port), timeout=5)
        key = base64.b64encode(os.urandom(16)).decode("ascii")
        path = parsed.path + (f"?{parsed.query}" if parsed.query else "")
        request = (
            f"GET {path} HTTP/1.1\r\n"
            f"Host: {parsed.hostname}:{parsed.port}\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\n\r\n"
        )
        self.socket.sendall(request.encode("ascii"))
        response = bytearray()
        while b"\r\n\r\n" not in response:
            response.extend(self.socket.recv(4096))
        if not response.startswith(b"HTTP/1.1 101"):
            raise RuntimeError(f"DevTools WebSocket upgrade failed: {response[:200]!r}")

    def close(self) -> None:
        self.socket.close()

    def send_json(self, value: dict[str, object]) -> None:
        payload = json.dumps(value, separators=(",", ":")).encode("utf-8")
        mask = os.urandom(4)
        header = bytearray([0x81])
        length = len(payload)
        if length < 126:
            header.append(0x80 | length)
        elif length <= 0xFFFF:
            header.append(0x80 | 126)
            header.extend(struct.pack("!H", length))
        else:
            header.append(0x80 | 127)
            header.extend(struct.pack("!Q", length))
        masked = bytes(byte ^ mask[index % 4] for index, byte in enumerate(payload))
        self.socket.sendall(header + mask + masked)

    def receive_json(self) -> dict[str, object]:
        while True:
            first, second = self._read_exact(2)
            opcode = first & 0x0F
            length = second & 0x7F
            if length == 126:
                length = struct.unpack("!H", self._read_exact(2))[0]
            elif length == 127:
                length = struct.unpack("!Q", self._read_exact(8))[0]
            mask = self._read_exact(4) if second & 0x80 else b""
            payload = self._read_exact(length)
            if mask:
                payload = bytes(
                    byte ^ mask[index % 4] for index, byte in enumerate(payload)
                )
            if opcode == 0x1:
                value = json.loads(payload)
                if isinstance(value, dict):
                    return value
            elif opcode == 0x8:
                raise RuntimeError("DevTools WebSocket closed unexpectedly")
            elif opcode == 0x9:
                self._send_control(0xA, payload)

    def _send_control(self, opcode: int, payload: bytes) -> None:
        mask = os.urandom(4)
        masked = bytes(byte ^ mask[index % 4] for index, byte in enumerate(payload))
        self.socket.sendall(bytes([0x80 | opcode, 0x80 | len(payload)]) + mask + masked)

    def _read_exact(self, length: int) -> bytes:
        chunks = bytearray()
        while len(chunks) < length:
            chunk = self.socket.recv(length - len(chunks))
            if not chunk:
                raise RuntimeError("DevTools WebSocket ended early")
            chunks.extend(chunk)
        return bytes(chunks)


def _wait_for_page_target(debug_port: int, page_url: str) -> str:
    deadline = time.monotonic() + 8
    endpoint = f"http://127.0.0.1:{debug_port}/json/list"
    while time.monotonic() < deadline:
        try:
            with urlopen(endpoint, timeout=1) as response:
                targets = json.load(response)
            for target in targets:
                if target.get("type") == "page" and target.get("url") == page_url:
                    return str(target["webSocketDebuggerUrl"])
        except (OSError, ValueError):
            pass
        time.sleep(0.05)
    raise RuntimeError("Chromium DevTools target did not become ready")


def _wait_for_browser_result(websocket_url: str) -> str:
    connection = _WebSocket(websocket_url)
    command_id = 0
    try:
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            command_id += 1
            connection.send_json(
                {
                    "id": command_id,
                    "method": "Runtime.evaluate",
                    "params": {
                        "expression": "document.body ? document.body.textContent : ''",
                        "returnByValue": True,
                    },
                }
            )
            while True:
                message = connection.receive_json()
                if message.get("id") != command_id:
                    continue
                result = message.get("result", {})
                remote = result.get("result", {}) if isinstance(result, dict) else {}
                text = remote.get("value", "") if isinstance(remote, dict) else ""
                if "WEB_FETCH_BROWSER_PASSED" in text:
                    return str(text)
                if "WEB_FETCH_BROWSER_FAILED" in text:
                    raise RuntimeError(str(text))
                break
            time.sleep(0.05)
    finally:
        connection.close()
    raise RuntimeError("timed out waiting for browser Fetch bridge result")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("index_js", type=Path)
    parser.add_argument("--chrome", help="path to a Chromium-family browser")
    args = parser.parse_args()

    try:
        verify_file(args.index_js)
        bridge = extract_bridge(args.index_js.read_text(encoding="utf-8"))
        chrome = _find_chrome(args.chrome)
        state = LoopbackState(bridge)
        server = ThreadingHTTPServer(("127.0.0.1", 0), _handler_type(state))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        process: subprocess.Popen[str] | None = None
        try:
            port = server.server_address[1]
            with tempfile.TemporaryDirectory() as directory:
                debug_port = _free_loopback_port()
                page_url = f"http://127.0.0.1:{port}/test.html"
                command = [
                    str(chrome),
                    "--headless=new",
                    "--disable-background-networking",
                    "--disable-component-update",
                    "--disable-default-apps",
                    "--disable-extensions",
                    "--no-default-browser-check",
                    "--no-first-run",
                    f"--user-data-dir={Path(directory) / 'profile'}",
                    "--remote-debugging-address=127.0.0.1",
                    f"--remote-debugging-port={debug_port}",
                    page_url,
                ]
                process = subprocess.Popen(
                    command,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                )
                try:
                    websocket_url = _wait_for_page_target(debug_port, page_url)
                    _wait_for_browser_result(websocket_url)
                finally:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=5)
                    process = None
        finally:
            if process is not None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

        if state.redirect_hits != 1 or state.redirect_target_hits != 0:
            raise RuntimeError(
                "redirect request escaped its original endpoint: "
                f"redirect={state.redirect_hits}, target={state.redirect_target_hits}"
            )
        if not state.stream_closed.is_set():
            raise RuntimeError("browser did not close the streamed request")
    except (FileNotFoundError, OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"WEB_FETCH_BROWSER_FAILED: {error}", file=sys.stderr)
        return 1

    print("WEB_FETCH_BROWSER_PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
