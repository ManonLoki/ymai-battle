#!/usr/bin/env python3
"""Deterministically harden Godot 4.7.2's generated Web Fetch bridge."""

from __future__ import annotations

import hashlib
import os
from pathlib import Path
import tempfile


BRIDGE_START = "var GodotFetch="
BRIDGE_END = ";function _godot_js_fetch_create"
GODOT_4_7_2_BRIDGE_SHA256 = (
    "bd68c0999474f1b08674ddec8b7afe3bcda16b5f7c3a65dd88cce0d3a8ce8cfa"
)

# Keep this compact so the replacement is identical in threaded and non-threaded
# templates. The surrounding bridge is matched by an exact Godot 4.7.2 digest.
PATCHED_GODOT_FETCH = (
    'var GodotFetch={onread:function(id,result){const obj=IDHandler.get(id);'
    'if(!obj){return}if(result.value){obj.chunks.push(result.value)}obj.reading=false;'
    'obj.done=result.done},onresponse:function(id,response){const obj=IDHandler.get(id);'
    'if(!obj){if(response.body){response.body.cancel().catch(function(e){})}return}'
    'let chunked=false;response.headers.forEach(function(value,header){'
    'const v=value.toLowerCase().trim();const h=header.toLowerCase().trim();'
    'if(h==="transfer-encoding"&&v==="chunked"){chunked=true}});'
    'obj.status=response.status;obj.response=response;obj.reader=response.body?.getReader();'
    'obj.chunked=chunked},onerror:function(id,err){const obj=IDHandler.get(id);'
    'if(!obj){return}GodotRuntime.error(err);obj.error=err},'
    'create:function(method,url,headers,body){const controller=new AbortController();'
    'const obj={request:null,response:null,reader:null,controller:controller,error:null,'
    'done:false,reading:false,status:0,chunks:[]};const id=IDHandler.add(obj);'
    'const init={method,headers,body,redirect:"error",signal:controller.signal};'
    'obj.request=fetch(url,init);obj.request.then(GodotFetch.onresponse.bind(null,id))'
    '.catch(GodotFetch.onerror.bind(null,id));return id},free:function(id){'
    'const obj=IDHandler.get(id);if(!obj){return}IDHandler.remove(id);'
    'if(obj.reader){obj.reader.cancel().catch(function(e){})}obj.controller.abort()},'
    'read:function(id){const obj=IDHandler.get(id);if(!obj){return}'
    'if(obj.reader&&!obj.reading){if(obj.done){obj.reader=null;return}obj.reading=true;'
    'obj.reader.read().then(GodotFetch.onread.bind(null,id))'
    '.catch(GodotFetch.onerror.bind(null,id))}'
    'else if(obj.reader==null&&obj.response.body==null){obj.reading=true;'
    'GodotFetch.onread(id,{value:undefined,done:true})}}}'
)


class BridgePatchError(RuntimeError):
    """The generated engine bridge did not match the locked input or output."""


def _bridge_bounds(source: str) -> tuple[int, int]:
    if source.count(BRIDGE_START) != 1 or source.count(BRIDGE_END) != 1:
        raise BridgePatchError("expected exactly one GodotFetch bridge")
    start = source.index(BRIDGE_START)
    end = source.index(BRIDGE_END, start)
    if end <= start:
        raise BridgePatchError("GodotFetch bridge markers are out of order")
    return start, end


def extract_bridge(source: str) -> str:
    """Return only the generated GodotFetch object, excluding the next function."""

    start, end = _bridge_bounds(source)
    return source[start:end]


def patch_source(source: str) -> str:
    """Replace the exact stock 4.7.2 bridge or fail without changing the input."""

    start, end = _bridge_bounds(source)
    original = source[start:end]
    digest = hashlib.sha256(original.encode("utf-8")).hexdigest()
    if digest != GODOT_4_7_2_BRIDGE_SHA256:
        raise BridgePatchError(
            "generated GodotFetch bridge changed; "
            f"expected sha256 {GODOT_4_7_2_BRIDGE_SHA256}, got {digest}"
        )
    patched = source[:start] + PATCHED_GODOT_FETCH + source[end:]
    verify_source(patched)
    return patched


def verify_source(source: str) -> None:
    """Verify the complete hardened bridge, not just individual keywords."""

    bridge = extract_bridge(source)
    if bridge != PATCHED_GODOT_FETCH:
        digest = hashlib.sha256(bridge.encode("utf-8")).hexdigest()
        raise BridgePatchError(
            "generated GodotFetch bridge is not the locked hardened bridge "
            f"(sha256 {digest})"
        )
    required = (
        'redirect:"error"',
        "new AbortController()",
        "signal:controller.signal",
        "obj.reader.cancel()",
        "obj.controller.abort()",
        "response.body.cancel()",
    )
    missing = [fragment for fragment in required if fragment not in bridge]
    if missing:
        raise BridgePatchError(f"hardened bridge is missing: {', '.join(missing)}")
    if "response.abort()" in bridge:
        raise BridgePatchError("obsolete non-existent Response.abort() remains")


def patch_file(path: Path) -> None:
    """Patch one generated JavaScript file atomically."""

    source = path.read_bytes().decode("utf-8")
    patched = patch_source(source).encode("utf-8")
    mode = path.stat().st_mode
    temporary: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="wb", prefix=f".{path.name}.", dir=path.parent, delete=False
        ) as handle:
            handle.write(patched)
            handle.flush()
            os.fsync(handle.fileno())
            temporary = Path(handle.name)
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def verify_file(path: Path) -> None:
    verify_source(path.read_bytes().decode("utf-8"))
