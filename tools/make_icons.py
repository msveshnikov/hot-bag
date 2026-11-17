"""Make every app icon from one painted square (concept/ui/app_icon.png, ChatGPT).
python tools/make_icons.py
Writes:
  icon.png                         project icon (512, rounded square) - window, web favicon, boot
  assets/icons/icon_192.png        Android legacy launcher icon (full square, OS masks it)
  assets/icons/adaptive_fg_432.png Android adaptive foreground: whole painting in the 72dp safe zone
  assets/icons/adaptive_bg_432.png Android adaptive background: blurred, enlarged painting
  assets/icons/pwa_*.png           web app icons
  assets/icons/icon.ico            Windows exe icon (16-256)
"""
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "concept", "ui", "app_icon.png")
OUT = os.path.join(ROOT, "assets", "icons")


def square(img):
    w, h = img.size
    s = min(w, h)
    return img.crop(((w - s) // 2, (h - s) // 2, (w - s) // 2 + s, (h - s) // 2 + s))


def rounded(img, size, radius=0.22):
    im = img.resize((size, size), Image.LANCZOS).convert("RGBA")
    k = 4
    mask = Image.new("L", (size * k, size * k), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size * k - 1, size * k - 1), int(size * k * radius), fill=255)
    im.putalpha(mask.resize((size, size), Image.LANCZOS))
    return im


def main():
    os.makedirs(OUT, exist_ok=True)
    art = square(Image.open(SRC).convert("RGB"))
    rounded(art, 512).save(os.path.join(ROOT, "icon.png"))
    art.resize((192, 192), Image.LANCZOS).save(os.path.join(OUT, "icon_192.png"))
    # Adaptive icon: 108dp layer, 72dp visible -> painting at 2/3 size in the middle of the foreground,
    # background = the same painting enlarged and blurred so the edges continue it seamlessly.
    fg = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
    fg.paste(art.resize((288, 288), Image.LANCZOS), (72, 72))
    fg.save(os.path.join(OUT, "adaptive_fg_432.png"))
    bg = art.resize((432, 432), Image.LANCZOS).filter(ImageFilter.GaussianBlur(18))
    bg.save(os.path.join(OUT, "adaptive_bg_432.png"))
    for s in (144, 180, 512):
        art.resize((s, s), Image.LANCZOS).save(os.path.join(OUT, "pwa_%d.png" % s))
    rounded(art, 256, 0.18).save(os.path.join(OUT, "icon.ico"),
                                 sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print("icons written to", OUT)


if __name__ == "__main__":
    main()
