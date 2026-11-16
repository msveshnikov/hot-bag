"""Contact sheet of images (system Python).
usage: python tools/sheet.py out.jpg cell_px cols img1 img2 ... (globs allowed)"""
import sys, glob
from PIL import Image, ImageDraw

out, cell, cols = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
files = []
for a in sys.argv[4:]:
    files += sorted(glob.glob(a)) if any(c in a for c in "*?") else [a]
rows = (len(files) + cols - 1) // cols
sheet = Image.new("RGB", (cols * cell, rows * (cell + 16)), "white")
d = ImageDraw.Draw(sheet)
for i, f in enumerate(files):
    im = Image.open(f).convert("RGB")
    im.thumbnail((cell, cell))
    x, y = (i % cols) * cell, (i // cols) * (cell + 16)
    sheet.paste(im, (x, y))
    d.text((x + 2, y + cell + 2), f.replace("\\", "/").split("/")[-1][:28], fill="black")
sheet.save(out, quality=85)
print(out, len(files))
