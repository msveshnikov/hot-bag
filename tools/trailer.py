"""Promo video: record every shot of scripts/trailer.gd with Godot's Movie Maker, then edit the video.
python tools/trailer.py record [shot ...]   # renders/trailer/raw/<shot>.avi (+ .start = first frame of the shot)
python tools/trailer.py sheet [shot ...]    # contact sheets renders/trailer/chk_<shot>.png
python tools/trailer.py edit                # renders/trailer/hot_bag_trailer.mp4
Voice-over: renders/trailer/vo_full.mp3 (ElevenLabs), end card: renders/trailer/endcard.png, music: music_menu.mp3.
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = r"C:\Users\msves\OneDrive\Рабочий стол\Godot_v4.7.2-stable_win64.exe"
RAW = os.path.join(ROOT, "renders", "trailer", "raw")
OUT = os.path.join(ROOT, "renders", "trailer")
MUSIC = os.path.join(ROOT, "assets", "audio", "music", "music_menu.mp3")
FONT = "C:/Windows/Fonts/seguibl.ttf"

# (shot, seconds after the shot starts, length, game-audio volume)
CUTS = [
    ("s01_open", 1.5, 4.6, 0.30), ("s02_side", 0.6, 1.8, 0.35), ("s14_dream", 1.6, 2.6, 0.25),
    ("s03_phone", 0.6, 3.6, 0.30), ("s04_rest", 1.0, 2.6, 0.35),
    ("s05_rain", 0.8, 1.7, 0.45), ("s06_snow", 1.0, 1.5, 0.35), ("s07_night", 0.4, 2.0, 0.35),
    ("s08_stairs", 0.5, 3.4, 0.40),
    ("s04_rest", 3.6, 1.3, 0.30), ("s09_city", 1.0, 1.9, 0.35), ("s07_night", 3.4, 1.4, 0.30),
    ("s15_market", 1.0, 1.4, 0.35), ("s16_park", 2.2, 1.9, 0.35),
    ("s10_garage", 0.2, 4.6, 0.25), ("s02_side", 2.6, 2.4, 0.35), ("s12_fall", 1.0, 2.6, 0.80),
    ("s13_sunset", 1.0, 4.4, 0.35),
]
END_LEN = 7.0
# (text, start, end, style): big = centre, small = pill at the bottom, district = coral pill at the top
CAPTIONS = [
    ("Мечта: свой ресторан", 6.6, 9.0, "small"),
    ("Приложение «Хоп!»", 9.2, 12.6, "small"),
    ("ДОЖДЬ", 15.3, 16.9, "big"), ("СНЕГ", 16.9, 18.4, "big"), ("НОЧНЫЕ СМЕНЫ", 18.5, 20.4, "big"),
    ("Старый город", 23.8, 25.1, "district"), ("«Сити»", 25.1, 27.0, "district"), ("«Берёзки»", 27.0, 28.4, "district"),
    ("Гастроквартал", 28.4, 29.8, "district"), ("Большой парк", 29.8, 31.7, "district"),
    ("5 видов транспорта", 32.0, 36.2, "small"),
    ("Михалыч: «Голубей не дави — у них профсоюз»", 36.4, 40.4, "small"),
    ("Падать — смешно. Почти.", 38.9, 41.3, "district"),
    ("ГОРЯЧИМ", 41.8, 43.0, "big"), ("ЦЕЛЫМ", 43.0, 44.2, "big"), ("ВОВРЕМЯ!", 44.2, 45.7, "big"),
]
# voice-over pieces: (start in vo_full.mp3, end, position in the video)
VO = [(0.0, 3.5, 0.5), (4.5, 7.7, 5.0), (8.4, 14.2, 9.3), (15.0, 15.8, 15.4), (16.05, 16.65, 17.1), (17.1, 18.25, 18.6),
      (18.85, 21.9, 20.6), (22.55, 28.65, 24.0), (29.25, 33.4, 31.9), (33.95, 37.85, 41.6), (38.45, 44.12, 46.2)]
MENTOR_LINE = (os.path.join(ROOT, "assets", "audio", "voice", "mikhalych", "351bd6dfbd10.mp3"), 36.4)

def shots():
    src = open(os.path.join(ROOT, "scripts", "trailer.gd"), encoding="utf-8").read()
    return re.findall(r'^\t"(s\d\d_\w+)": \{"d": "(\w+)"', src, re.M)


def record(only):
    os.makedirs(RAW, exist_ok=True)
    ov = os.path.join(ROOT, "override.cfg")
    open(ov, "w").write("[display]\n\nwindow/size/window_width_override=1920\nwindow/size/window_height_override=1080\n")
    try:
        for sid, dist in shots():
            if only and sid not in only:
                continue
            print("record", sid, dist, flush=True)
            subprocess.run([GODOT, "--path", ROOT, "--write-movie", os.path.join(RAW, sid + ".avi"), "--fixed-fps", "30",
                            "--", "--trailer", sid, "--district", dist, "--quality", "2"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=900)
    finally:
        os.remove(ov)


def start_of(sid):
    p = os.path.join(RAW, sid + ".start")
    return int(open(p).read().strip()) if os.path.exists(p) else 0


def sheet(only):
    for sid, _ in shots():
        if only and sid not in only:
            continue
        s = start_of(sid)
        sel = "+".join("eq(n\\,%d)" % f for f in [s + 5, s + 45, s + 90, s + 135])
        subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", os.path.join(RAW, sid + ".avi"), "-vf",
                        "select='%s',scale=640:-1,tile=2x2" % sel, "-frames:v", "1", "-update", "1",
                        os.path.join(OUT, "chk_%s.png" % sid)])
        print("sheet", sid, "start", s)


def _caption_png(text, style, path):
    from PIL import Image, ImageDraw, ImageFont
    size = {"big": 128, "small": 62, "district": 74}[style]
    f = ImageFont.truetype(FONT, size)
    sw = 11 if style == "big" else 6
    box = ImageDraw.Draw(Image.new("RGBA", (10, 10))).textbbox((0, 0), text, font=f, stroke_width=sw)
    tw, th = box[2] - box[0], box[3] - box[1]
    padx, pady = (0, 0) if style == "big" else (36, 18)
    w, h = tw + padx * 2, th + pady * 2
    im = Image.new("RGBA", (w + 16, h + 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if style != "big":
        col = (34, 184, 176, 240) if style == "small" else (239, 106, 91, 245)
        d.rounded_rectangle((8, 10, w + 8, h + 10), radius=h // 2, fill=(47, 42, 51, 190))
        d.rounded_rectangle((0, 0, w, h), radius=h // 2, fill=col)
    fill = (255, 243, 196) if style == "big" else (255, 255, 255)
    d.text((padx - box[0], pady - box[1]), text, font=f, fill=fill, stroke_width=sw, stroke_fill=(47, 42, 51))
    im.save(path)


def run(args):
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y"] + args, check=True)


def edit():
    tmp = os.path.join(OUT, "tmp")
    os.makedirs(tmp, exist_ok=True)
    # 1) cut the shots: hard cuts, 1080p30, game audio at its own volume
    parts = []
    for i, (sid, off, ln, vol) in enumerate(CUTS):
        p = os.path.join(tmp, "c%02d.mp4" % i)
        run(["-ss", "%.3f" % (start_of(sid) / 30.0 + off), "-t", "%.3f" % ln, "-i", os.path.join(RAW, sid + ".avi"),
             "-vf", "scale=1920:1080,fps=30,format=yuv420p",
             "-af", "volume=%.2f,aresample=48000,aformat=channel_layouts=stereo" % vol,
             "-c:v", "libx264", "-crf", "16", "-preset", "fast", "-c:a", "aac", "-b:a", "192k", p])
        parts.append(p)
    end = os.path.join(tmp, "end.mp4")
    run(["-loop", "1", "-framerate", "30", "-t", "%.2f" % END_LEN, "-i", os.path.join(OUT, "endcard.png"),
         "-f", "lavfi", "-t", "%.2f" % END_LEN, "-i", "anullsrc=r=48000:cl=stereo",
         "-vf", "scale=2112:1188,crop=1920:1080:'(in_w-1920)/2+40*sin(t/3)':'(in_h-1080)/2',fade=t=in:d=0.5,format=yuv420p",
         "-c:v", "libx264", "-crf", "16", "-preset", "fast", "-c:a", "aac", "-b:a", "192k", "-shortest", end])
    parts.append(end)
    lst = os.path.join(tmp, "list.txt")
    open(lst, "w").write("".join("file '%s'\n" % p.replace("\\", "/") for p in parts))
    cut = os.path.join(tmp, "cut.mp4")
    run(["-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", cut])
    total = float(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0",
                                           cut]).decode().strip())
    # 2) captions, voice-over, music ducked under the voice
    inputs = ["-i", cut, "-i", os.path.join(OUT, "vo_full.mp3"), "-i", MUSIC, "-i", MENTOR_LINE[0]]
    fc = []
    v = "0:v"
    for k, (text, t0, t1, style) in enumerate(CAPTIONS):
        png = os.path.join(tmp, "cap%02d.png" % k)
        _caption_png(text, style, png)
        inputs += ["-loop", "1", "-framerate", "30", "-t", "%.2f" % total, "-i", png]
        idx = 4 + k
        if style == "big":
            x, y = "(W-w)/2", "(H-h)/2-40"
            fc.append("[%d:v]format=rgba,fade=t=in:st=%.2f:d=0.12:alpha=1,fade=t=out:st=%.2f:d=0.15:alpha=1[cp%d]" % (
                idx, t0, t1 - 0.15, k))
        else:
            x = "if(lt(t,%.2f),-w+(t-%.2f)/0.25*(80+w),80)" % (t0 + 0.25, t0)
            y = "H-h-100" if style == "small" else "80"
            fc.append("[%d:v]format=rgba,fade=t=out:st=%.2f:d=0.2:alpha=1[cp%d]" % (idx, t1 - 0.2, k))
        fc.append("[%s][cp%d]overlay=x='%s':y='%s':enable='between(t,%.2f,%.2f)'[v%d]" % (v, k, x, y, t0, t1, k))
        v = "v%d" % k
    vo = []
    for j, (a, b, at) in enumerate(VO):
        fc.append("[1:a]atrim=%.2f:%.2f,asetpts=PTS-STARTPTS,aresample=48000,aformat=channel_layouts=stereo,volume=1.5,"
                  "adelay=%d|%d[vo%d]" % (a, b, int(at * 1000), int(at * 1000), j))
        vo.append("[vo%d]" % j)
    fc.append("[3:a]aresample=48000,aformat=channel_layouts=stereo,volume=1.4,adelay=%d|%d[ment]" % (
        int(MENTOR_LINE[1] * 1000), int(MENTOR_LINE[1] * 1000)))
    vo.append("[ment]")
    fc.append("%samix=inputs=%d:normalize=0:duration=longest,apad,atrim=0:%.2f,asplit=2[vox][voside]" % (
        "".join(vo), len(vo), total))
    fc.append("[2:a]atrim=0:%.2f,asetpts=PTS-STARTPTS,aresample=48000,aformat=channel_layouts=stereo,volume=0.6,"
              "afade=t=out:st=%.2f:d=2.5[mus]" % (total, total - 2.6))
    fc.append("[mus][voside]sidechaincompress=threshold=0.03:ratio=8:attack=15:release=350[musd]")
    fc.append("[0:a][musd][vox]amix=inputs=3:normalize=0:duration=first,alimiter=limit=0.95[aout]")
    out = os.path.join(OUT, "hot_bag_trailer.mp4")
    script = os.path.join(tmp, "filter.txt")
    open(script, "w", encoding="utf-8").write(";\n".join(fc))
    run(inputs + ["-filter_complex_script", script, "-map", "[%s]" % v, "-map", "[aout]", "-t", "%.2f" % total,
                  "-c:v", "libx264", "-crf", "18", "-preset", "medium", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k",
                  "-movflags", "+faststart", out])
    print("trailer", out, "%.1f s" % total)


if __name__ == "__main__":
    cmd, rest = sys.argv[1], sys.argv[2:]
    if cmd == "record":
        record(rest)
    elif cmd == "sheet":
        sheet(rest)
    elif cmd == "edit":
        edit()
