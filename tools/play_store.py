"""Google Play store graphics -> renders/play/.

python tools/play_store.py
  icon_512.png        app icon 512x512 (from concept/ui/app_icon.png)
  feature_1024x500.png feature graphic (title screen art, blurred, + icon + title)
  shot_N.png          1920x1080 screenshots: frames from the trailer's raw clips (renders/trailer/raw/*.avi)
"""
import os
import subprocess
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "renders", "play")
RAW = os.path.join(ROOT, "renders", "trailer", "raw")
FONT = "C:/Windows/Fonts/seguibl.ttf"
# clip, fraction of its length
SHOTS = [("s02_side", 1 / 3), ("s03_phone", 1 / 3), ("s13_sunset", 1 / 3), ("s06_snow", 2 / 3),
         ("s10_garage", 2 / 3), ("s15_market", 2 / 3), ("s12_fall", 1 / 3), ("s14_dream", 2 / 3)]


def rounded(img, r):
    m = Image.new("L", img.size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, img.size[0] - 1, img.size[1] - 1), r, fill=255)
    img = img.convert("RGBA")
    img.putalpha(m)
    return img


def text(d, xy, s, size, fill, stroke=6):
    f = ImageFont.truetype(FONT, size)
    d.text(xy, s, font=f, fill=fill, stroke_width=stroke, stroke_fill=(40, 30, 40))


def icon():
    src = Image.open(os.path.join(ROOT, "concept", "ui", "app_icon.png")).convert("RGB")
    src.resize((512, 512), Image.LANCZOS).save(os.path.join(OUT, "icon_512.png"))


def feature():
    bg = Image.open(os.path.join(ROOT, "concept", "ui", "title_screen.png")).convert("RGB")
    w, h = 1024, 500
    s = max(w / bg.width, h / bg.height)
    bg = bg.resize((round(bg.width * s), round(bg.height * s)), Image.LANCZOS)
    bg = bg.crop(((bg.width - w) // 2, (bg.height - h) // 2, (bg.width - w) // 2 + w, (bg.height - h) // 2 + h))
    bg = bg.filter(ImageFilter.GaussianBlur(7))
    dark = Image.new("RGB", (w, h), (30, 20, 40))
    bg = Image.blend(bg, dark, 0.25).convert("RGBA")
    ic = rounded(Image.open(os.path.join(ROOT, "concept", "ui", "app_icon.png")).resize((300, 300), Image.LANCZOS), 60)
    sh = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((62, 112, 372, 422), 60, fill=(0, 0, 0, 140))
    bg = Image.alpha_composite(bg, sh.filter(ImageFilter.GaussianBlur(12)))
    bg.alpha_composite(ic, (56, 100))
    d = ImageDraw.Draw(bg)
    text(d, (400, 150), "Горячая сумка", 70, (255, 244, 200), 7)
    text(d, (404, 262), "Симулятор курьера", 44, (255, 255, 255), 5)
    text(d, (404, 330), "велосипед · заказы · свой ресторан", 28, (120, 230, 220), 4)
    bg.convert("RGB").save(os.path.join(OUT, "feature_1024x500.png"))


def shots():
    for i, (clip, k) in enumerate(SHOTS, 1):
        src = os.path.join(RAW, clip + ".avi")
        dur = float(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                                             "-of", "csv=p=0", src]).decode().strip())
        subprocess.check_call(["ffmpeg", "-v", "error", "-y", "-ss", "%.2f" % (dur * k), "-i", src,
                               "-frames:v", "1", os.path.join(OUT, "shot_%d.png" % i)])


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    icon()
    feature()
    shots()
    print("ok", sorted(os.listdir(OUT)))
