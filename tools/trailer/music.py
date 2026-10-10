"""The trailer's score, written to the edit's clock (timeline.py) with the
game's own instruments (tools/py/audio.py).

The Bell tolls and cracks; the Hush plays the battle motif half forgotten;
the tavern band comes to life and grows into the factions' song; the battle
theme drops on the beat and stops dead when a member falls; the Unnamed's theme builds to the title, where the
Bell rings again in D major.

    python tools/trailer/music.py      -> tools/_cache/trailer/score.wav (48 kHz stereo)
"""
import os
import sys
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "py"))
import audio as A  # noqa: E402
import timeline as TL  # noqa: E402
from common import CACHE  # noqa: E402
from timeline import bar, BEAT  # noqa: E402

SR = A.SR
OUT_SR = 48000
m = A.midi
f = A.freq


class Stem:
    """One group of instruments: a mono buffer with a place in the stereo field
    and its own share of reverb."""

    def __init__(self, pan=0.0, wet=0.25, room=1.6):
        self.buf = np.zeros(int((TL.LENGTH + 10) * SR))
        self.pan = pan
        self.wet = wet
        self.room = room

    def at(self, t, sound, gain=1.0):
        i = int(round(t * SR))
        end = min(len(self.buf), i + len(sound))
        if 0 <= i < len(self.buf):
            self.buf[i:end] += sound[:end - i] * gain


def impulse(room, seed):
    rng = np.random.default_rng(seed)
    n = int(room * SR)
    t = np.arange(n) / SR
    h = rng.uniform(-1, 1, n) * np.exp(-t * 6.5 / room)
    h = A.lowpass_fft(h, 3400)
    h[:int(0.014 * SR)] = 0
    return h / (np.sqrt(np.sum(h ** 2)) + 1e-9)


def convolve(x, h):
    n = len(x) + len(h)
    nfft = 1 << (n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(x, nfft) * np.fft.rfft(h, nfft), nfft)[:len(x)]


def tune(bars, start, stem, voice, gain, shift=0):
    for (b, d, n) in A.tune(bars, 1, 4):
        stem.at(start + b * BEAT, voice(f(n + shift), d * BEAT), gain)


def chord_notes(root, quality):
    return A.chord(m(root), quality)


