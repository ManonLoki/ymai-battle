#!/usr/bin/env python3
"""Bake 32x32 pixel icons for agent buffs and random skills.

Skill icons share a border color per family so the set reads as five frames:
self / defense / status / recover / technique. Inner glyphs are unique per
skill and should read as that skill's effect at 32px.
"""
from __future__ import annotations

import math
import os
import struct
import zlib

SIZE = 32
SKULL_SIZE = 32
ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "assets", "icons")
FX_OUT = os.path.join(ROOT, "assets", "fx")

# Outer-ring ink. Tests sample (2, 16); same family MUST use the identical tuple.
FAMILY_INK = {
    "self": (232, 176, 48),
    "defense": (64, 140, 210),
    "status": (168, 64, 220),
    "recover": (40, 180, 110),
    "technique": (220, 48, 64),
}


def write_png(path: str, pixels: list[list[tuple[int, int, int, int]]]) -> None:
    height = len(pixels)
    width = len(pixels[0]) if pixels else 0
    raw = b""
    for row in pixels:
        raw += b"\x00"
        for r, g, b, a in row:
            raw += bytes((r, g, b, a))
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def canvas(bg: tuple[int, int, int, int], size: int = SIZE) -> list[list[tuple[int, int, int, int]]]:
    return [[bg for _ in range(size)] for _ in range(size)]


def px(img, x: int, y: int, c: tuple[int, int, int, int]) -> None:
    h = len(img)
    w = len(img[0]) if img else 0
    if 0 <= x < w and 0 <= y < h:
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


def line(img, x0: int, y0: int, x1: int, y1: int, c, thickness: int = 1) -> None:
    dx = abs(x1 - x0)
    dy = abs(y1 - y0)
    sx = 1 if x0 < x1 else -1
    sy = 1 if y0 < y1 else -1
    err = dx - dy
    x, y = x0, y0
    while True:
        if thickness <= 1:
            px(img, x, y, c)
        else:
            r = thickness // 2
            fill(img, x - r, y - r, thickness, thickness, c)
        if x == x1 and y == y1:
            break
        e2 = 2 * err
        if e2 > -dy:
            err -= dy
            x += sx
        if e2 < dx:
            err += dx
            y += sy


def disc(img, cx: int, cy: int, r: int, c) -> None:
    for yy in range(cy - r, cy + r + 1):
        for xx in range(cx - r, cx + r + 1):
            if (xx - cx) * (xx - cx) + (yy - cy) * (yy - cy) <= r * r:
                px(img, xx, yy, c)


def ring(img, cx: int, cy: int, r: int, c) -> None:
    for yy in range(cy - r, cy + r + 1):
        for xx in range(cx - r, cx + r + 1):
            d2 = (xx - cx) * (xx - cx) + (yy - cy) * (yy - cy)
            if (r - 1) * (r - 1) <= d2 <= r * r + r:
                px(img, xx, yy, c)


def diamond(img, cx: int, cy: int, rx: int, ry: int, c) -> None:
    for yy in range(cy - ry, cy + ry + 1):
        for xx in range(cx - rx, cx + rx + 1):
            if abs(xx - cx) * ry + abs(yy - cy) * rx <= rx * ry:
                px(img, xx, yy, c)


def rounded_tile(bg: tuple[int, int, int], ink: tuple[int, int, int]) -> list:
    img = canvas((0, 0, 0, 0))
    fill(img, 2, 2, 28, 28, (*bg, 255))
    fill(img, 3, 1, 26, 1, (*bg, 255))
    fill(img, 3, 30, 26, 1, (*bg, 255))
    fill(img, 1, 3, 1, 26, (*bg, 255))
    fill(img, 30, 3, 1, 26, (*bg, 255))
    rect(img, 2, 2, 28, 28, (*ink, 255))
    return img


def family_tile(family: str, bg: tuple[int, int, int]) -> list:
    return rounded_tile(bg, FAMILY_INK[family])


def star(img, cx: int, cy: int, c) -> None:
    fill(img, cx, cy - 6, 2, 13, c)
    fill(img, cx - 6, cy, 13, 2, c)
    fill(img, cx - 3, cy - 3, 8, 2, c)
    fill(img, cx - 3, cy + 2, 8, 2, c)


