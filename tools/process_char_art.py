#!/usr/bin/env python3
"""Process raw generated character sprites into game assets.

Removes the white background via border flood-fill (black outlines keep it
from leaking inside), trims, resizes to 256px height, and writes the final
PNGs into assets/char/.

Usage: python3 tools/process_char_art.py
"""
import os
from collections import deque
from PIL import Image

RAW = "art_raw"
OUT = "assets/char"
SETS = ["trooper", "medic", "hazmat", "ghillie", "raider", "astro",
        "zombie", "captain", "alien", "mecha"]
TOL = 60  # near-white tolerance for background removal


def cutout(path: str) -> Image.Image:
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    px = im.load()
    visited = bytearray(w * h)
    q = deque()

    def near_white(p):
        return p[0] > 255 - TOL and p[1] > 255 - TOL and p[2] > 255 - TOL and p[3] > 200

    for x in range(w):
        q.append((x, 0)); q.append((x, h - 1))
    for y in range(h):
        q.append((0, y)); q.append((w - 1, y))
    while q:
        x, y = q.popleft()
        if x < 0 or y < 0 or x >= w or y >= h:
            continue
        i = y * w + x
        if visited[i]:
            continue
        if not near_white(px[x, y]):
            continue
        visited[i] = 1
        q.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
    out = Image.new("RGBA", (w, h))
    op = out.load()
    for y in range(h):
        for x in range(w):
            op[x, y] = (0, 0, 0, 0) if visited[y * w + x] else px[x, y]
    bbox = out.getbbox()
    if bbox is None:
        raise SystemExit(f"empty sprite: {path}")
    out = out.crop(bbox)
    r = 256.0 / out.size[1]
    return out.resize((max(1, round(out.size[0] * r)), 256), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name in SETS:
        for part in ("head", "body"):
            src = os.path.join(RAW, f"{part}_{name}.png")
            if not os.path.exists(src):
                raise SystemExit(f"missing raw sprite {src}")
            dst = os.path.join(OUT, f"{part}.png" if name == "trooper" else f"{part}_{name}.png")
            img = cutout(src)
            img.save(dst)
            print(f"{src} -> {dst} {img.size}")


if __name__ == "__main__":
    main()
