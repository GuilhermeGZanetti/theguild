"""Films trailer shots with Godot's Movie Maker.

    python tools/trailer/render.py <shot> [<shot> ...]

Each shot runs the game with --trailer=<shot> (scripts/trailer/trailer.gd) and
writes tools/_cache/trailer/shots/<shot>/: numbered PNG frames, the game's
audio (f.wav) and marks.json, the frame number of every TRAILER_MARK.

Movie Maker films at the project's window size override, so a temporary
override.cfg asks for 1920x1080 and parks the window off screen while it runs.
"""
import json
import os
import shutil
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import ROOT, SHOTS, GODOT, FPS, W, H  # noqa: E402

OVERRIDE = os.path.join(ROOT, "override.cfg")
OVERRIDE_TEXT = """[display]

window/size/window_width_override=%d
window/size/window_height_override=%d
window/size/initial_position_type=0
window/size/initial_position=Vector2i(%d, 0)
""" % (W, H, 2400)


def render(shot, timeout=900):
    out = os.path.join(SHOTS, shot)
    if os.path.isdir(out):
        shutil.rmtree(out)
    os.makedirs(out)
    if os.path.exists(OVERRIDE):
        raise SystemExit("override.cfg already exists; remove it first (it is not ours)")
    with open(OVERRIDE, "w") as f:
        f.write(OVERRIDE_TEXT)
    t0 = time.time()
    try:
        cmd = [GODOT, "--path", ROOT, "--write-movie", os.path.join(out, "f.png"), "--fixed-fps", str(FPS),
               "--", "--trailer=" + shot]
        p = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout)
    finally:
        os.remove(OVERRIDE)
    log = p.stdout + "\n" + p.stderr
    with open(os.path.join(out, "log.txt"), "w", encoding="utf-8") as f:
        f.write(log)
    marks = {}
    for line in log.splitlines():
        if line.startswith("TRAILER_MARK "):
            _, name, frame = line.split()
            marks[name] = int(frame)
    with open(os.path.join(out, "marks.json"), "w") as f:
        json.dump(marks, f, indent=1)
    n = len([x for x in os.listdir(out) if x.endswith(".png")])
    errors = [ln for ln in log.splitlines() if ("SCRIPT ERROR" in ln or "ERROR:" in ln or "WARNING: TRAILER" in ln
                                                 or "at: " in ln) and "resources still in use" not in ln
              and "ObjectDB" not in ln and "cleanup" not in ln and "clear (core" not in ln]
    print("%s: %d frames (%.1fs of footage) in %.0fs, marks %s" % (shot, n, n / FPS, time.time() - t0, marks))
    for e in errors[:20]:
        print("   ", e)
    return marks


if __name__ == "__main__":
    for s in sys.argv[1:]:
        render(s)
