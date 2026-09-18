#!/usr/bin/env python3
"""Bake 32x32 pixel icons for agent buffs and random skills."""
from __future__ import annotations

import os
import struct
import zlib

SIZE = 32
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "icons")


def write_png(path: str, pixels: list[list[tuple[int, int, int, int]]]) -> None:
    raw = b""
    for row in pixels:
        raw += b"\x00"
        for r, g, b, a in row:
            raw += bytes((r, g, b, a))
    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def canvas(bg: tuple[int, int, int, int]) -> list[list[tuple[int, int, int, int]]]:
    return [[bg for _ in range(SIZE)] for _ in range(SIZE)]


def px(img, x: int, y: int, c: tuple[int, int, int, int]) -> None:
    if 0 <= x < SIZE and 0 <= y < SIZE:
        img[y][x] = c


def fill(img, x: int, y: int, w: int, h: int, c: tuple[int, int, int, int]) -> None:
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            px(img, xx, yy, c)


def rect(img, x: int, y: int, w: int, h: int, c: tuple[int, int, int, int]) -> None:
    fill(img, x, y, w, 1, c)
    fill(img, x, y + h - 1, w, 1, c)
    fill(img, x, y, 1, h, c)
    fill(img, x + w - 1, y, 1, h, c)


def rounded_tile(bg: tuple[int, int, int], ink: tuple[int, int, int]) -> list:
    img = canvas((0, 0, 0, 0))
    fill(img, 2, 2, 28, 28, (*bg, 255))
    fill(img, 3, 1, 26, 1, (*bg, 255))
    fill(img, 3, 30, 26, 1, (*bg, 255))
    fill(img, 1, 3, 1, 26, (*bg, 255))
    fill(img, 30, 3, 1, 26, (*bg, 255))
    rect(img, 2, 2, 28, 28, (*ink, 255))
    return img


def star(img, cx: int, cy: int, c) -> None:
    fill(img, cx, cy - 6, 2, 13, c)
    fill(img, cx - 6, cy, 13, 2, c)
    fill(img, cx - 3, cy - 3, 8, 2, c)
    fill(img, cx - 3, cy + 2, 8, 2, c)


