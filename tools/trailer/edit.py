"""The trailer's edit: cuts the filmed shots (render.py) to the score
(music.py), puts the story lines and titles on black cards between them, mixes
the shots' own sound under the score and encodes build/trailer/AGuilda_Trailer.mp4.

    python tools/trailer/edit.py                   the whole trailer
    python tools/trailer/edit.py --from 40 --to 65 a part of it (preview_*.mp4)
    python tools/trailer/edit.py --stills 9.6,43.3 single frames as PNGs
    python tools/trailer/edit.py --sheet           contact sheet, one frame a second

Times are seconds on the score's clock (timeline.py: 100 BPM, 2.4 s bars).
"""
import argparse
import json
import math
import os
import subprocess
import sys
import wave

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import timeline as TL  # noqa: E402
from common import CACHE, FONTS, FPS, H, OUT, ROOT, SHOTS, W, ffmpeg  # noqa: E402
from timeline import bar  # noqa: E402

SR = 48000
TEXT = (238, 228, 206)
TEXT_DIM = (170, 156, 140)
GOLD = (246, 204, 96)
INK = (58, 40, 32)
SHADOW = (30, 16, 20)
BAR_H = 138          # 2.39:1 letterbox bars at 1080p


# ------------------------------------------------------------------ shots
_marks = {}
_counts = {}


def marks(shot):
    if shot not in _marks:
        _marks[shot] = json.load(open(os.path.join(SHOTS, shot, "marks.json")))
    return _marks[shot]


def count(shot):
    if shot not in _counts:
        d = os.path.join(SHOTS, shot)
        _counts[shot] = len([x for x in os.listdir(d) if x.startswith("f") and x.endswith(".png")])
    return _counts[shot]


def sync(frame, at, t0):
    """The source frame to start a clip on at t0 so that `frame` lands on `at`."""
    return int(round(frame - (at - t0) * FPS))


class Clip:
    """A stretch of a filmed shot on the timeline. It fades in over `fi`
    seconds (over what is under it: the clip before, or black) and out over
    `fo`; `src` is the shot's frame shown at t0."""

    def __init__(self, shot, t0, t1, src, fi=0.0, fo=0.0, gain=0.7, zoom=None, grey=None, dark=None):
        self.shot, self.t0, self.t1, self.src = shot, t0, t1, int(src)
        self.fi, self.fo, self.gain = fi, fo, gain
        self.zoom = zoom      # (cx, cy, k): crop around a point of the source, k x
        self.grey = grey      # (t_a, t_b, from, to): desaturate over time
        self.dark = dark      # (t_a, t_b, from, to): darken over time
        last = self.src + int(round((t1 - t0) * FPS))
        if self.src < 0 or last >= count(shot):
            print("WARNING clip %s %.2f-%.2f wants frames %d..%d of %d" % (shot, t0, t1, self.src, last, count(shot)))

    def alpha(self, t):
        a = 1.0
        if self.fi > 0:
            a = min(a, (t - self.t0) / self.fi)
        if self.fo > 0:
            a = min(a, (self.t1 - t) / self.fo)
        return max(0.0, min(1.0, a))

    def frame(self, t):
        return min(count(self.shot) - 1, max(0, self.src + int(math.floor((t - self.t0) * FPS + 1e-6))))


def ramp(spec, t):
    if spec is None:
        return 0.0
    a, b, v0, v1 = spec
    k = min(1.0, max(0.0, (t - a) / (b - a)))
    k = k * k * (3 - 2 * k)
    return v0 + (v1 - v0) * k


