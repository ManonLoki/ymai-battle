#!/usr/bin/env python3
"""Key, tile-soften, and pixel-scale the main-menu parallax layers."""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageChops, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "backgrounds"
SESSION = Path(
    "/Users/manonloki/.grok/sessions/%2FUsers%2Fmanonloki%2FDocuments%2Fstudy%2Fgodot-game%2FStudy%2Fymai-battle/01a0b401-fbf6-7fe1-904d-643fea89f613/images"
)

# Generated files: 6=sky, 5=colosseum, 4=floor
LAYERS = [
    ("far.png", SESSION / "6.jpg", False),
    ("mid.png", SESSION / "5.jpg", True),
    ("near.png", SESSION / "4.jpg", True),
]

TARGET = (640, 360)


def is_key_pink(r: int, g: int, b: int) -> bool:
    # Generated plates used hot pink (~241,19,118), not #FF00FF.
    return r > 180 and g < 100 and r > g + 70 and r > b


def key_magenta(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if is_key_pink(r, g, b):
                px[x, y] = (0, 0, 0, 0)
    # Chew JPEG fringes next to already-keyed pixels.
    fringe = []
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0 or not (r > 140 and g < 130 and r > g + 40):
                continue
            for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and px[nx, ny][3] == 0:
                    fringe.append((x, y))
                    break
    for x, y in fringe:
        px[x, y] = (0, 0, 0, 0)
    return im


def make_h_tileable(im: Image.Image, blend: int = 48) -> Image.Image:
    """Soft-crossfade the left/right edges so horizontal wrap is less obvious."""
    w, h = im.size
    blend = min(blend, w // 4)
    out = im.copy()
    left = im.crop((0, 0, blend, h))
    right = im.crop((w - blend, 0, w, h))
    for i in range(blend):
        t = (i + 1) / float(blend)
        col_l = Image.new("RGBA", (1, h))
        col_r = Image.new("RGBA", (1, h))
        src_l = left.crop((i, 0, i + 1, h))
        src_r = right.crop((i, 0, i + 1, h))
        mixed_l = Image.blend(src_l, src_r, 1.0 - t)
        mixed_r = Image.blend(src_r, src_l, t)
        out.paste(mixed_l, (i, 0))
        out.paste(mixed_r, (w - blend + i, 0))
    return out


def pixel_scale(im: Image.Image) -> Image.Image:
    return im.resize(TARGET, Image.NEAREST)


def save_preview_2x1(path: Path, im: Image.Image) -> None:
    w, h = im.size
    sheet = Image.new("RGBA", (w * 2, h), (13, 17, 23, 255))
    sheet.paste(im, (0, 0), im)
    sheet.paste(im, (w, 0), im)
    sheet.save(path)


def bake() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, src, do_key in LAYERS:
        im = Image.open(src).convert("RGBA")
        if do_key:
            im = key_magenta(im)
        im = pixel_scale(im)
        if name == "far.png":
            im = make_h_tileable(im, blend=64)
        dest = OUT / name
        im.save(dest, "PNG")
        preview_dir = Path("/var/folders/7t/63gnjwn559g78v2clhl2dm0w0000gn/T/grok-goal-8c5e6670ac04/implementer")
        preview_dir.mkdir(parents=True, exist_ok=True)
        save_preview_2x1(preview_dir / f"preview_{name}", im)
        opaque = 0
        for p in im.getdata():
            if p[3] > 127:
                opaque += 1
        print("wrote", dest, im.size, "opaque", opaque)


if __name__ == "__main__":
    bake()
