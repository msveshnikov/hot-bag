"""Slice concept/ui/icon_sheet.png (ChatGPT, 5x5 icons on flat light grey) into assets/ui/icons/<id>.png with
transparent background: flood fill of the grey from the cell border, soft edge, trimmed and padded to 192x192.
python tools/slice_icons.py
"""
import os
import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "concept", "ui", "icon_sheet.png")
OUT = os.path.join(ROOT, "assets", "ui", "icons")
IDS = [
    "battery", "motor", "tires", "brakes", "rack",
    "lock", "headlight", "mudguards", "raincoat", "waterproof_bag",
    "cooling_pack", "cup_holder", "soft_bag", "helmet_bike", "helmet_half",
    "helmet_retro", "warm_gloves", "bicycle", "scooter", "ebike",
    "moped", "ecar", "coins", "tools", "powerbank",
]


def main():
    os.makedirs(OUT, exist_ok=True)
    im = np.asarray(Image.open(SRC).convert("RGB")).astype(np.float32)
    H, W, _ = im.shape
    bg = np.median(np.concatenate([im[:6].reshape(-1, 3), im[-6:].reshape(-1, 3)]), axis=0)
    for k, name in enumerate(IDS):
        r, c = divmod(k, 5)
        y0, y1 = int(r * H / 5), int((r + 1) * H / 5)
        x0, x1 = int(c * W / 5), int((c + 1) * W / 5)
        cell = im[y0:y1, x0:x1]
        dist = np.sqrt(((cell - bg) ** 2).sum(axis=2))
        near = dist < 18.0
        lab, _ = ndimage.label(near)
        edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
        back = np.isin(lab, list(edge))
        alpha = (~back).astype(np.float32)
        # keep only the biggest object (drops bits of neighbouring icons)
        obj, n = ndimage.label(alpha > 0.5)
        if n > 1:
            sizes = ndimage.sum(alpha > 0.5, obj, range(1, n + 1))
            keep = [i + 1 for i, s in enumerate(sizes) if s > 0.04 * sizes.max()]
            alpha *= np.isin(obj, keep)
        a = Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))
        rgba = Image.fromarray(cell.astype(np.uint8)).convert("RGBA")
        rgba.putalpha(a)
        bbox = rgba.getbbox()
        rgba = rgba.crop(bbox)
        s = max(rgba.size)
        canvas = Image.new("RGBA", (s + 16, s + 16), (0, 0, 0, 0))
        canvas.paste(rgba, ((s + 16 - rgba.width) // 2, (s + 16 - rgba.height) // 2))
        canvas.resize((192, 192), Image.LANCZOS).save(os.path.join(OUT, name + ".png"))
    print("icons:", len(IDS))


if __name__ == "__main__":
    main()