# ------------------------------------------------------------------ text
class Text:
    def __init__(self, t0, t1, text, style="center", y=None, fi=0.5, fo=0.5, color=None):
        self.t0, self.t1, self.text, self.style = t0, t1, text, style
        self.y, self.fi, self.fo, self.color = y, fi, fo, color
        self._img = None

    def alpha(self, t):
        a = min((t - self.t0) / self.fi if self.fi > 0 else 1.0, (self.t1 - t) / self.fo if self.fo > 0 else 1.0)
        return max(0.0, min(1.0, a))

    def image(self):
        if self._img is None:
            self._img = render_text(self.text, self.style, self.color)
        return self._img

    def ypos(self):
        if self.y is not None:
            return self.y
        return {"tag": 760, "title": 560}.get(self.style, H // 2)


_fonts = {}


def font(name, size):
    key = (name, size)
    if key not in _fonts:
        _fonts[key] = ImageFont.truetype(os.path.join(FONTS, name), size)
    return _fonts[key]


def smooth_text(text, f, color, shadow_blur=6, shadow_alpha=230):
    """Anti-aliased text with a soft dark shadow, as an RGBA image."""
    box = f.getbbox(text)
    tw, th = box[2] - box[0], box[3] - box[1]
    pad = 30
    im = Image.new("RGBA", (tw + pad * 2, th + pad * 2), (0, 0, 0, 0))
    sh = Image.new("L", im.size, 0)
    ImageDraw.Draw(sh).text((pad - box[0], pad - box[1] + 3), text, font=f, fill=shadow_alpha)
    sh = sh.filter(ImageFilter.GaussianBlur(shadow_blur))
    dark = Image.new("RGBA", im.size, (8, 5, 10, 255))
    dark.putalpha(sh)
    im.alpha_composite(dark)
    ImageDraw.Draw(im).text((pad - box[0], pad - box[1]), text, font=f, fill=color + (255,))
    return im


def pixel_text(text, f, color, k=3, outline=INK, shadow=SHADOW):
    """Text in a pixel font drawn at the game's own size without smoothing,
    outlined and shadowed like the HUD's, then scaled k x with hard pixels."""
    box = f.getbbox(text)
    tw, th = box[2] - box[0], box[3] - box[1]
    pad = 4
    im = Image.new("RGBA", (tw + pad * 2, th + pad * 2), (0, 0, 0, 0))
    mask = Image.new("L", im.size, 0)
    md = ImageDraw.Draw(mask)
    md.fontmode = "1"
    md.text((pad - box[0], pad - box[1]), text, font=f, fill=255)
    m = np.array(mask) > 127
    ring = np.zeros_like(m)
    for dx, dy in [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, -1), (-1, 1), (1, 1)]:
        ring |= np.roll(np.roll(m, dy, 0), dx, 1)
    drop = np.roll(ring | m, 1, 0)
    a = np.zeros(m.shape + (4,), np.uint8)
    if shadow is not None:
        a[drop] = shadow + (200,)
    if outline is not None:
        a[ring] = outline + (255,)
    a[m] = color + (255,)
    im = Image.fromarray(a, "RGBA")
    return im.resize((im.width * k, im.height * k), Image.NEAREST)


def emblem_row(ids, k, gap=40):
    """The factions' emblems (assets/sprites/ui/emblem_<id>_64.png) side by side, k x."""
    ims = []
    for fid in ids:
        e = Image.open(os.path.join(ROOT, "assets", "sprites", "ui", "emblem_%s_64.png" % fid)).convert("RGBA")
        ims.append(e.resize((e.width * k, e.height * k), Image.NEAREST))
    out = Image.new("RGBA", (sum(i.width for i in ims) + gap * (len(ims) - 1), max(i.height for i in ims)), (0, 0, 0, 0))
    x = 0
    for i in ims:
        out.alpha_composite(i, (x, 0))
        x += i.width + gap
    return out


