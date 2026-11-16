"""Download ElevenLabs takes into assets/audio/voice/mikhalych/<key>.mp3.
python tools/voice_get.py <key> <url> [<key> <url> ...]
"""
import os
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "audio", "voice", "mikhalych")
os.makedirs(OUT, exist_ok=True)
a = sys.argv[1:]
for k, url in zip(a[0::2], a[1::2]):
    data = urllib.request.urlopen(url, timeout=60).read()
    open(os.path.join(OUT, k + ".mp3"), "wb").write(data)
    print(k, len(data))
