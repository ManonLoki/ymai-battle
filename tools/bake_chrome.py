#!/usr/bin/env python3
"""Bake the app icon and the 32x32 arrow / pressed mouse cursors."""
from __future__ import annotations

import os
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CURSOR_DIR = ROOT / "assets" / "cursors"
ICON_PATH = ROOT / "icon.png"
FIGHTER = ROOT / "assets" / "characters" / "fighter_4_idle_crown.png"

# ThemeHelper / SpriteFactory palette
OUT = (11, 28, 36, 255)
GOLD = (212, 160, 23, 255)
GOLD_HI = (250, 214, 31, 255)
GOLD_DK = (160, 110, 16, 255)
CYAN = (62, 200, 224, 255)
CYAN_HI = (138, 230, 245, 255)
CYAN_DK = (26, 111, 134, 255)
TEAL = (18, 80, 98, 255)
BG = (13, 17, 23, 255)
TRANSPARENT = (0, 0, 0, 0)

CURSOR_SIZE = 32

# Classic pointer. Tip is the first '1'. 1=outline 2=gold 3=fill 4=highlight
ARROW_ART = """
1
11
121
1231
12321
123321
1233321
12333321
123333321
1233333321
12333333321
123333333321
1233331111111
1233211
123211
1211.11
111...11
1......11
........1
""".strip(
    "\n"
)


def write_png(path: Path, pixels: list[list[tuple[int, int, int, int]]]) -> None:
    height = len(pixels)
    width = len(pixels[0])
    raw = b""
    for row in pixels:
        raw += b"\x00"
        for r, g, b, a in row:
            raw += bytes((r, g, b, a))
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def canvas(size: int, bg: tuple[int, int, int, int]) -> list[list[tuple[int, int, int, int]]]:
    return [[bg for _ in range(size)] for _ in range(size)]


def px(img: list, x: int, y: int, c: tuple[int, int, int, int]) -> None:
    if 0 <= x < len(img[0]) and 0 <= y < len(img):
        img[y][x] = c


def draw_art(img: list, art: str, ox: int, oy: int, palette: dict[str, tuple[int, int, int, int]]) -> None:
    for y, line in enumerate(art.splitlines()):
        for x, ch in enumerate(line.rstrip()):
            if ch in palette:
                px(img, ox + x, oy + y, palette[ch])


def scale_nearest(img: list, factor: int) -> list:
    h = len(img)
    w = len(img[0])
    out = canvas(w * factor, TRANSPARENT)
    for y in range(h):
        for x in range(w):
            c = img[y][x]
            for dy in range(factor):
                for dx in range(factor):
                    out[y * factor + dy][x * factor + dx] = c
    return out


def blit(dst: list, src: list, ox: int, oy: int) -> None:
    for y, row in enumerate(src):
        for x, c in enumerate(row):
            if c[3] > 0:
                px(dst, ox + x, oy + y, c)


def load_png_rgba(path: Path) -> list[list[tuple[int, int, int, int]]]:
    from PIL import Image

    im = Image.open(path).convert("RGBA")
    w, h = im.size
    data = list(im.getdata())
    rows: list[list[tuple[int, int, int, int]]] = []
    i = 0
    for _y in range(h):
        row = []
        for _x in range(w):
            row.append(data[i])
            i += 1
        rows.append(row)
    return rows


def bake_cursors() -> None:
    arrow_pal = {"1": OUT, "2": GOLD, "3": CYAN, "4": CYAN_HI}
    pressed_pal = {"1": OUT, "2": GOLD_DK, "3": CYAN_DK, "4": TEAL}
    arrow = canvas(CURSOR_SIZE, TRANSPARENT)
    pressed = canvas(CURSOR_SIZE, TRANSPARENT)
    draw_art(arrow, ARROW_ART, 1, 1, arrow_pal)
    draw_art(pressed, ARROW_ART, 1, 1, pressed_pal)
    # Pressed state: inset the fill one pixel so geometry of the outline stays,
    # but the click is readable at a glance.
    for y, line in enumerate(ARROW_ART.splitlines()):
        for x, ch in enumerate(line.rstrip()):
            if ch == "3":
                left = line[x - 1] if x > 0 else "1"
                up_line = ARROW_ART.splitlines()[y - 1] if y > 0 else ""
                up = up_line[x] if x < len(up_line) else "1"
                if left == "2" or up == "2" or left == "1":
                    px(pressed, 1 + x, 1 + y, TEAL)
    CURSOR_DIR.mkdir(parents=True, exist_ok=True)
    write_png(CURSOR_DIR / "arrow.png", arrow)
    write_png(CURSOR_DIR / "pressed.png", pressed)
    print("wrote", CURSOR_DIR / "arrow.png")
    print("wrote", CURSOR_DIR / "pressed.png")


def rounded_tile(size: int) -> list:
    img = canvas(size, TRANSPARENT)
    margin = 2
    for y in range(margin, size - margin):
        for x in range(margin, size - margin):
            corner = 3
            on_corner = (
                (x < margin + corner and y < margin + corner and (margin + corner - x) + (margin + corner - y) > corner + 1)
                or (x >= size - margin - corner and y < margin + corner and (x - (size - margin - corner - 1)) + (margin + corner - y) > corner + 1)
                or (x < margin + corner and y >= size - margin - corner and (margin + corner - x) + (y - (size - margin - corner - 1)) > corner + 1)
                or (
                    x >= size - margin - corner
                    and y >= size - margin - corner
                    and (x - (size - margin - corner - 1)) + (y - (size - margin - corner - 1)) > corner + 1
                )
            )
            if on_corner:
                continue
            img[y][x] = BG
    # gold frame
    for y in range(size):
        for x in range(size):
            if img[y][x][3] == 0:
                continue
            edge = False
            for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                ny, nx = y + dy, x + dx
                if ny < 0 or nx < 0 or ny >= size or nx >= size or img[ny][nx][3] == 0:
                    edge = True
                    break
            if edge:
                img[y][x] = GOLD if (x + y) % 7 != 0 else GOLD_HI
    return img


def bake_icon_from_fighter() -> list:
    tile = rounded_tile(32)
    if not FIGHTER.is_file():
        raise FileNotFoundError(f"icon fighter sprite is missing: {FIGHTER}")
    fighter = load_png_rgba(FIGHTER)
    blit(tile, fighter, 0, 0)
    return scale_nearest(tile, 8)


def bake_icon() -> None:
    if ICON_PATH.exists():
        print("keep", ICON_PATH)
        return
    pixels = bake_icon_from_fighter()
    write_png(ICON_PATH, pixels)
    print("wrote", ICON_PATH, "from fighter sprite")


def bake() -> None:
    bake_cursors()
    bake_icon()


if __name__ == "__main__":
    bake()