def render_text(text, style, color=None):
    if style == "emblems":       # text: faction ids, comma separated
        ids = text.split(",")
        return emblem_row(ids, 3 if len(ids) == 1 else 2)
    lines = text.split("\n")
    imgs = []
    for ln in lines:
        if style == "center":
            imgs.append(smooth_text(ln, font("AlegreyaSans-Italic.ttf", 50), TEXT))
        elif style == "gold":
            imgs.append(smooth_text(ln, font("AlegreyaSans-Italic.ttf", 58), GOLD))
        elif style == "slogan":
            imgs.append(pixel_text(ln, font("PixelifySans.ttf", 20), GOLD))
        elif style == "slogan_pale":
            imgs.append(pixel_text(ln, font("PixelifySans.ttf", 20), TEXT))
        elif style == "faction":
            imgs.append(pixel_text(ln, font("PixelifySans.ttf", 20), color))
        elif style == "tag":
            imgs.append(pixel_text(ln, font("PixelifySans.ttf", 12), TEXT_DIM))
        elif style == "title":
            imgs.append(pixel_text(ln, font("Jacquard12-Regular.ttf", 60), GOLD, outline=None))
        else:
            raise ValueError(style)
    gap = 6
    w = max(i.width for i in imgs)
    h = sum(i.height for i in imgs) + gap * (len(imgs) - 1)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    y = 0
    for i in imgs:
        out.alpha_composite(i, ((w - i.width) // 2, y))
        y += i.height + gap
    return out


# ------------------------------------------------------------------ the edit
FACTIONS = [  # data/factions.json: id, name, colour, and their answer to the Hush (shortened)
    ("saltborn", "THE SALTBORN COMPACT", (84, 188, 196), "“Flee by sea. The ocean remembers.”"),
    ("lantern", "THE LANTERN CONCLAVE", (240, 200, 96), "“Record everything. Nothing may be forgotten.”"),
    ("rootwardens", "THE ROOTWARDENS", (206, 120, 60), "“The Hush is a season. It will pass.”"),
    ("glass", "THE GLASS CARAVANS", (196, 120, 200), "“Sell what the Hush leaves behind.”"),
]


def card(x, t0, t1, *lines):
    """Words on black between two shots: (text, style[, colour]) per line,
    stacked around the middle of the screen."""
    n = len(lines)
    gap = 76 if all(ln[1] == "center" for ln in lines) else 92
    for i, ln in enumerate(lines):
        text, style = ln[0], ln[1]
        y = H // 2 + int((i - (n - 1) / 2) * gap)
        x.append(Text(t0, t1, text, style, y=y, fi=0.18, fo=0.15, color=ln[2] if len(ln) > 2 else None))


def edit():
    """The cut: shots, words on black between them, letterbox and flashes, all
    on the score's bars. The shots carry no words of ours."""
    c = []
    x = []
    # PROLOGUE (bars 0-10): the Bell, the crack, the grey -------------------
    card(x, 0.3, 3.4, ("For centuries, the Great Bell of Carrow", "center"), ("kept the Hush beyond the edges of the map.", "center"))
    c.append(Clip("bell", 3.6, 10.8, sync(marks("bell")["crack"], bar(TL.CRACK), 3.6), fi=0.8, fo=0.4, gain=0.6))
    card(x, 10.95, 12.9, ("Twenty years ago, the Bell cracked.", "center"))
    c.append(Clip("creep", 13.0, 17.6, 110, fi=0.5, fo=0.3, gain=0.6))
    card(x, 17.75, 20.15, ("Now the grey silence creeps back.", "center"), ("Villages vanish from maps, and from memory.", "center"))
    c.append(Clip("grey", 20.3, 24.0, sync(215, 24.0, 20.3), fi=0.5, fo=0.5, gain=0.6))
    # GUILD (bars 10-16): the tavern, the nations ---------------------------
    card(x, 24.15, 26.3, ("You inherit an abandoned tavern,", "center"), ("and a ledger of blank pages.", "center"))
    c.append(Clip("tavern_empty", 26.4, bar(TL.GUILD_FULL), 60, fi=0.4, gain=0.5))
    full = bar(TL.GUILD_FULL)
    card(x, full + 0.05, full + 1.15, ("RAISE A GUILD", "slogan"))
    c.append(Clip("tavern_full", full + 1.2, full + 4.8, 60, gain=0.5))
    card(x, full + 4.85, full + 5.95, ("RECRUIT FROM FIVE NATIONS", "slogan"))
    c.append(Clip("peoples", full + 6.0, bar(TL.FACTIONS), 40, gain=0.6))
    # FACTIONS (bars 16-22): four answers to the Hush ------------------------
    fa = bar(TL.FACTIONS)
    ids = [fc[0] for fc in FACTIONS]
    x.append(Text(fa + 0.05, fa + 1.75, ",".join(ids), "emblems", y=420, fi=0.18, fo=0.15))
    x.append(Text(fa + 0.05, fa + 1.75, "FOUR FACTIONS", "slogan", y=590, fi=0.18, fo=0.15))
    x.append(Text(fa + 0.05, fa + 1.75, "Four answers to the Hush.", "center", y=672, fi=0.18, fo=0.15))
    for i, (fid, name, colour, answer) in enumerate(FACTIONS):
        t = bar(TL.FACTIONS + 0.75 + 1.25 * i)
        x.append(Text(t + 0.05, t + 1.45, fid, "emblems", y=380, fi=0.18, fo=0.15))
        x.append(Text(t + 0.05, t + 1.45, name, "faction", y=575, fi=0.18, fo=0.15, color=colour))
        x.append(Text(t + 0.05, t + 1.45, answer, "center", y=660, fi=0.18, fo=0.15))
        c.append(Clip("faction_" + fid, t + 1.5, t + 3.0, 38, gain=0.6))
    bd = bar(TL.FACTIONS + 0.75 + 1.25 * len(FACTIONS))
    card(x, bd + 0.05, bd + 1.15, ("EVERY JOB YOU REFUSE HAS A PRICE", "slogan"))
    c.append(Clip("board", bd + 1.2, bar(TL.BREAK), 140, gain=0.6))
    br = bar(TL.BREAK)
    x.append(Text(br + 0.15, br + 2.25, "Written names resist the Hush.", "center", y=500, fi=0.3, fo=0.25))
    x.append(Text(br + 1.1, br + 2.25, "Write yours.", "gold", y=585, fi=0.25, fo=0.25))
    # BATTLE (bars 24-31): the drop, a cut on every beat or so ---------------
    b = bar(TL.BATTLE)
    beat = TL.BEAT
    death = bar(TL.DEATH)
    t = b
    c.append(Clip("meteor", t, t + 4 * beat, sync(64, t + 0.1, t), gain=0.45))
    t += 4 * beat
    c.append(Clip("play_stilts_night_clear_7_55", t, t + 3 * beat, sync(426, t + 1.2, t), gain=0.45))
    t += 3 * beat
    card(x, t + 0.05, t + 2 * beat - 0.05, ("TURN-BASED TACTICS", "slogan"))
    t += 2 * beat
    c.append(Clip("turn", t, t + 3 * beat, sync(marks("turn")["click"], t + 0.6, t), gain=0.45))
    t += 3 * beat
    c.append(Clip("blitz", t, t + 3 * beat, 56, gain=0.45))
    t += 3 * beat
    card(x, t + 0.05, t + 2 * beat - 0.05, ("8 CLASSES  -  16 PATHS", "slogan"))
    t += 2 * beat
    c.append(Clip("tsunami", t, t + 3 * beat, 56, gain=0.45))
    t += 3 * beat
    c.append(Clip("shards", t, t + 3 * beat, 54, gain=0.45))
    t += 3 * beat
    c.append(Clip("play_stilts_night_clear_7_55", t, t + 2 * beat, sync(991, t + 0.6, t), gain=0.45))
    t += 2 * beat
    fall = death - 26 / FPS   # the arrow is loosed; it lands as the music stops
    c.append(Clip("play_coast_day_survive_5_45", t, fall, sync(1088, t + 0.4, t), gain=0.45))
    # DEATH (bar 31) -----------------------------------------------------------
    c.append(Clip("fall", fall, death + 1.4, sync(63, death, fall), gain=0.8, fo=0.15, grey=(death + 0.2, death + 1.4, 0.0, 0.8)))
    fin = bar(TL.FINAL)
    card(x, death + 1.5, fin - 0.1, ("SAVE THEM, OR LOSE THEM FOREVER", "slogan_pale"))
    # FINAL (bars 32.5-38.5): the Unnamed, then everything -------------------
    c.append(Clip("unnamed", fin, fin + 4.8, marks("unnamed")["in"], gain=0.6))
    card(x, fin + 4.85, fin + 5.95, ("HOLD BACK THE HUSH", "slogan"))
    m = fin + 6.0
    hits = [("play_coast_day_survive_5_45", 829), ("meteor", 177), ("play_stilts_night_clear_7_55", 782)]
    for i, (shot, f) in enumerate(hits):
        t0 = m + i * 1.2
        c.append(Clip(shot, t0, t0 + 1.2, sync(f, t0 + 0.4, t0), gain=0.4))
    q = bar(TL.BUILD - 1)
    for i, (shot, f) in enumerate([("shards", 116), ("blitz", 77), ("unnamed", 156), ("meteor", 64)]):
        t0 = q + i * 0.6
        c.append(Clip(shot, t0, t0 + 0.6, sync(f, t0 + 0.2, t0), gain=0.4))
    x.append(Text(bar(TL.BUILD) + 0.2, bar(TL.TITLE) - 0.15, "Write your name before the Hush forgets it.", "center",
                  fi=0.5, fo=0.15))
    # TITLE (bar 38.5) -------------------------------------------------------
    title = bar(TL.TITLE)
    bg = "title_bg" if os.path.exists(os.path.join(SHOTS, "title_bg", "marks.json")) else "tavern_full"
    c.append(Clip(bg, title, TL.LENGTH, marks(bg)["in"], gain=0.0, dark=(title, title + 0.01, 0.42, 0.42)))
    x.append(Text(title, TL.LENGTH, "A Guilda", "title", fi=0.0, fo=0.0))
    x.append(Text(title + 1.4, TL.LENGTH, "A turn-based tactics and guild management game", "tag", fi=0.8, fo=0.0))
    flash = [(title, 0.7, 0.9)]
    return c, x, flash


def letterbox(t):
    """Bar height: the prologue is in scope; the bars slide away when the band
    comes in at the full tavern."""
    a, b = bar(TL.GUILD_FULL), bar(TL.GUILD_FULL) + 0.8
    if t < a:
        return BAR_H
    if t > b:
        return 0
    k = (t - a) / (b - a)
    return int(round(BAR_H * (1 - k * k * (3 - 2 * k))))


# ------------------------------------------------------------------ frames
class Frames:
    def __init__(self, scale=1.0):
        self.cache = {}
        self.scale = scale
        self.size = (int(W * scale), int(H * scale))

    def get(self, shot, i):
        key = (shot, i)
        if key not in self.cache:
            if len(self.cache) > 12:
                self.cache.pop(next(iter(self.cache)))
            im = Image.open(os.path.join(SHOTS, shot, "f%08d.png" % i)).convert("RGB")
            self.cache[key] = im
        return self.cache[key]


def clip_image(fr, cl, t):
    im = fr.get(cl.shot, cl.frame(t))
    if cl.zoom:
        cx, cy, k = cl.zoom
        w, h = W / k, H / k
        x0 = min(max(0, cx - w / 2), W - w)
        y0 = min(max(0, cy - h / 2), H - h)
        im = im.crop((int(x0), int(y0), int(x0 + w), int(y0 + h))).resize((W, H), Image.NEAREST)
    g = ramp(cl.grey, t)
    if g > 0:
        grey = im.convert("L").convert("RGB")
        im = Image.blend(im, grey, g)
    d = ramp(cl.dark, t)
    if d > 0:
        im = Image.blend(im, Image.new("RGB", im.size, (6, 4, 8)), d)
    return im


_vignette = None


def vignette():
    """Dark edges, and a soft shade behind the logo so it reads over the town."""
    global _vignette
    if _vignette is None:
        yy, xx = np.mgrid[0:H, 0:W]
        r = np.sqrt(((xx - W / 2) / (W / 2)) ** 2 + ((yy - H / 2) / (H / 2)) ** 2)
        a = np.clip((r - 0.55) / 0.75, 0, 1) ** 1.6 * 200
        e = np.sqrt(((xx - W / 2) / 760.0) ** 2 + ((yy - 530) / 360.0) ** 2)
        a = np.maximum(a, np.clip(1 - e, 0, 1) ** 0.8 * 165)
        v = np.zeros((H, W, 4), np.uint8)
        v[..., 3] = a.astype(np.uint8)
        _vignette = Image.fromarray(v, "RGBA")
    return _vignette


_emblem = None


def emblem():
    global _emblem
    if _emblem is None:
        e = Image.open(os.path.join(ROOT, "assets", "sprites", "ui", "emblem_guild_64.png")).convert("RGBA")
        _emblem = e.resize((e.width * 3, e.height * 3), Image.NEAREST)
    return _emblem


def compose(t, clips, texts, flashes, fr):
    out = Image.new("RGB", (W, H), (0, 0, 0))
    for cl in clips:
        if cl.t0 <= t < cl.t1:
            a = cl.alpha(t)
            if a <= 0:
                continue
            im = clip_image(fr, cl, t)
            out = im if a >= 1 else Image.blend(out, im, a)
    title = bar(TL.TITLE)
    if t >= title:
        o = out.convert("RGBA")
        o.alpha_composite(vignette())
        e = emblem()
        o.alpha_composite(e, ((W - e.width) // 2, 250))
        out = o.convert("RGB")
    lb = letterbox(t)
    if lb > 0:
        d = ImageDraw.Draw(out)
        d.rectangle((0, 0, W, lb), fill=(0, 0, 0))
        d.rectangle((0, H - lb, W, H), fill=(0, 0, 0))
    # flashes are drawn over the picture, under the words
    for ft, dur, s in flashes:
        if dur > 0 and ft <= t < ft + dur:
            k = s * (1 - (t - ft) / dur) ** 2
            out = Image.blend(out, Image.new("RGB", out.size, (255, 250, 240)), k)
    o = None
    for tx in texts:
        if tx.t0 <= t < tx.t1:
            a = tx.alpha(t)
            if a <= 0:
                continue
            im = tx.image()
            if a < 1:
                im = im.copy()
                im.putalpha(im.getchannel("A").point(lambda v: int(v * a)))
            if o is None:
                o = out.convert("RGBA")
            o.alpha_composite(im, ((W - im.width) // 2, tx.ypos() - im.height // 2))
    if o is not None:
        out = o.convert("RGB")
    # the end fades to black with the music
    end_fade = TL.LENGTH - 2.2
    if t > end_fade:
        k = min(1.0, (t - end_fade) / 2.0)
        out = Image.blend(out, Image.new("RGB", out.size, (0, 0, 0)), k)
    if fr.scale != 1.0:
        out = out.resize(fr.size, Image.BILINEAR)
    return out


# ------------------------------------------------------------------ sound
def read_wav(path):
    with wave.open(path, "rb") as w:
        n, ch, sw, sr = w.getnframes(), w.getnchannels(), w.getsampwidth(), w.getframerate()
        raw = w.readframes(n)
    if sw == 2:
        a = np.frombuffer(raw, np.int16).astype(np.float32) / 32768.0
    elif sw == 4:
        a = np.frombuffer(raw, np.int32).astype(np.float32) / 2147483648.0
    else:
        raise ValueError("%s: %d-byte samples" % (path, sw))
    a = a.reshape(-1, ch)
    if ch == 1:
        a = np.repeat(a, 2, axis=1)
    if sr != SR:
        raise ValueError("%s: %d Hz" % (path, sr))
    return a


def mix(clips, path):
    n = int(math.ceil(TL.LENGTH * SR))
    score = read_wav(os.path.join(CACHE, "score.wav"))[:n]
    out = np.zeros((n, 2), np.float32)
    out[:len(score)] = score
    fx = np.zeros((n, 2), np.float32)
    sounds = {}
    for cl in clips:
        if cl.gain <= 0:
            continue
        if cl.shot not in sounds:
            p = os.path.join(SHOTS, cl.shot, "f.wav")
            sounds[cl.shot] = read_wav(p) if os.path.exists(p) else None
        s = sounds[cl.shot]
        if s is None:
            continue
        i0, i1 = int(round(cl.t0 * SR)), min(n, int(round(cl.t1 * SR)))
        j0 = int(round(cl.src / FPS * SR))
        seg = s[j0:j0 + (i1 - i0)]
        if len(seg) == 0:
            continue
        i1 = i0 + len(seg)
        t = cl.t0 + np.arange(len(seg)) / SR
        env = np.ones(len(seg), np.float32)
        fi, fo = max(cl.fi, 0.012), max(cl.fo, 0.012)
        env = np.minimum(env, np.clip((t - cl.t0) / fi, 0, 1))
        env = np.minimum(env, np.clip((cl.t1 - t) / fo, 0, 1))
        fx[i0:i1] += seg * (env * cl.gain)[:, None]
    y = (out + fx) * 1.35
    # a soft knee above 0.8 instead of clipping, then a little headroom
    a = np.abs(y)
    knee = 0.8
    over = a > knee
    y[over] = np.sign(y[over]) * (knee + (1 - knee) * np.tanh((a[over] - knee) / (1 - knee)))
    y *= 0.97
    # the last seconds fade with the picture
    fade = int(2.2 * SR)
    y[-fade:] *= np.linspace(1, 0, fade)[:, None] ** 1.5
    pcm = (np.clip(y, -1, 1) * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    rms = lambda v: 20 * np.log10(np.sqrt(np.mean(v ** 2)) + 1e-9)  # noqa: E731
    print("mix: peak %.2f  rms %.1f dB  (sfx rms %.1f dB)" % (np.abs(y).max(), rms(y), rms(fx)))
    return path


# ------------------------------------------------------------------ main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--from", dest="start", type=float, default=0.0)
    ap.add_argument("--to", dest="end", type=float, default=None)
    ap.add_argument("--stills", default="")
    ap.add_argument("--sheet", action="store_true")
    ap.add_argument("--half", action="store_true", help="960x540, for a quick look")
    ap.add_argument("--out", default=None)
    a = ap.parse_args()
    clips, texts, flashes = edit()
    os.makedirs(OUT, exist_ok=True)
    fr = Frames(0.5 if a.half else 1.0)

    if a.stills:
        d = os.path.join(CACHE, "stills")
        os.makedirs(d, exist_ok=True)
        for s in a.stills.split(","):
            t = float(s)
            p = os.path.join(d, "t%06.2f.png" % t)
            compose(t, clips, texts, flashes, fr).save(p)
            print(p)
        return

    if a.sheet:
        ts = np.arange(a.start + 0.5, a.end or TL.LENGTH, 1.0)
        cols, w = 6, 320
        h = w * 9 // 16
        rows = (len(ts) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * w, rows * (h + 14)), (20, 18, 24))
        dr = ImageDraw.Draw(sheet)
        for i, t in enumerate(ts):
            im = compose(t, clips, texts, flashes, fr).resize((w, h), Image.BILINEAR)
            x, y = (i % cols) * w, (i // cols) * (h + 14)
            sheet.paste(im, (x, y + 14))
            dr.text((x + 3, y + 1), "%.1fs" % t, fill=(230, 220, 160))
        p = os.path.join(CACHE, "final_sheet.png")
        sheet.save(p)
        print(p)
        return

    end = a.end if a.end is not None else TL.LENGTH
    whole = a.start == 0.0 and a.end is None
    name = a.out or ("AGuilda_Trailer.mp4" if whole else "preview_%d_%d.mp4" % (a.start, end))
    path = os.path.join(OUT, name)
    wav = mix(clips, os.path.join(CACHE, "mix.wav"))
    n0, n1 = int(round(a.start * FPS)), int(round(end * FPS))
    size = "%dx%d" % fr.size
    cmd = [ffmpeg(), "-y", "-loglevel", "error",
           "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", size, "-r", str(FPS), "-i", "-",
           "-ss", "%.4f" % (n0 / FPS), "-t", "%.4f" % ((n1 - n0) / FPS), "-i", wav,
           "-map", "0:v", "-map", "1:a",
           "-c:v", "libx264", "-preset", "slow", "-crf", "16", "-pix_fmt", "yuv420p", "-tune", "animation",
           "-c:a", "aac", "-b:a", "256k", "-movflags", "+faststart", "-shortest", path]
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    for k in range(n0, n1):
        t = k / FPS
        p.stdin.write(compose(t, clips, texts, flashes, fr).tobytes())
        if k % 150 == 0:
            print("  %.1fs" % t, flush=True)
    p.stdin.close()
    if p.wait() != 0:
        raise SystemExit("ffmpeg failed")
    print(path)


if __name__ == "__main__":
    main()
