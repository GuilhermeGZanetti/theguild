"""Contact sheet of a filmed shot, to review it without playing it.

    python tools/trailer/sheet.py <shot> [--every 0.5] [--from in] [--to out] [--cols 4]

Writes tools/_cache/trailer/shots/<shot>/sheet.png: frames from one mark to
another, labelled with their frame number and time since the first mark.
"""
import argparse
import json
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import SHOTS, FPS  # noqa: E402


def sheet(shot, every=0.5, start="in", end="out", cols=4, width=480, frames=None):
    d = os.path.join(SHOTS, shot)
    marks = json.load(open(os.path.join(d, "marks.json")))
    n = len([x for x in os.listdir(d) if x.endswith(".png") and x.startswith("f")])
    a = marks.get(start, 0) if isinstance(start, str) else int(start)
    b = marks.get(end, n - 1) if isinstance(end, str) else int(end)
    b = min(b, n - 1)
    if frames is None:
        step = max(1, int(round(every * FPS)))
        frames = list(range(a, b + 1, step))
    h = width * 9 // 16
    rows = (len(frames) + cols - 1) // cols
    out = Image.new("RGB", (cols * width, rows * (h + 14)), (20, 18, 24))
    dr = ImageDraw.Draw(out)
    for i, f in enumerate(frames):
        im = Image.open(os.path.join(d, "f%08d.png" % f)).convert("RGB").resize((width, h), Image.BILINEAR)
        x, y = (i % cols) * width, (i // cols) * (h + 14)
        out.paste(im, (x, y + 14))
        dr.text((x + 3, y + 1), "f%d  t=%.2f" % (f, (f - a) / FPS), fill=(230, 220, 160))
    path = os.path.join(d, "sheet.png")
    out.save(path)
    print(path, len(frames), "frames")
    return path


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("shot")
    ap.add_argument("--every", type=float, default=0.5)
    ap.add_argument("--start", default="in")
    ap.add_argument("--end", default="out")
    ap.add_argument("--cols", type=int, default=4)
    ap.add_argument("--width", type=int, default=480)
    a = ap.parse_args()
    s = a.start if not a.start.isdigit() else int(a.start)
    e = a.end if not a.end.isdigit() else int(a.end)
    sheet(a.shot, a.every, s, e, a.cols, a.width)
