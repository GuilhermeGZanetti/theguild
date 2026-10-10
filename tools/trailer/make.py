"""Makes the whole trailer: films every shot the edit uses, writes the score
and cuts them together into build/trailer/AGuilda_Trailer.mp4.

    python tools/trailer/make.py            film what is missing, then score and edit
    python tools/trailer/make.py --refilm   film every shot again

Filming is slow (the autoplayed battles run at a few frames a second), so shots
already in tools/_cache/trailer/shots/ are kept unless --refilm is given.
Needs Pillow, numpy and imageio-ffmpeg (or ffmpeg on PATH).
"""
import argparse
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import SHOTS  # noqa: E402

SHOTS_USED = [
    "bell", "creep", "grey", "tavern_empty", "tavern_full", "peoples", "board",
    "faction_saltborn", "faction_lantern", "faction_rootwardens", "faction_glass",
    "meteor", "turn", "blitz", "tsunami", "shards", "fall", "unnamed", "title_bg",
    "play_stilts_night_clear_7_55", "play_coast_day_survive_5_45",
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--refilm", action="store_true")
    a = ap.parse_args()
    py = sys.executable
    todo = [s for s in SHOTS_USED if a.refilm or not os.path.exists(os.path.join(SHOTS, s, "marks.json"))]
    if todo:
        subprocess.run([py, os.path.join(HERE, "render.py")] + todo, check=True)
    subprocess.run([py, os.path.join(HERE, "music.py")], check=True)
    subprocess.run([py, os.path.join(HERE, "edit.py")], check=True)


if __name__ == "__main__":
    main()
