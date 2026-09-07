#!/usr/bin/env python3
"""Magenta chroma-key for the AI-generated sheets.

Every sheet so far has arrived claiming transparency with a fully opaque alpha
channel, so this is the standard first step. Three stages, each one added
because the previous attempt left a visible artefact:

1. Soft alpha ramp on distance from the key colour, so edges stay anti-aliased
   instead of turning into a jagged 1-bit cutout.
2. Colour decontamination -- un-blend the key out of the semi-transparent edge
   pixels, which otherwise keep a pink glow.
3. Spill suppression -- magenta baked into *opaque* pixels (the purple halo
   that survived the boss sheet's first two passes). Where red and blue both
   exceed green, pull them back down.
"""
import sys
import numpy as np
from PIL import Image

KEY = np.array([255.0, 0.0, 255.0])


def key_out(path, out_path, d0=90.0, d1=190.0):
    img = np.array(Image.open(path).convert("RGBA")).astype(np.float32)
    rgb = img[..., :3]

    dist = np.linalg.norm(rgb - KEY, axis=-1)
    alpha = np.clip((dist - d0) / (d1 - d0), 0.0, 1.0)

    # Un-blend the key colour out of partially transparent edge pixels.
    safe = np.maximum(alpha, 1e-3)[..., None]
    decon = (rgb - (1.0 - safe) * KEY) / safe

    # Spill suppression on what remains.
    r, g, b = decon[..., 0], decon[..., 1], decon[..., 2]
    excess = np.maximum(np.minimum(r, b) - g, 0.0)
    decon[..., 0] = r - excess
    decon[..., 2] = b - excess

    out = np.dstack([np.clip(decon, 0, 255), alpha * 255.0]).astype(np.uint8)
    Image.fromarray(out, "RGBA").save(out_path)

    kept = float((alpha > 0.5).mean())
    print(f"{out_path}: {img.shape[1]}x{img.shape[0]}, {kept * 100:.1f}% opaque")


if __name__ == "__main__":
    key_out(sys.argv[1], sys.argv[2])