def bake() -> None:
    icons: dict[str, list] = {}

    # Agent buffs
    img = rounded_tile((18, 90, 110), (90, 230, 245))
    star(img, 15, 15, (255, 240, 120, 255))
    icons["buff_codex"] = img

    img = rounded_tile((120, 70, 20), (255, 180, 80))
    rect(img, 10, 10, 12, 12, (255, 230, 180, 255))
    fill(img, 15, 6, 2, 20, (255, 230, 180, 255))
    fill(img, 6, 15, 20, 2, (255, 230, 180, 255))
    icons["buff_claude"] = img

    img = rounded_tile((70, 30, 110), (210, 150, 255))
    fill(img, 8, 18, 16, 3, (230, 200, 255, 255))
    fill(img, 18, 10, 8, 8, (230, 200, 255, 255))
    fill(img, 6, 12, 6, 6, (180, 120, 230, 255))
    icons["buff_grok"] = img

    img = rounded_tile((20, 80, 40), (120, 220, 130))
    fill(img, 8, 12, 16, 12, (180, 255, 190, 255))
    fill(img, 10, 8, 12, 6, (180, 255, 190, 255))
    fill(img, 14, 16, 4, 6, (20, 80, 40, 255))
    icons["buff_workbuddy"] = img

    # Skills
    img = rounded_tile((40, 24, 16), (255, 170, 60))
    star(img, 15, 15, (255, 220, 80, 255))
    icons["skill_crit"] = img

    img = rounded_tile((24, 28, 70), (140, 190, 255))
    fill(img, 7, 16, 14, 3, (200, 220, 255, 255))
    fill(img, 20, 8, 6, 10, (200, 220, 255, 255))
    icons["skill_dodge"] = img

    img = rounded_tile((70, 40, 12), (255, 200, 90))
    rect(img, 11, 11, 10, 10, (255, 230, 160, 255))
    fill(img, 15, 6, 2, 20, (255, 230, 160, 255))
    fill(img, 6, 15, 20, 2, (255, 230, 160, 255))
    icons["skill_hit"] = img

    img = rounded_tile((20, 50, 70), (80, 200, 230))
    fill(img, 8, 12, 16, 12, (140, 230, 255, 255))
    fill(img, 10, 8, 12, 5, (140, 230, 255, 255))
    icons["skill_dr"] = img

    img = rounded_tile((80, 20, 20), (255, 90, 90))
    fill(img, 14, 7, 4, 18, (255, 160, 140, 255))
    fill(img, 7, 14, 18, 4, (255, 160, 140, 255))
    icons["skill_dmg"] = img

    img = rounded_tile((50, 30, 10), (255, 160, 70))
    fill(img, 6, 12, 8, 8, (255, 210, 140, 255))
    fill(img, 18, 12, 8, 8, (255, 210, 140, 255))
    fill(img, 14, 14, 4, 4, (255, 180, 80, 255))
    icons["skill_double"] = img

    img = rounded_tile((60, 20, 40), (255, 120, 180))
    fill(img, 5, 13, 6, 6, (255, 190, 210, 255))
    fill(img, 13, 13, 6, 6, (255, 190, 210, 255))
    fill(img, 21, 13, 6, 6, (255, 190, 210, 255))
    icons["skill_triple"] = img

    img = rounded_tile((40, 30, 20), (210, 170, 90))
    fill(img, 8, 18, 16, 4, (230, 200, 120, 255))
    fill(img, 10, 10, 3, 10, (230, 200, 120, 255))
    fill(img, 19, 10, 3, 10, (230, 200, 120, 255))
    icons["skill_root"] = img

    img = rounded_tile((30, 70, 20), (80, 220, 90))
    fill(img, 14, 6, 4, 14, (140, 255, 150, 255))
    fill(img, 12, 20, 8, 6, (140, 255, 150, 255))
    px(img, 16, 8, (30, 70, 20, 255))
    icons["skill_poison"] = img

    img = rounded_tile((40, 40, 80), (180, 180, 255))
    fill(img, 8, 14, 16, 6, (210, 210, 255, 255))
    fill(img, 12, 8, 8, 16, (160, 160, 230, 255))
    icons["skill_paralyze"] = img

    img = rounded_tile((70, 20, 70), (240, 120, 220))
    fill(img, 8, 10, 6, 12, (255, 180, 240, 255))
    fill(img, 18, 10, 6, 12, (255, 180, 240, 255))
    fill(img, 14, 16, 4, 4, (255, 80, 180, 255))
    icons["skill_confuse"] = img

    img = rounded_tile((20, 40, 80), (90, 200, 255))
    fill(img, 8, 10, 16, 14, (140, 220, 255, 255))
    fill(img, 12, 14, 8, 8, (20, 40, 80, 255))
    icons["skill_guard"] = img

    img = rounded_tile((90, 40, 10), (255, 140, 40))
    fill(img, 10, 16, 12, 8, (255, 180, 80, 255))
    fill(img, 14, 8, 4, 10, (255, 220, 120, 255))
    fill(img, 12, 10, 8, 3, (255, 220, 120, 255))
    icons["skill_rebirth"] = img

    img = rounded_tile((80, 30, 20), (255, 110, 70))
    fill(img, 8, 14, 10, 6, (255, 180, 120, 255))
    fill(img, 16, 8, 8, 16, (255, 180, 120, 255))
    fill(img, 18, 6, 8, 4, (255, 220, 160, 255))
    icons["skill_counter"] = img

    img = rounded_tile((90, 16, 28), (255, 80, 110))
    fill(img, 10, 8, 4, 16, (255, 150, 160, 255))
    fill(img, 18, 8, 4, 16, (255, 150, 160, 255))
    fill(img, 10, 20, 12, 4, (255, 90, 110, 255))
    icons["skill_lifesteal"] = img

    img = rounded_tile((16, 80, 40), (80, 230, 140))
    fill(img, 14, 7, 4, 18, (140, 255, 180, 255))
    fill(img, 7, 14, 18, 4, (140, 255, 180, 255))
    icons["skill_heal"] = img

    os.makedirs(OUT, exist_ok=True)
    for name, image in icons.items():
        path = os.path.join(OUT, f"{name}.png")
        write_png(path, image)
        print("wrote", path)
    print("count", len(icons))


if __name__ == "__main__":
    bake()
