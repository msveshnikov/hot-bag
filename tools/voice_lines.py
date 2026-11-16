"""Collect Михалыч's lines from scripts/story.gd for voice-over and write tools/voice_mikhalych.json:
[{key, file, text}] — file = assets/audio/voice/mikhalych/<key>.mp3, key = Sfx.voice_key(text) (letters only,
lower case, md5[:12]). Format specifiers are filled with the game's constants so the spoken numbers match the screen.

python tools/voice_lines.py            # list lines + total characters
python tools/voice_lines.py --missing  # only lines without an mp3 yet
The mp3s are made with ElevenLabs (MCP text-to-speech or the API, see README «Озвучка»).
"""
import hashlib
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STORY = os.path.join(ROOT, "scripts", "story.gd")
OUT_DIR = os.path.join(ROOT, "assets", "audio", "voice", "mikhalych")
CONST = {"Game.DREAM_PRICE": "1000", "Game.DREAM_RATING": "4,5", "CITY_GOAL": "5", "NIGHT_GOAL": "4"}
LIT = r'"((?:[^"\\]|\\.)*)"'


def key(text):
    letters = "".join(ch for ch in text.lower() if ("a" <= ch <= "z") or ("а" <= ch <= "я") or ch == "ё")
    return hashlib.md5(letters.encode("utf-8")).hexdigest()[:12]


def fill(lit, tail):
    """Fill %d/%s/%.1f using the expression after the literal (`% X` or `% [X, Y]`)."""
    m = re.match(r'\s*%\s*(\[[^\]]*\]|[A-Za-z_.]+(?:\([^)]*\))?)', tail)
    args = []
    if m:
        a = m.group(1).strip("[]")
        args = [x.strip() for x in a.split(",")]
    out, i = [], 0

    def sub(mm):
        nonlocal i
        name = args[i] if i < len(args) else ""
        i += 1
        if name in CONST:
            return CONST[name]
        if "gender" in name or "сынок" in tail[:200]:
            return "сынок"
        return mm.group(0)
    return re.sub(r'%[-+0-9.]*[dsf]', sub, lit)


def collect():
    src = open(STORY, encoding="utf-8").read()
    lines = []
    for rx in (r'dialog\(MENTOR[^,]*,\s*' + LIT, r'mentor_call\(\s*' + LIT):
        for m in re.finditer(rx, src):
            lines.append(fill(m.group(1), src[m.end():m.end() + 200]))
    # tips and t = "..." inside talk_mentor
    body = src[src.index("func talk_mentor"):src.index("func _mentor_1")]
    for blk in re.finditer(r'tips (?:\+)?= \[(.*?)\]\n', body, re.S):
        for m in re.finditer(LIT, blk.group(1)):
            lines.append(fill(m.group(1), blk.group(1)[m.end():m.end() + 200]))
    ban = src[src.index("const BANTER = ["):src.index("var world: Node")]
    for m in re.finditer(LIT, ban):
        lines.append(m.group(1))
    for m in re.finditer(r'\bt = ' + LIT, body):
        lines.append(fill(m.group(1), body[m.end():m.end() + 200]))
    out, seen = [], set()
    for t in lines:
        t = t.replace('\\"', '"')
        if "%" in t or len(t) < 12:
            continue
        variants = [t] if "сынок" not in t else [t, t.replace("сынок", "дочка")]
        for v in variants:
            k = key(v)
            if k in seen:
                continue
            seen.add(k)
            out.append(dict(key=k, file="assets/audio/voice/mikhalych/%s.mp3" % k, text=v))
    return out


def main():
    lines = collect()
    if "--missing" in sys.argv:
        lines = [l for l in lines if not os.path.exists(os.path.join(ROOT, l["file"]))]
    json.dump(lines, open(os.path.join(ROOT, "tools", "voice_mikhalych.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    total = sum(len(l["text"]) for l in lines)
    print("lines: %d, characters: %d (~%.1f min of speech)" % (len(lines), total, total / 14.0 / 60.0))


if __name__ == "__main__":
    main()
