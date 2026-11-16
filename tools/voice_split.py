"""Split one ElevenLabs take of several lines (separated by [long pause]) into one mp3 per line.
python tools/voice_split.py <take.mp3|url> <key1> <key2> ...
Cuts at the N-1 longest silences (ffmpeg silencedetect), keeps 0.12 s of air around each line.
"""
import os
import re
import subprocess
import sys
import tempfile
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "audio", "voice", "mikhalych")


def main():
    src, keys = sys.argv[1], sys.argv[2:]
    if src.startswith("http"):
        tmp = os.path.join(tempfile.gettempdir(), "voice_take.mp3")
        open(tmp, "wb").write(urllib.request.urlopen(src, timeout=60).read())
        src = tmp
    dur = float(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of",
                                         "csv=p=0", src]).decode().strip())
    log = subprocess.run(["ffmpeg", "-hide_banner", "-i", src, "-af", "silencedetect=noise=-38dB:d=0.45", "-f", "null",
                          "-"], capture_output=True, text=True).stderr
    starts = [float(x) for x in re.findall(r"silence_start: ([0-9.]+)", log)]
    ends = [float(x) for x in re.findall(r"silence_end: ([0-9.]+)", log)]
    sil = [(s, e) for s, e in zip(starts, ends) if s > 0.3 and e < dur - 0.3]
    need = len(keys) - 1
    if len(sil) < need:
        print("only %d silences for %d lines: %s" % (len(sil), len(keys), sil))
        sys.exit(1)
    cuts = sorted(sorted(sil, key=lambda p: p[1] - p[0], reverse=True)[:need])
    bounds = [0.0] + [((s + 0.12), (e - 0.12)) for s, e in cuts] + [dur]
    os.makedirs(OUT, exist_ok=True)
    a = 0.0
    for i, k in enumerate(keys):
        b = cuts[i][0] + 0.15 if i < need else dur
        out = os.path.join(OUT, k + ".mp3")
        subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", src, "-ss", "%.3f" % a, "-to",
                        "%.3f" % b, "-c:a", "libmp3lame", "-q:a", "3", out], check=True)
        print(k, "%.2f-%.2f" % (a, b))
        if i < need:
            a = max(cuts[i][1] - 0.15, 0.0)


if __name__ == "__main__":
    main()
