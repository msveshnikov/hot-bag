"""Move the newest ChatGPT download (<uuid>.tmp PNG) from ~/Downloads to a target path.
usage: python tools/grab_download.py concept/locations/old_town_night.png"""
import sys, os, glob, time, shutil
dst = sys.argv[1]
dl = os.path.join(os.path.expanduser("~"), "Downloads")
for _ in range(20):
    files = sorted(glob.glob(os.path.join(dl, "*.tmp")) + glob.glob(os.path.join(dl, "*.png")), key=os.path.getmtime)
    if files and time.time() - os.path.getmtime(files[-1]) < 120:
        src = files[-1]
        with open(src, "rb") as f:
            sig = f.read(4)
        if sig == b"\x89PNG":
            os.makedirs(os.path.dirname(dst) or ".", exist_ok=True)
            shutil.move(src, dst)
            from PIL import Image
            print("OK", dst, Image.open(dst).size)
            sys.exit(0)
    time.sleep(1)
print("NOT FOUND"); sys.exit(1)