def score():
    rng = np.random.default_rng(2026)
    drums = Stem(0.0, 0.16, 1.2)
    perc = Stem(0.15, 0.14, 1.0)
    bass = Stem(0.0, 0.1, 1.2)
    lo_str = Stem(-0.25, 0.2, 1.4)
    hi_str = Stem(0.3, 0.24, 1.6)
    lead = Stem(0.1, 0.26, 1.8)
    brass = Stem(-0.2, 0.28, 1.8)
    choir = Stem(0.0, 0.4, 2.4)
    pads = Stem(0.0, 0.35, 2.4)
    lute = Stem(-0.35, 0.2, 1.4)
    winds = Stem(0.35, 0.3, 1.8)
    bells = Stem(0.2, 0.5, 2.8)
    fx = Stem(0.0, 0.35, 2.2)
    stems = [drums, perc, bass, lo_str, hi_str, lead, brass, choir, pads, lute, winds, bells, fx]

    def toll(t, root, g=1.0):
        bells.at(t, A.bell(f(root), 8.0, 0.3), 1.0 * g)
        bells.at(t, A.bell(f(root + 12), 7.0, 0.42), 0.5 * g)
        bells.at(t, A.bell(f(root + 19), 5.0, 0.65), 0.22 * g)
        drums.at(t, A.drum("taiko", rng, 0.7), 0.55 * g)

    def boom(t, g=1.0, dur=2.0):
        tt = A.t_axis(dur)
        fr = 34 + 30 * np.exp(-tt * 6)
        drums.at(t, np.sin(2 * np.pi * np.cumsum(fr) / SR) * np.exp(-tt * 2.2) * 0.9, g)

    def rev_cymbal(end_t, g=1.0):
        rc = A.drum("cymbal", rng)[::-1]
        fx.at(end_t - len(rc) / SR, rc, g)

    def riser(t0, t1, g=1.0, f0=180, f1=2600):
        dur = t1 - t0
        n = int(dur * SR)
        env = np.linspace(0, 1, n) ** 2.2
        sw = A.sweep(f0, f1, dur, "saw") * 0.18 + A.sweep(f0 * 1.5, f1 * 1.5, dur) * 0.2
        nz = A.bandpass_fft(rng.uniform(-1, 1, n), 900, 9000) * 0.5
        fx.at(t0, (sw + nz * env) * env, g)

    def roll(t0, t1, g0, g1, kind="rim", step0=0.25, step1=0.125):
        t = t0
        while t < t1 - 1e-6:
            k = (t - t0) / (t1 - t0)
            perc.at(t, A.drum(kind, rng, 0.5 + 0.5 * k), g0 + (g1 - g0) * k)
            t += (step0 + (step1 - step0) * k) * BEAT

    # ------------------------------------------------------------ prologue
    toll(0.0, m("A2"))
    toll(bar(2), m("A2"), 0.65)
    pads.at(0.5, A.pad(f(m("A2")), bar(4) - 0.5, rng, harm=5, attack=2.5, release=1.6), 0.9)
    pads.at(0.5, A.pad(f(m("E3")), bar(4) - 0.5, rng, harm=4, attack=3.0, release=1.6), 0.55)
    choir.at(bar(1), A.choir(f(m("A3")), bar(3) + 0.4, rng), 0.55)
    choir.at(bar(2), A.choir(f(m("C4")), bar(2) + 0.4, rng), 0.4)
    # the battle motif on a music box, before anyone has heard the battle theme
    tune(["E5:1 A5:1.5 B5:0.5 C6:1", "A5:1.5 G5:0.5 F5:1 E5:1"], bar(1.5), bells, lambda fr, d: A.bell(fr, 2.6, 1.5), 0.3)
    rev_cymbal(bar(TL.CRACK), 1.2)
    # the crack: a bell struck out of tune, a splintering hiss, a blow from below
    t = bar(TL.CRACK)
    fx.at(t, A.mixn(A.bell(f(m("A3")), 4.5, 1.0), 0.8 * A.bell(f(m("A#3")) * 1.01, 4.5, 1.3), 0.6 * A.bell(f(m("D#4")), 3.0, 1.7)), 1.6)
    n = int(0.5 * SR)
    fx.at(t, A.bandpass_fft(rng.uniform(-1, 1, n), 700, 8000) * np.exp(-np.arange(n) / SR * 10), 0.8)
    drums.at(t, A.drum("taiko", rng, 1.0), 1.3)
    boom(t, 1.0, 2.5)
    # the grey: Am, a phrygian Bb, Am, then A major to lead into the tavern
    dark = [(4.4, 6, "A2", "m"), (6, 8, "A#2", "M"), (8, 9, "A2", "m"), (9, 10, "A2", "M")]
    for b0, b1, root, q in dark:
        ch = chord_notes(root, q)
        dur = bar(b1) - bar(b0) + 0.9
        choir.at(bar(b0), A.choir(f(ch[0]), dur, rng), 0.75)
        choir.at(bar(b0), A.choir(f(ch[2]), dur, rng), 0.5)
        pads.at(bar(b0), A.pad(f(ch[0] - 12), dur, rng, harm=6, attack=1.2), 0.75)
        if q == "M":
            pads.at(bar(b0), A.pad(f(ch[1] + 12), dur, rng, harm=4, attack=1.0), 0.35)
    for b in range(5, 10):
        drums.at(bar(b), A.drum("taiko", rng, 0.55), 0.55 + 0.08 * (b - 5))
        drums.at(bar(b, 0.45), A.drum("taiko", rng, 0.35), 0.35 + 0.05 * (b - 5))
    # the motif again, half forgotten: notes missing, out of tune
    mem = np.random.default_rng(31)
    for (b, d, n) in A.tune(["E5:1 A5:1.5 A#5:0.5 C6:1", "A5:1.5 G5:0.5 F5:1 E5:1"], 1, 4):
        if b >= 3 and mem.random() < 0.35:
            continue
        drift = 2 ** (mem.uniform(-0.4, 0.4) / 12)
        bells.at(bar(6) + b * BEAT, A.bell(f(n) * drift, 2.4, 1.7), 0.24)
        bells.at(bar(6) + b * BEAT + 0.45, A.bell(f(n) * drift, 2.0, 2.2), 0.08)
    # trembling strings rise toward the tavern
    t = bar(8)
    while t < bar(10) - 1e-6:
        k = (t - bar(8)) / (bar(10) - bar(8))
        note = m("E4") if int(round((t - bar(8)) / (BEAT / 4))) % 2 == 0 else m("A3")
        if t >= bar(9):
            note = m("E4") if int(round((t - bar(8)) / (BEAT / 4))) % 2 == 0 else m("C#4")
        lo_str.at(t, A.fiddle(f(note), BEAT / 4 * 1.05, rng, vib=0, harm=6), 0.05 + 0.2 * k)
        t += BEAT / 4
    rev_cymbal(bar(TL.GUILD), 0.8)

    # ------------------------------------------------------------ the guild (D dorian), then the factions (D minor)
    G, FA, BR = TL.GUILD, TL.FACTIONS, TL.BREAK
    full = TL.GUILD_FULL
    chords = {G: ("D3", "m"), G + 1: ("D3", "m"), G + 2: ("C3", "M"), G + 3: ("D3", "m"), G + 4: ("A2", "m"), G + 5: ("F3", "M"),
              FA: ("D3", "m"), FA + 1: ("A#2", "M"), FA + 2: ("C3", "M"), FA + 3: ("D3", "m"), FA + 4: ("A#2", "M"), FA + 5: ("C3", "M"),
              TL.BOARD: ("G2", "M"), BR: ("A2", "M")}
    dorian = A.scale_notes(m("D4") % 12, "dorian", 50, 90)
    for b, (root, q) in chords.items():
        ch = chord_notes(root, q)
        b0 = bar(b)
        if b < BR:
            pat = [ch[0], ch[1], ch[2], ch[0] + 12, ch[2] + 12, ch[0] + 12, ch[2], ch[1]] if b % 2 == 0 else \
                [ch[0], ch[2], ch[0] + 12, ch[1] + 12, ch[2] + 12, ch[1] + 12, ch[0] + 12, ch[2]]
            for k, n in enumerate(pat):
                lute.at(b0 + k * BEAT / 2, A.pluck(f(n), 1.0, 0.8, 3.2, rng), (0.55 if k % 4 == 0 else 0.42) * (0.6 if b < full else 0.7))
        pads.at(b0, A.pad(f(ch[0]), bar(1) + 0.4, rng, harm=4, attack=0.5), 0.3 if b < full else 0.4)
        if full <= b < BR:
            bass.at(b0, A.pluck(f(ch[0] - 12), 1.4, 0.6, 2.0, rng), 0.7)
            bass.at(b0 + 2 * BEAT, A.pluck(f(ch[2] - 12), 1.2, 0.6, 2.2, rng), 0.55)
            perc.at(b0, A.drum("bodhran", rng), 0.7)
            perc.at(b0 + 1.5 * BEAT, A.drum("bodhran", rng, 0.6), 0.5)
            perc.at(b0 + 2 * BEAT, A.drum("bodhran", rng, 0.7), 0.5)
            perc.at(b0 + 3 * BEAT, A.drum("rim", rng), 0.38)
            if b >= full + 2:
                perc.at(b0 + 3.5 * BEAT, A.drum("bodhran", rng, 0.5), 0.5)
                for k in range(8):
                    perc.at(b0 + k * BEAT / 2, A.drum("shaker", rng, 1.0 if k % 2 == 0 else 0.6), 0.55)
            if b == BR - 1:
                for k in range(4):
                    perc.at(b0 + (3 + k * 0.25) * BEAT, A.drum("bodhran", rng, 0.5 + 0.15 * k), 0.55)
        if FA <= b < TL.BOARD:
            # the factions: the band grows into something older and larger
            for k in range(8):
                lo_str.at(b0 + k * BEAT / 2, A.fiddle(f(ch[0] - 12), 0.4 * BEAT, rng, vib=0, harm=7), 0.3 if k % 2 else 0.4)
            choir.at(b0, A.choir(f(ch[0]), bar(1) + 0.5, rng), 0.45)
            choir.at(b0, A.choir(f(ch[2]), bar(1) + 0.5, rng), 0.3)
            drums.at(b0, A.drum("taiko", rng, 0.7), 0.6)
            drums.at(b0 + 2 * BEAT, A.drum("taiko", rng, 0.5), 0.45)
    phrase_a = ["D5:1.5 E5:0.5 F5:1 A5:1", "G5:1.5 F5:0.5 E5:1 C5:1", "D5:1 F5:1 A5:1 D6:1", "C6:1.5 B5:0.5 A5:2"]
    tune(phrase_a, bar(G + 1), winds, lambda fr, d: A.flute(fr, d + 0.05, rng), 0.6)
    tune(phrase_a[1:], bar(full), lead, lambda fr, d: A.fiddle(fr, d + 0.04, rng), 0.5)
    tune(["A5:1.5 G5:0.5 F5:1 E5:1"], bar(G + 5), lead, lambda fr, d: A.fiddle(fr, d + 0.04, rng), 0.55)
    tune(["A5:1.5 G5:0.5 F5:1 E5:1"], bar(G + 5), winds, lambda fr, d: A.flute(fr, d + 0.05, rng), 0.3, 12)
    # the factions' song: the guild tune taken into D minor, fiddles and flute in octaves
    song = ["D5:1.5 E5:0.5 F5:1 A5:1", "A#5:1.5 A5:0.5 F5:1 D5:1", "E5:1 G5:1 C6:1 A#5:1",
            "A5:3 r:1", "F5:1.5 G5:0.5 A5:1 A#5:1", "C6:1.5 A#5:0.5 A5:1 G5:1"]
    tune(song, bar(FA), lead, lambda fr, d: A.fiddle(fr, d + 0.04, rng, vib=6.0), 0.5)
    tune(song, bar(FA), winds, lambda fr, d: A.flute(fr, d + 0.05, rng), 0.3, -12)
    tune(song, bar(FA), brass, lambda fr, d: A.horn(fr, d + 0.05, rng), 0.25, -24)
    # each faction's card turns like a page: a bell and a low drum
    perc.at(bar(FA), A.drum("cymbal", rng), 0.8)
    for i, root in enumerate(("D5", "F5", "A5", "C6")):
        t = bar(FA + 0.75 + i * 1.25)
        bells.at(t, A.bell(f(m(root)), 3.0, 0.9), 0.32)
        bells.at(t, A.bell(f(m(root) + 7), 2.5, 1.1), 0.14)
        drums.at(t, A.drum("taiko", rng, 0.8), 0.55)
    # the board, then the break: a held A, a snare roll and a riser into the drop
    tune(["B5:1 D6:1 G5:1 B5:1"], bar(TL.BOARD), lead, lambda fr, d: A.fiddle(fr, d + 0.04, rng), 0.55)
    tune(["B5:1 D6:1 G5:1 B5:1"], bar(TL.BOARD), winds, lambda fr, d: A.flute(fr, d + 0.05, rng), 0.3, 12)
    for (b, d, n) in A.tune(["B5:1 D6:1 G5:1 B5:1"], 1, 4):
        if n in dorian:
            hi_str.at(bar(TL.BOARD) + b * BEAT, A.fiddle(f(A.third_below(n, dorian)), d * BEAT + 0.04, rng), 0.28)
    tune(["C#6:1 E6:1 r:2"], bar(BR), lead, lambda fr, d: A.fiddle(fr, d + 0.04, rng), 0.55)
    pads.at(bar(BR), A.pad(f(m("A2")), bar(1), rng, harm=6, attack=0.3), 0.6)
    choir.at(bar(BR), A.choir(f(m("C#4")), bar(1), rng), 0.5)
    roll(bar(BR), bar(TL.BATTLE) - 0.12, 0.08, 0.9)
    riser(bar(BR), bar(TL.BATTLE) - 0.12, 0.7)
    rev_cymbal(bar(TL.BATTLE) - 0.12, 0.9)

    # ------------------------------------------------------------ battle (D minor)
    B = TL.BATTLE
    battle = {B: ("D3", "m"), B + 1: ("D3", "m"), B + 2: ("A#2", "M"), B + 3: ("C3", "M"),
              B + 4: ("D3", "m"), B + 5: ("A#2", "M"), B + 6: ("C3", "M")}
    for b, (root, q) in battle.items():
        ch = chord_notes(root, q)
        r, third = ch[0], ch[1] - ch[0]
        b0 = bar(b)
        for beat in range(4):
            n = r - 12 + (7 if beat == 3 else 0)
            for off, d, g in ((0, 0.45, 0.55), (0.5, 0.22, 0.38), (0.75, 0.22, 0.42)):
                lo_str.at(b0 + (beat + off) * BEAT, A.fiddle(f(n), d * BEAT, rng, vib=0, harm=8), g * 1.1)
        shape = [0, 7, 12, 7, third, 7, 12, 7] if (b - B) % 2 == 0 else [0, 7, third, 7, 12, 7, third + 12, 7]
        for k, iv in enumerate(shape):
            hi_str.at(b0 + k * BEAT / 2, A.fiddle(f(r + iv), 0.42 * BEAT, rng, vib=0, harm=6), 0.3 if k % 2 else 0.38)
        pads.at(b0, A.pad(f(r), bar(1) + 0.3, rng, harm=6, attack=0.2), 0.6)
        bass.at(b0, A.pluck(f(r - 12), 1.2, 0.5, 2.0, rng), 0.9)
        drums.at(b0, A.drum("taiko", rng), 1.2)
        drums.at(b0 + 1.5 * BEAT, A.drum("tom", rng), 0.7)
        drums.at(b0 + 2 * BEAT, A.drum("taiko", rng, 0.8), 1.0)
        drums.at(b0 + 3.5 * BEAT, A.drum("tom", rng, 0.8), 0.6)
        if b >= B + 4:
            choir.at(b0, A.choir(f(r), bar(1) + 0.5, rng), 0.9)
            choir.at(b0, A.choir(f(ch[2]), bar(1) + 0.5, rng), 0.7)
            drums.at(b0 + 2.5 * BEAT, A.drum("taiko", rng, 0.6), 0.6)
            perc.at(b0 + 1 * BEAT, A.drum("rim", rng), 0.55)
            perc.at(b0 + 3 * BEAT, A.drum("rim", rng), 0.55)
            for k in range(16):
                perc.at(b0 + k * BEAT / 4, A.drum("shaker", rng, 1.0 if k % 4 == 0 else 0.55), 0.6)
    perc.at(bar(B), A.drum("cymbal", rng), 1.4)
    perc.at(bar(B + 4), A.drum("cymbal", rng), 1.1)
    drums.at(bar(B), A.drum("taiko", rng), 0.8)
    boom(bar(B), 1.0)
    horn_call = ["D4:3 A3:1", "D4:1 F4:1 A4:2", "A#4:2 A4:1 F4:1", "G4:4"]
    tune(horn_call, bar(B), brass, lambda fr, d: A.horn(fr, d + 0.05, rng), 0.8)
    tune(horn_call, bar(B), brass, lambda fr, d: A.horn(fr, d + 0.05, rng), 0.4, -12)
    # the theme: its last bar never comes, the fall cuts it off
    theme = ["A4:1 D5:1.5 E5:0.5 F5:1", "D5:1.5 C5:0.5 A#4:1 A4:1", "G4:1 C5:1.5 D5:0.5 E5:1"]
    tune(theme, bar(B + 4), lead, lambda fr, d: A.fiddle(fr, d, rng, vib=6.5), 0.45)
    tune(theme, bar(B + 4), lead, lambda fr, d: A.fiddle(fr * 1.003, d, rng, vib=6.0), 0.45)
    tune(theme, bar(B + 4), brass, lambda fr, d: A.horn(fr, d + 0.05, rng), 0.55, -12)
    roll(bar(TL.DEATH - 1, 2), bar(TL.DEATH) - 0.05, 0.2, 0.85)
    for k in range(4):
        drums.at(bar(TL.DEATH - 1, 3 + k * 0.25), A.drum("tom", rng, 0.6 + 0.12 * k), 0.6)

    # ------------------------------------------------------------ the Unnamed (D minor)
    # a low hum carries the silence into her theme
    F = TL.FINAL
    choir.at(bar(TL.DEATH, 2), A.choir(f(m("D3")), bar(F) - bar(TL.DEATH, 2) + 0.6, rng), 0.35)
    final = {F: ("D3", "m"), F + 1: ("A#2", "M"), F + 2: ("F3", "M"), F + 3: ("C3", "M"), F + 4: ("G2", "m"), F + 5: ("A2", "M")}
    for b, (root, q) in final.items():
        ch = chord_notes(root, q)
        b0 = bar(b)
        choir.at(b0, A.choir(f(ch[0]), bar(1) + 0.6, rng), 0.9)
        choir.at(b0, A.choir(f(ch[1] + 12), bar(1) + 0.6, rng), 0.6 if b >= F + 2 else 0.35)
        pads.at(b0, A.pad(f(ch[0] - 12), bar(1) + 0.4, rng, harm=7, attack=0.3), 0.8)
        if b <= F + 1:
            drums.at(b0, A.drum("taiko", rng), 1.0)
            boom(b0, 0.6, 1.6)
            bells.at(b0, A.bell(f(ch[0] + 24), 3.0, 0.9), 0.3)
            bells.at(b0 + 2 * BEAT, A.bell(f(ch[2] + 24), 3.0, 1.0), 0.2)
            continue
        for k in range(8):
            lo_str.at(b0 + k * BEAT / 2, A.fiddle(f(ch[0] - 12 + (12 if k % 2 else 0)), 0.22 * 1.2, rng, vib=0, harm=8), 0.5)
        bass.at(b0, A.pluck(f(ch[0] - 12), 1.2, 0.5, 2.0, rng), 0.9)
        drums.at(b0, A.drum("taiko", rng), 1.0)
        drums.at(b0 + 1 * BEAT, A.drum("tom", rng), 0.5)
        drums.at(b0 + 2 * BEAT, A.drum("taiko", rng, 0.8), 0.85)
        drums.at(b0 + 2.5 * BEAT, A.drum("taiko", rng, 0.6), 0.6)
        drums.at(b0 + 3 * BEAT, A.drum("tom", rng), 0.6)
        if b >= F + 4:
            for k in range(8):
                drums.at(b0 + k * BEAT / 2, A.drum("taiko", rng, 0.5), 0.35)
            for k in range(16):
                perc.at(b0 + k * BEAT / 4, A.drum("shaker", rng, 1.0 if k % 4 == 0 else 0.55), 0.6)
            perc.at(b0, A.drum("cymbal", rng), 1.0)
        if b < TL.BUILD:
            shape = [0, 7, 12, 7, 3 if q == "m" else 4, 7, 12, 7]
            for k, iv in enumerate(shape):
                hi_str.at(b0 + k * BEAT / 2, A.fiddle(f(ch[0] + iv), 0.42 * BEAT, rng, vib=0, harm=6), 0.3)
    # her motif on the horns, then the climb into the title
    motif = ["A4:1 D5:1.5 E5:0.5 F5:1", "D5:1.5 C5:0.5 A#4:1 A4:1"]
    tune(motif, bar(F + 2), brass, lambda fr, d: A.horn(fr, d + 0.05, rng), 0.85)
    tune(motif, bar(F + 2), brass, lambda fr, d: A.horn(fr, d + 0.05, rng), 0.4, -12)
    climax = ["G5:1.5 F5:0.5 D5:1 A#4:1", "A4:1 C#5:1 E5:1 A5:1"]
    tune(climax, bar(F + 4), lead, lambda fr, d: A.fiddle(fr, d, rng, vib=6.5), 0.5)
    tune(climax, bar(F + 4), lead, lambda fr, d: A.fiddle(fr * 1.003, d, rng, vib=6.0), 0.5)
    tune(climax, bar(F + 4), brass, lambda fr, d: A.horn(fr, d + 0.05, rng), 0.6, -12)
    tune(climax, bar(F + 4), winds, lambda fr, d: A.flute(fr, d + 0.05, rng), 0.35, 12)
    # the build: rolls, rising choir, a riser and a breath before the hit
    roll(bar(TL.BUILD), bar(TL.TITLE) - 0.1, 0.15, 1.0, "rim", 0.25, 0.0625)
    t = bar(TL.BUILD)
    while t < bar(TL.TITLE) - 0.1:
        k = (t - bar(TL.BUILD)) / bar(1)
        drums.at(t, A.drum("taiko", rng, 0.4 + 0.6 * k), 0.4 + 0.6 * k)
        t += BEAT / 2
    choir.at(bar(TL.BUILD), A.choir(f(m("E4")), bar(1), rng), 0.7)
    choir.at(bar(TL.BUILD, 2), A.choir(f(m("A4")), bar(0.5), rng), 0.6)
    riser(bar(TL.BUILD), bar(TL.TITLE) - 0.1, 0.9, 220, 3200)
    rev_cymbal(bar(TL.TITLE) - 0.1, 1.0)

    # ------------------------------------------------------------ the title: the Bell rings again, in D major
    t = bar(TL.TITLE)
    drums.at(t, A.drum("taiko", rng), 1.25)
    drums.at(t + 0.02, A.drum("taiko", rng), 0.8)
    boom(t, 1.0, 3.0)
    perc.at(t, A.drum("cymbal", rng), 1.3)
    toll(t, m("D2"), 1.1)
    hold = bar(TL.END) - t
    for n, g in (("D3", 0.7), ("A3", 0.6), ("D4", 0.55), ("F#4", 0.45)):
        brass.at(t, A.horn(f(m(n)), 3.2, rng), g)
    for n, g in (("D4", 0.8), ("F#4", 0.6), ("A4", 0.55)):
        choir.at(t, A.choir(f(m(n)), hold - 0.5, rng), g)
    for n, g in (("D2", 0.8), ("A2", 0.5)):
        pads.at(t, A.pad(f(m(n)), hold - 0.5, rng, harm=6, attack=0.05, release=3.0), g)
    tune(["E5:1 A5:1.5 B5:0.5 C#6:1"], t + bar(1.5), bells, lambda fr, d: A.bell(fr, 3.0, 1.2), 0.22, -2)
    toll(bar(TL.TITLE + 2), m("D3"), 0.45)
    return stems