def bake_skull() -> list:
    img = canvas((0, 0, 0, 0), SKULL_SIZE)
    red = (220, 24, 28, 255)
    dark = (90, 8, 10, 255)
    xcol = (255, 40, 36, 255)
    fill(img, 8, 6, 16, 14, red)
    fill(img, 10, 4, 12, 4, red)
    fill(img, 10, 18, 12, 6, red)
    fill(img, 12, 24, 8, 3, red)
    fill(img, 11, 10, 4, 4, dark)
    fill(img, 17, 10, 4, 4, dark)
    fill(img, 15, 15, 2, 3, dark)
    fill(img, 12, 22, 2, 3, dark)
    fill(img, 18, 22, 2, 3, dark)
    for i in range(22):
        px(img, 6 + i, 5 + i, xcol)
        px(img, 7 + i, 5 + i, xcol)
        px(img, 25 - i, 5 + i, xcol)
        px(img, 24 - i, 5 + i, xcol)
    return img


def bake() -> None:
    icons: dict[str, list] = {}

    # Agent buffs keep their own frames (not part of the five skill families).
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

    gold = (255, 220, 80, 255)
    hot = (255, 150, 40, 255)
    white = (255, 245, 220, 255)

    # --- self: gold frame ---
    # 暴击：八向爆裂 + 热核，不是十字。
    img = family_tile("self", (48, 28, 12))
    disc(img, 16, 16, 3, hot)
    disc(img, 16, 16, 1, white)
    for dx, dy in ((0, 1), (1, 0), (1, 1), (1, -1)):
        line(img, 16 - dx * 8, 16 - dy * 8, 16 + dx * 8, 16 + dy * 8, gold, 2)
    fill(img, 15, 6, 2, 3, white)
    fill(img, 15, 23, 2, 3, white)
    fill(img, 6, 15, 3, 2, white)
    fill(img, 23, 15, 3, 2, white)
    icons["skill_crit"] = img

    # 命中：准星圆环 + 中心点。
    img = family_tile("self", (70, 40, 12))
    ring(img, 16, 16, 8, (255, 230, 160, 255))
    ring(img, 16, 16, 5, (255, 200, 90, 255))
    fill(img, 16, 8, 1, 16, gold)
    fill(img, 8, 16, 16, 1, gold)
    disc(img, 16, 16, 2, (255, 80, 40, 255))
    icons["skill_hit"] = img

    # 增伤：朝上的剑。
    img = family_tile("self", (80, 20, 20))
    blade = (255, 160, 140, 255)
    steel = (230, 230, 235, 255)
    diamond(img, 16, 8, 4, 5, steel)
    fill(img, 14, 10, 4, 12, blade)
    fill(img, 10, 20, 12, 3, gold)
    fill(img, 15, 22, 2, 5, (180, 90, 50, 255))
    icons["skill_dmg"] = img

    # --- defense: steel-blue frame ---
    ice = (200, 220, 255, 255)
    mid = (140, 190, 255, 255)
    # 闪避：三个错开的残影人。
    img = family_tile("defense", (24, 28, 70))
    for i, ox in enumerate((7, 13, 19)):
        if i == 0:
            col = (90, 130, 190, 255)
        elif i == 1:
            col = (140, 180, 230, 255)
        else:
            col = ice
        fill(img, ox, 10, 5, 5, col)
        fill(img, ox + 1, 15, 3, 8, col)
        fill(img, ox, 22, 2, 4, col)
        fill(img, ox + 3, 22, 2, 4, col)
    icons["skill_dodge"] = img

    # 减伤：菱形小盾。
    img = family_tile("defense", (20, 50, 70))
    diamond(img, 16, 16, 8, 10, mid)
    diamond(img, 16, 16, 5, 7, ice)
    fill(img, 15, 13, 2, 6, (20, 50, 70, 255))
    icons["skill_dr"] = img

    # 绝对防御：板甲大盾，横带纹。
    img = family_tile("defense", (20, 40, 80))
    fill(img, 8, 8, 16, 18, mid)
    fill(img, 10, 7, 12, 2, ice)
    fill(img, 10, 25, 12, 2, ice)
    fill(img, 8, 12, 16, 2, ice)
    fill(img, 8, 18, 16, 2, ice)
    disc(img, 16, 16, 3, (20, 40, 80, 255))
    disc(img, 16, 16, 1, ice)
    icons["skill_guard"] = img

    # --- status: violet frame ---
    # 中毒：圆瓶 + 滴液。
    img = family_tile("status", (36, 16, 16))
    vial = (80, 220, 90, 255)
    drip = (255, 70, 70, 255)
    fill(img, 14, 6, 4, 3, (200, 200, 210, 255))
    fill(img, 13, 8, 6, 2, (200, 200, 210, 255))
    disc(img, 16, 16, 6, vial)
    disc(img, 16, 16, 3, (40, 90, 40, 255))
    disc(img, 16, 24, 2, drip)
    disc(img, 12, 26, 1, drip)
    icons["skill_poison"] = img

    # 麻痹：闪电折线。
    img = family_tile("status", (40, 40, 24))
    bolt = (255, 230, 80, 255)
    line(img, 18, 6, 12, 14, bolt, 3)
    line(img, 12, 14, 20, 16, bolt, 3)
    line(img, 20, 16, 11, 26, bolt, 3)
    fill(img, 10, 25, 4, 2, (255, 210, 40, 255))
    icons["skill_paralyze"] = img

    # 混乱：螺旋 + 头顶两点。
    img = family_tile("status", (70, 20, 70))
    swirl = (255, 180, 240, 255)
    for i, (r, a0) in enumerate(((3, 0), (5, 2), (7, 4), (9, 1))):
        for t in range(10):
            ang = (a0 + t) * 0.7
            xx = int(round(16 + r * math.cos(ang)))
            yy = int(round(16 + r * math.sin(ang)))
            disc(img, xx, yy, 1, swirl)
    disc(img, 11, 8, 2, (255, 80, 180, 255))
    disc(img, 21, 8, 2, (255, 80, 180, 255))
    icons["skill_confuse"] = img

    # 定身：脚铐 + 地根。
    img = family_tile("status", (40, 30, 20))
    iron = (230, 200, 120, 255)
    fill(img, 8, 18, 16, 3, iron)
    fill(img, 9, 12, 4, 8, iron)
    fill(img, 19, 12, 4, 8, iron)
    fill(img, 10, 10, 2, 3, (200, 160, 80, 255))
    fill(img, 20, 10, 2, 3, (200, 160, 80, 255))
    line(img, 8, 24, 6, 27, iron, 2)
    line(img, 16, 21, 16, 27, iron, 2)
    line(img, 24, 24, 26, 27, iron, 2)
    icons["skill_root"] = img

    # --- recover: mint frame ---
    # 浴火重生：火焰里的翼形。
    img = family_tile("recover", (90, 40, 10))
    flame = (255, 140, 40, 255)
    wing = (255, 220, 120, 255)
    disc(img, 16, 18, 6, flame)
    fill(img, 15, 8, 2, 10, wing)
    line(img, 16, 14, 7, 20, wing, 2)
    line(img, 16, 14, 25, 20, wing, 2)
    line(img, 16, 12, 8, 10, wing, 2)
    line(img, 16, 12, 24, 10, wing, 2)
    disc(img, 16, 10, 2, (255, 255, 200, 255))
    icons["skill_rebirth"] = img

    # 吸血：心形 + 两颗獠牙。
    img = family_tile("recover", (90, 16, 28))
    blood = (255, 70, 90, 255)
    fang = (255, 230, 230, 255)
    disc(img, 12, 13, 4, blood)
    disc(img, 20, 13, 4, blood)
    diamond(img, 16, 20, 8, 8, blood)
    fill(img, 12, 10, 3, 6, fang)
    fill(img, 17, 10, 3, 6, fang)
    px(img, 13, 15, blood)
    px(img, 18, 15, blood)
    icons["skill_lifesteal"] = img

    # 治疗：圆底上的医十字（和其他十字技能形状不同：有圆垫）。
    img = family_tile("recover", (16, 80, 40))
    disc(img, 16, 16, 8, (40, 140, 80, 255))
    plus = (140, 255, 180, 255)
    fill(img, 14, 8, 4, 16, plus)
    fill(img, 8, 14, 16, 4, plus)
    icons["skill_heal"] = img

    # --- technique: crimson frame ---
    slash = (255, 210, 140, 255)
    # 二连击：两道平行斩击。
    img = family_tile("technique", (50, 30, 10))
    line(img, 8, 10, 22, 22, slash, 3)
    line(img, 10, 7, 24, 19, (255, 160, 80, 255), 3)
    icons["skill_double"] = img

    # 三连击：三道扇形斩击。
    img = family_tile("technique", (60, 20, 40))
    line(img, 8, 20, 24, 8, (255, 190, 210, 255), 3)
    line(img, 8, 16, 24, 16, slash, 3)
    line(img, 8, 12, 24, 24, (255, 120, 80, 255), 3)
    icons["skill_triple"] = img

    # 反击：回勾箭头。
    img = family_tile("technique", (80, 30, 20))
    arrow = (255, 180, 120, 255)
    line(img, 22, 10, 10, 10, arrow, 3)
    line(img, 10, 10, 10, 22, arrow, 3)
    line(img, 10, 22, 22, 22, arrow, 3)
    line(img, 22, 22, 18, 18, arrow, 3)
    line(img, 22, 22, 18, 26, arrow, 3)
    icons["skill_counter"] = img

    # 幻影刺杀：头骨轮廓 + 斜插匕首。
    img = family_tile("technique", (40, 8, 12))
    bone = (255, 80, 80, 255)
    disc(img, 14, 13, 5, bone)
    fill(img, 11, 17, 6, 4, bone)
    fill(img, 12, 12, 2, 2, (40, 8, 12, 255))
    fill(img, 16, 12, 2, 2, (40, 8, 12, 255))
    line(img, 18, 8, 26, 24, (230, 230, 230, 255), 2)
    fill(img, 17, 7, 4, 3, (200, 160, 80, 255))
    line(img, 10, 10, 20, 22, (255, 40, 36, 255), 1)
    line(img, 20, 10, 10, 22, (255, 40, 36, 255), 1)
    icons["skill_assassinate"] = img

    # 凌波微步：脚印 + 涟漪弧。
    img = family_tile("technique", (16, 24, 48))
    foot = (255, 230, 160, 255)
    wave = (160, 200, 255, 255)
    fill(img, 10, 14, 5, 8, foot)
    disc(img, 12, 13, 3, foot)
    fill(img, 9, 21, 2, 3, foot)
    fill(img, 14, 21, 2, 3, foot)
    ring(img, 17, 16, 5, wave)
    ring(img, 19, 14, 7, (120, 160, 255, 255))
    icons["skill_lingbo"] = img

    # 潜能激发：小人两侧上升的能量柱，和暴击的八向星芒分开。
    img = family_tile("technique", (48, 16, 8))
    body = (255, 220, 120, 255)
    low = (255, 70, 40, 255)
    mid = (255, 160, 50, 255)
    high = (255, 230, 80, 255)
    disc(img, 16, 10, 3, body)
    fill(img, 14, 13, 4, 8, body)
    fill(img, 12, 14, 2, 5, body)
    fill(img, 18, 14, 2, 5, body)
    fill(img, 13, 21, 2, 5, body)
    fill(img, 17, 21, 2, 5, body)
    fill(img, 7, 20, 3, 6, low)
    fill(img, 7, 14, 3, 6, mid)
    fill(img, 7, 8, 3, 6, high)
    fill(img, 22, 20, 3, 6, low)
    fill(img, 22, 14, 3, 6, mid)
    fill(img, 22, 8, 3, 6, high)
    icons["skill_awaken"] = img

    # 反弹：身前竖盾 + 向外弹出的波，和绝对防御的板甲盾、反击的回勾都分开。
    img = family_tile("technique", (12, 28, 48))
    mirror = (210, 235, 255, 255)
    rim = (140, 210, 255, 255)
    wave_col = (180, 240, 255, 255)
    diamond(img, 12, 16, 6, 9, rim)
    diamond(img, 12, 16, 4, 6, mirror)
    fill(img, 10, 12, 2, 8, (255, 255, 255, 255))
    line(img, 18, 10, 26, 16, wave_col, 2)
    line(img, 18, 22, 26, 16, wave_col, 2)
    line(img, 20, 8, 27, 16, (230, 250, 255, 255), 1)
    line(img, 20, 24, 27, 16, (230, 250, 255, 255), 1)
    icons["skill_reflect"] = img

    os.makedirs(OUT, exist_ok=True)
    for name, image in icons.items():
        path = os.path.join(OUT, f"{name}.png")
        write_png(path, image)
        print("wrote", path)

    os.makedirs(FX_OUT, exist_ok=True)
    skull_path = os.path.join(FX_OUT, "skull_x.png")
    write_png(skull_path, bake_skull())
    print("wrote", skull_path)
    print("count", len(icons))


if __name__ == "__main__":
    bake()
