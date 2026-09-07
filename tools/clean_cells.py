#!/usr/bin/env python3
"""Drop fragments that bled in from a neighbouring cell.

The generators draw muzzle flashes that run past the frame they belong to, so
after slicing, a cell can carry a stray sliver of the previous cell's flash
floating in empty space. Keeping only the connected components that reach the
middle of the cell removes those without touching the real sprite.
"""
import sys
import numpy as np
from PIL import Image
from scipy import ndimage


def clean(path, out_path, cols, rows, min_frac=0.004):
    img = np.array(Image.open(path).convert("RGBA"))
    H, W = img.shape[:2]
    cw, ch = W // cols, H // rows
    removed = 0
    for r in range(rows):
        for c in range(cols):
            y0, x0 = r * ch, c * cw
            cell = img[y0:y0 + ch, x0:x0 + cw]
            mask = cell[..., 3] > 40
            if not mask.any():
                continue
            lab, n = ndimage.label(mask)
            if n <= 1:
                continue
            sizes = ndimage.sum(mask, lab, range(1, n + 1))
            keep = np.zeros(n + 1, dtype=bool)
            for i in range(1, n + 1):
                ys, xs = np.where(lab == i)
                # Keep anything substantial, or anything that reaches the
                # middle third of the cell -- that's the sprite itself.
                bled_in = xs.max() < cw * 0.18   # sits entirely in the left margin
                touches_core = (xs.min() < cw * 0.66) and (xs.max() > cw * 0.33)
                keep[i] = touches_core and not bled_in and sizes[i - 1] >= mask.size * min_frac
            drop = ~keep[lab]
            drop[lab == 0] = False
            if drop.any():
                removed += int(drop.sum())
                cell[..., 3][drop] = 0
    Image.fromarray(img).save(out_path)
    print(f"{out_path}: cleared {removed} stray px")


if __name__ == "__main__":
    clean(sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]))
