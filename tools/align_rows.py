#!/usr/bin/env python3
"""Put every row of a sheet on one ground line.

Rows generated separately drift: on the turret sheet the idle rows sit with
their feet at y=184 while the firing and death rows sit at 159-164. Left
alone, the sprite visibly jumps ~25px up the instant it opens fire and drops
back when it stops. Shifting each row so its lowest opaque pixel matches the
lowest row means the code can treat the sheet as one aligned animation.
"""
import sys
import numpy as np
from PIL import Image


def align(path, out_path, cols, rows):
    img = np.array(Image.open(path).convert("RGBA"))
    H, W = img.shape[:2]
    cw, ch = W // cols, H // rows

    bottoms = []
    for r in range(rows):
        band = img[r * ch:(r + 1) * ch, :, 3] > 40
        ys, _ = np.where(band)
        bottoms.append(int(ys.max()) if len(ys) else 0)
    target = max(bottoms)
    print("row bottoms:", bottoms, "-> aligning all to", target)

    for r in range(rows):
        shift = target - bottoms[r]
        if shift == 0:
            continue
        band = img[r * ch:(r + 1) * ch].copy()
        moved = np.zeros_like(band)
        if shift > 0:
            moved[shift:] = band[:ch - shift]
        else:
            moved[:ch + shift] = band[-shift:]
        img[r * ch:(r + 1) * ch] = moved
        print(f"  row {r}: shifted {shift:+d}px")

    Image.fromarray(img).save(out_path)


if __name__ == "__main__":
    align(sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]))