def mix(stems):
    n = len(stems[0].buf)
    left = np.zeros(n)
    right = np.zeros(n)
    irs = {}
    for i, s in enumerate(stems):
        a = (s.pan + 1) * np.pi / 4
        left += s.buf * np.cos(a) * 1.414
        right += s.buf * np.sin(a) * 1.414
        if s.wet > 0:
            key = s.room
            if key not in irs:
                irs[key] = (impulse(s.room, 11), impulse(s.room, 23))
            left += convolve(s.buf, irs[key][0]) * s.wet
            right += convolve(s.buf, irs[key][1]) * s.wet
    y = np.stack([left, right], axis=1)[:int(TL.LENGTH * SR)]
    t = np.arange(len(y)) / SR
    # a member falls: everything stops, tails and all, and comes back with her theme
    gate = np.ones(len(y))
    d0, d1 = bar(TL.DEATH), bar(TL.DEATH, 2)
    gate[(t >= d0) & (t < d1)] = 0.0
    ramp = (t >= d0 - 0.015) & (t < d0)
    gate[ramp] = (d0 - t[ramp]) / 0.015
    rise = (t >= d1) & (t < bar(TL.FINAL))
    gate[rise] = ((t[rise] - d1) / (bar(TL.FINAL) - d1)) ** 2
    # a breath of silence before the drop and before the title
    for g in (bar(TL.BATTLE), bar(TL.TITLE)):
        gap = (t >= g - 0.1) & (t < g)
        gate[gap] = 0.0
    # fade out at the end
    tail = t > TL.LENGTH - 2.5
    gate[tail] *= np.clip((TL.LENGTH - t[tail]) / 2.5, 0, 1)
    y *= gate[:, None]
    # level: peak-normalize, then a gentle soft clip
    y = y / (np.max(np.abs(y)) + 1e-9) * 0.98
    y = np.tanh(y * 1.25) / np.tanh(1.25) * 0.9
    return y


def resample(y, sr_in, sr_out):
    n_out = int(round(len(y) * sr_out / sr_in))
    out = np.zeros((n_out, y.shape[1]))
    for c in range(y.shape[1]):
        spec = np.fft.rfft(y[:, c])
        out[:, c] = np.fft.irfft(spec, n_out) * (n_out / len(y))
    return out


def write(path, y, sr):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    pcm = (np.clip(y, -1, 1) * 32000).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(y.shape[1])
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())


def main():
    y = mix(score())
    y = resample(y, SR, OUT_SR)
    path = os.path.join(CACHE, "score.wav")
    write(path, y, OUT_SR)
    # loudness per bar, to check the shape of the whole
    mono = y.mean(axis=1)
    per = int(TL.BAR * OUT_SR)
    rms = [20 * np.log10(np.sqrt(np.mean(mono[i:i + per] ** 2)) + 1e-9) for i in range(0, len(mono), per)]
    print(path, "%.1fs" % (len(y) / OUT_SR))
    print("dB per bar:", " ".join("%d:%.0f" % (i, r) for i, r in enumerate(rms)))


if __name__ == "__main__":
    main()
