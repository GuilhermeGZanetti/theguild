"""Procedural music and sound effects for A Guilda (numpy only).

Music: a hand-written jig in the guild (lute, fiddle, flute, frame drum), a
horn-and-strings battle theme over war drums in combat, and a battle track per
biome that rewrites that theme's motif (coast shanty, jungle marimba, autumn
waltz, desert maqam, the Hush half-forgotten). Each has a danger layer that
lines up sample for sample with its base track. Loops are seamless: everything that rings past
the loop end is wrapped back onto the start.

    python tools/py/audio.py [--only music|sfx] [--track name]
Outputs assets/audio/music/*.wav and assets/audio/sfx/*.wav (16-bit mono).
"""
import os
import sys
import wave
import numpy as np

SR = 22050
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT_MUSIC = os.path.join(ROOT, "assets", "audio", "music")
OUT_SFX = os.path.join(ROOT, "assets", "audio", "sfx")

NOTE = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8,
        "A": 9, "A#": 10, "Bb": 10, "B": 11}


def midi(name):
    """'A3' -> 57"""
    n = name[:-1]
    o = int(name[-1])
    return 12 * (o + 1) + NOTE[n]


def freq(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


def t_axis(dur):
    return np.arange(int(dur * SR)) / SR


def env_adsr(n, a, d, s, r, sr=SR):
    a_n, d_n, r_n = int(a * sr), int(d * sr), int(r * sr)
    e = np.ones(n) * s
    if a_n > 0:
        e[:min(a_n, n)] = np.linspace(0, 1, a_n)[:min(a_n, n)]
    if d_n > 0 and a_n < n:
        seg = min(d_n, n - a_n)
        e[a_n:a_n + seg] = np.linspace(1, s, d_n)[:seg]
    if r_n > 0:
        r_n = min(r_n, n)
        e[-r_n:] *= np.linspace(1, 0, r_n)
    return e


def lowpass_fft(x, cutoff, sr=SR, slope=2.0):
    """Gentle frequency-domain low-pass (whole buffer)."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / sr)
    X *= 1.0 / (1.0 + (f / max(cutoff, 1.0)) ** slope)
    return np.fft.irfft(X, len(x))


def bandpass_fft(x, lo, hi, sr=SR):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / sr)
    X *= (1.0 / (1.0 + (lo / np.maximum(f, 1.0)) ** 2)) * (1.0 / (1.0 + (f / hi) ** 2))
    return np.fft.irfft(X, len(x))


def noise(n, rng):
    return rng.uniform(-1, 1, n)


# ------------------------------------------------------------------ instruments
def pluck(f, dur, bright=1.0, decay=3.0, rng=None):
    """Lute / harp: harmonics with faster decay for higher partials."""
    t = t_axis(dur)
    y = np.zeros_like(t)
    for k in range(1, 12):
        if f * k > SR / 2.2:
            break
        amp = (1.0 / k) * (bright ** (k - 1)) * (1.0 if k % 2 else 0.7)
        y += amp * np.sin(2 * np.pi * f * k * t + k * 0.3) * np.exp(-t * decay * (0.6 + 0.35 * k))
    # pick transient
    if rng is not None:
        n = min(len(t), int(0.012 * SR))
        y[:n] += noise(n, rng) * np.linspace(0.25, 0, n)
    a = min(len(t), int(0.004 * SR))
    y[:a] *= np.linspace(0, 1, a)
    return y * 0.5


def flute(f, dur, rng, vib=5.2, breath=0.06):
    t = t_axis(dur)
    vib_amt = np.clip((t - 0.25) * 2, 0, 1) * 0.006
    ph = 2 * np.pi * np.cumsum(f * (1 + vib_amt * np.sin(2 * np.pi * vib * t))) / SR
    y = np.sin(ph) + 0.22 * np.sin(2 * ph) + 0.06 * np.sin(3 * ph)
    b = lowpass_fft(noise(len(t), rng), f * 2.0) * breath * 3
    e = env_adsr(len(t), 0.06, 0.1, 0.85, min(0.12, dur * 0.3))
    return (y + b) * e * 0.32


def fiddle(f, dur, rng, vib=5.8, harm=10):
    t = t_axis(dur)
    vib_amt = np.clip((t - 0.15) * 3, 0, 1) * 0.008
    ph = 2 * np.pi * np.cumsum(f * (1 + vib_amt * np.sin(2 * np.pi * vib * t + rng.uniform(0, 6)))) / SR
    y = np.zeros_like(t)
    for k in range(1, harm + 1):
        if f * k > SR / 2.2:
            break
        y += np.sin(k * ph) / k * (0.9 ** k)
    bow = lowpass_fft(noise(len(t), rng), 3000) * 0.03
    e = env_adsr(len(t), 0.05, 0.08, 0.8, min(0.1, dur * 0.3))
    return (y + bow) * e * 0.22


def horn(f, dur, rng, vib=4.5):
    """Brass-like: rich harmonics with a bright blat on the attack."""
    t = t_axis(dur)
    vib_amt = np.clip((t - 0.3) * 2, 0, 1) * 0.004
    ph = 2 * np.pi * np.cumsum(f * (1 + vib_amt * np.sin(2 * np.pi * vib * t + rng.uniform(0, 6)))) / SR
    bright = 0.5 + 0.25 * np.exp(-t * 9) * np.clip(t / 0.03, 0, 1)
    y = np.zeros_like(t)
    for k in range(1, 13):
        if f * k > SR / 2.2:
            break
        y += bright ** (k - 1) * np.sin(k * ph)
    e = env_adsr(len(t), 0.06, 0.15, 0.8, min(0.18, dur * 0.3))
    return y * e * 0.16


def pad(f, dur, rng, detune=0.006, harm=6, attack=0.6, release=0.8):
    t = t_axis(dur)
    y = np.zeros_like(t)
    for dt in (-detune, 0, detune):
        ph = 2 * np.pi * f * (1 + dt) * t + rng.uniform(0, 6)
        for k in range(1, harm + 1):
            y += np.sin(k * ph) / (k * k ** 0.3)
    e = env_adsr(len(t), attack, 0.3, 0.9, min(release, dur * 0.5))
    return y * e * 0.07


def choir(f, dur, rng):
    """Vowel-ish 'aah': pad with formant-weighted harmonics."""
    t = t_axis(dur)
    y = np.zeros_like(t)
    formants = [(700, 110), (1220, 120), (2600, 170)]
    for dt in (-0.004, 0.0, 0.005):
        vib = 1 + 0.004 * np.sin(2 * np.pi * 4.8 * t + rng.uniform(0, 6))
        ph = 2 * np.pi * np.cumsum(f * (1 + dt) * vib) / SR
        for k in range(1, 24):
            fk = f * k
            if fk > SR / 2.3:
                break
            w = sum(np.exp(-((fk - fc) / bw) ** 2 / 2) * (1.0 / (i + 1)) for i, (fc, bw) in enumerate(formants)) + 0.15 / k
            y += w * np.sin(k * ph)
    e = env_adsr(len(t), 0.5, 0.2, 0.9, min(0.9, dur * 0.5))
    return y * e * 0.05


def bell(f, dur, decay=1.2):
    t = t_axis(dur)
    y = np.zeros_like(t)
    for ratio, amp, dk in [(1.0, 1.0, 1.0), (2.0, 0.5, 1.3), (2.76, 0.45, 1.8), (5.4, 0.25, 2.6), (8.93, 0.12, 3.5), (0.5, 0.3, 0.7)]:
        if f * ratio < SR / 2.2:
            y += amp * np.sin(2 * np.pi * f * ratio * t) * np.exp(-t * decay * dk)
    a = min(len(t), int(0.003 * SR))
    y[:a] *= np.linspace(0, 1, a)
    return y * 0.28


def drum(kind, rng, vel=1.0):
    if kind == "bodhran":
        t = t_axis(0.45)
        f = 55 + 70 * np.exp(-t * 30)
        y = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9)
        y += lowpass_fft(noise(len(t), rng), 1800) * np.exp(-t * 40) * 0.5
        return y * 0.55 * vel
    if kind == "rim":
        t = t_axis(0.18)
        y = bandpass_fft(noise(len(t), rng), 900, 4200) * np.exp(-t * 38) * 1.4
        y += np.sin(2 * np.pi * 420 * t) * np.exp(-t * 60) * 0.3
        return y * 0.35 * vel
    if kind == "taiko":
        t = t_axis(0.9)
        f = 42 + 60 * np.exp(-t * 18)
        y = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 5.5)
        y += lowpass_fft(noise(len(t), rng), 900) * np.exp(-t * 25) * 0.6
        return y * 0.8 * vel
    if kind == "shaker":
        t = t_axis(0.09)
        y = bandpass_fft(noise(len(t), rng), 3000, 9000) * np.exp(-t * 55)
        return y * 0.18 * vel
    if kind == "tom":
        t = t_axis(0.5)
        f = 90 + 50 * np.exp(-t * 20)
        y = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 8)
        return y * 0.5 * vel
    if kind == "cymbal":
        t = t_axis(1.6)
        y = bandpass_fft(noise(len(t), rng), 4000, 10000) * np.exp(-t * 3.2)
        return y * 0.12 * vel
    if kind == "hand":  # conga-like slap
        t = t_axis(0.3)
        f = 190 + 90 * np.exp(-t * 40)
        y = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 16)
        y += bandpass_fft(noise(len(t), rng), 800, 5000) * np.exp(-t * 60) * 0.4
        return y * 0.4 * vel
    if kind == "doum":  # the deep stroke of a goblet drum
        t = t_axis(0.5)
        f = 80 + 70 * np.exp(-t * 30)
        y = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 7)
        return y * 0.6 * vel
    if kind == "tek":  # its rim stroke
        t = t_axis(0.12)
        y = bandpass_fft(noise(len(t), rng), 2000, 8000) * np.exp(-t * 70)
        y += np.sin(2 * np.pi * 700 * t) * np.exp(-t * 90) * 0.5
        return y * 0.3 * vel
    if kind == "block":  # wood block
        t = t_axis(0.15)
        y = np.sin(2 * np.pi * 1100 * t) * np.exp(-t * 45) + np.sin(2 * np.pi * 2970 * t) * np.exp(-t * 70) * 0.3
        return y * 0.25 * vel
    raise ValueError(kind)


def mallet(f, dur, bright=1.0):
    """Marimba: a wooden bar with its tuned overtone and a soft knock."""
    t = t_axis(dur)
    y = np.sin(2 * np.pi * f * t) * np.exp(-t * 3.5)
    for ratio, amp, dk in ((3.93, 0.35, 14), (9.2, 0.12, 40)):
        if f * ratio < SR / 2.2:
            y += amp * bright * np.sin(2 * np.pi * f * ratio * t) * np.exp(-t * dk)
    a = min(len(t), int(0.002 * SR))
    y[:a] *= np.linspace(0, 1, a)
    return y * 0.4


def reed(f, dur, rng, vib=5.5):
    """Double reed: nasal, odd-heavy harmonics with a scoop up into each note."""
    t = t_axis(dur)
    bend = 1 - 0.03 * np.exp(-t * 25)
    vib_amt = np.clip((t - 0.2) * 2.5, 0, 1) * 0.01
    ph = 2 * np.pi * np.cumsum(f * bend * (1 + vib_amt * np.sin(2 * np.pi * vib * t + rng.uniform(0, 6)))) / SR
    y = np.zeros_like(t)
    for k in range(1, 15):
        fk = f * k
        if fk > SR / 2.2:
            break
        y += (1.0 if k % 2 else 0.55) / k ** 0.8 * (1 + 1.5 * np.exp(-((fk - 1400) / 500) ** 2)) * np.sin(k * ph)
    y += bandpass_fft(noise(len(t), rng), 1500, 4000) * 0.15
    e = env_adsr(len(t), 0.03, 0.08, 0.85, min(0.1, dur * 0.3))
    return y * e * 0.13


def surf(dur, rng):
    """A wave rolling in and drawing back."""
    n = int(dur * SR)
    env = np.sin(np.pi * np.linspace(0, 1, n)) ** 2
    y = lowpass_fft(noise(n, rng), 600) * env * 2.0 + bandpass_fft(noise(n, rng), 2000, 6000) * env ** 3 * 0.3
    return y * 0.5


def wind(dur, rng):
    """Desert wind: a band of noise that wanders in pitch."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    env = np.sin(np.pi * np.linspace(0, 1, n)) ** 2
    lo = bandpass_fft(noise(n, rng), 300, 900)
    hi = bandpass_fft(noise(n, rng), 1200, 3000)
    mix = 0.5 + 0.5 * np.sin(2 * np.pi * t / dur * 3 + rng.uniform(0, 6))
    return (lo * (1 - mix) + hi * mix * 0.6) * env * 0.9


def crackle(dur, rng, density=14.0):
    """Embers: sparse pops."""
    n = int(dur * SR)
    imp = (rng.random(n) < density / SR) * rng.uniform(0.2, 1.0, n)
    return bandpass_fft(imp, 1500, 8000) * 6.0


# ------------------------------------------------------------------ mixing
class Track:
    def __init__(self, bars, bpm, beats_per_bar=4, seed=0):
        self.bpm = bpm
        self.beat = 60.0 / bpm
        self.bars = bars
        self.bpb = beats_per_bar
        self.length = bars * beats_per_bar * self.beat
        self.n = int(round(self.length * SR))
        self.buf = np.zeros(self.n + SR * 6)
        self.rng = np.random.default_rng(seed)

    def at(self, beat_pos, sound, gain=1.0):
        i = int(round(beat_pos * self.beat * SR))
        end = min(len(self.buf), i + len(sound))
        if i < len(self.buf):
            self.buf[i:end] += sound[:end - i] * gain

    def finish(self, reverb=0.25, room=1.6):
        y = self.buf
        if reverb > 0:
            y = y + reverb * convolve_reverb(y, room, self.rng)
        # wrap the tail onto the start for a seamless loop
        loop = y[:self.n].copy()
        tail = y[self.n:]
        k = min(len(tail), self.n)
        loop[:k] += tail[:k]
        return loop


_ir_cache = {}


def convolve_reverb(x, room, rng):
    key = room
    if key not in _ir_cache:
        n = int(room * SR)
        t = np.arange(n) / SR
        ir = rng.uniform(-1, 1, n) * np.exp(-t * 6.5 / room)
        ir = lowpass_fft(ir, 3200)
        ir[: int(0.012 * SR)] = 0
        ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
        _ir_cache[key] = ir
    ir = _ir_cache[key]
    n = len(x) + len(ir)
    nfft = 1 << (n - 1).bit_length()
    y = np.fft.irfft(np.fft.rfft(x, nfft) * np.fft.rfft(ir, nfft), nfft)[:len(x)]
    return y * 0.9


def normalize(y, peak=0.85):
    m = np.max(np.abs(y)) + 1e-9
    y = y / m * peak
    return np.tanh(y * 1.1) / np.tanh(1.1)


def write_wav(path, y, peak=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = np.clip(y, -1, 1)
    pcm = (data * 32000).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


# ------------------------------------------------------------------ harmony helpers
MODES = {
    "aeolian": [0, 2, 3, 5, 7, 8, 10], "dorian": [0, 2, 3, 5, 7, 9, 10], "phrygian": [0, 1, 3, 5, 7, 8, 10],
    "ionian": [0, 2, 4, 5, 7, 9, 11], "mixolydian": [0, 2, 4, 5, 7, 9, 10], "harmonic": [0, 2, 3, 5, 7, 8, 11],
    "phrygdom": [0, 1, 4, 5, 7, 8, 10],
}


def scale_notes(root, mode, lo, hi):
    out = []
    for m in range(lo, hi + 1):
        if (m - root) % 12 in MODES[mode]:
            out.append(m)
    return out


def chord(root_midi, quality):
    iv = {"m": [0, 3, 7], "M": [0, 4, 7], "sus": [0, 5, 7], "dim": [0, 3, 6], "5": [0, 7, 12], "m7": [0, 3, 7, 10]}[quality]
    return [root_midi + i for i in iv]


def melody(rng, chords, scale, beats_per_chord, rhythm_pool, start_note, motif_bars=2, span=(60, 84)):
    """Scale-walk melody that lands on chord tones on strong beats, with a
    repeated motif so phrases feel composed rather than random."""
    notes = []
    cur = start_note
    motif = None
    for ci, ch in enumerate(chords):
        tones = [n for n in scale if span[0] <= n <= span[1]]
        chord_pcs = {c % 12 for c in ch}
        if ci % (motif_bars * 2) >= motif_bars and motif is not None and rng.random() < 0.7:
            # restate the motif transposed to fit this chord
            shift = min(tones, key=lambda n: abs(n - cur)) - motif[0][2]
            for (off, dur, n) in motif:
                nn = min(tones, key=lambda x: abs(x - (n + shift)))
                notes.append((ci * beats_per_chord + off, dur, nn))
            cur = notes[-1][2]
            continue
        pos = 0.0
        bar_notes = []
        while pos < beats_per_chord - 1e-6:
            dur = rhythm_pool[rng.integers(len(rhythm_pool))]
            dur = min(dur, beats_per_chord - pos)
            strong = abs(pos - round(pos)) < 1e-6 and int(round(pos)) % 2 == 0
            cands = [n for n in tones if abs(n - cur) <= 4] or tones
            if strong:
                ct = [n for n in cands if n % 12 in chord_pcs]
                if ct:
                    cands = ct
            weights = np.array([1.0 / (1 + abs(n - cur)) for n in cands])
            n = cands[rng.choice(len(cands), p=weights / weights.sum())]
            if rng.random() < 0.12 and not strong:
                n = None  # rest
            if n is not None:
                bar_notes.append((pos, dur, n))
                cur = n
            pos += dur
        if ci % (motif_bars * 2) < motif_bars:
            motif = bar_notes if motif is None and bar_notes else motif
        for (off, dur, n) in bar_notes:
            notes.append((ci * beats_per_chord + off, dur, n))
    return notes


def tune(bars, unit, beats_per_bar):
    """Hand-written melody: one 'D5:2 A4:1 r:1' string per bar, durations in
    `unit` beats; every bar must fill exactly. Returns [(beat, dur, midi)]."""
    notes = []
    for i, bar in enumerate(bars):
        pos = 0.0
        for tok in bar.split():
            name, d = tok.split(":")
            d = float(d) * unit
            if name != "r":
                notes.append((i * beats_per_bar + pos, d, midi(name)))
            pos += d
        assert abs(pos - beats_per_bar) < 1e-6, "bar %d is %.2f beats: %s" % (i, pos, bar)
    return notes


def third_below(n, scale):
    """The diatonic third under n, for folk-style parallel harmony."""
    return scale[scale.index(n) - 2]


def lay(tr, bars, start, voice, gain, shift=0, unit=1):
    """Plays a hand-written tune from beat `start`; voice(hz, seconds) -> samples."""
    for (b, d, n) in tune(bars, unit, tr.bpb):
        tr.at(start + b, voice(freq(n + shift), d * tr.beat), gain)


def danger_layer(tr, chords, grid, kit, rims, trem, trem_gain=0.2, accent=4, cymbal_every=4, extra=None):
    """A biome's danger layer: a fast grid of `kit`, rim accents, a high tremolo
    on the chord and a cymbal every few bars; extra(ci, chord, b0) adds its own."""
    rng = tr.rng
    step = tr.bpb / grid
    for ci, ch in enumerate(chords):
        b0 = ci * tr.bpb
        for k in range(grid):
            tr.at(b0 + k * step, drum(kit, rng, 1.0 if k % accent == 0 else 0.6), 1.0)
            n = (ch[2] if k % 2 == 0 else ch[1]) + 12
            tr.at(b0 + k * step, trem(freq(n), step * tr.beat * 1.05), trem_gain)
        for k in rims:
            tr.at(b0 + k, drum("rim", rng), 0.8)
        if ci % cymbal_every == cymbal_every - 1:
            tr.at(b0 + tr.bpb - 1, drum("cymbal", rng), 1.0)
        if extra:
            extra(ci, ch, b0)
    # match loudness, not peaks: the layers differ a lot in how spiky they are
    y = tr.finish(0.18, 1.2)
    y = y / (np.sqrt(np.mean(y ** 2)) + 1e-9) * 0.085
    return 0.85 * np.tanh(y / 0.85)


# ------------------------------------------------------------------ tracks
# Tavern jig in AABB form, 8 bars of 6/8 per part, written in eighth notes.
# Each part shares its first bars and only the cadence changes.
JIG_A = ["D5:2 A4:1 F4:2 A4:1", "G4:2 C5:1 E5:2 C5:1", "D5:2 F5:1 E5:1 D5:1 C5:1", "A4:1 G4:1 F4:1 E4:3",
         "F4:1 A4:1 C5:1 F5:2 E5:1", "G5:2 E5:1 C5:2 E5:1"]
JIG_B = ["A5:2 F5:1 C5:2 F5:1", "G5:2 D5:1 B4:2 D5:1", "E5:1 D5:1 C5:1 A4:2 C5:1", "D5:1 E5:1 F5:1 A5:2 G5:1",
         "F5:2 C5:1 A4:2 C5:1", "E5:1 G5:1 E5:1 C5:2 G4:1", "B4:1 D5:1 G5:1 F5:1 E5:1 D5:1"]
JIG = (JIG_A + ["D5:1 B4:1 G4:1 B4:1 C5:1 D5:1", "E5:2 C5:1 A4:3"]
       + JIG_A + ["D5:1 G5:1 F5:1 E5:1 D5:1 B4:1", "A4:1 C5:1 E5:1 D5:3"]
       + JIG_B + ["C5:2 D5:1 E5:3"]
       + JIG_B + ["C5:2 B4:1 A4:3"])


def track_guild(seed=11):
    # tavern jig in D dorian, 6/8 felt as two beats of three eighths
    tr = Track(bars=32, bpm=104, beats_per_bar=3, seed=seed)
    rng = tr.rng
    part_a = [("D3", "m"), ("C3", "M"), ("D3", "m"), ("A2", "m"), ("F3", "M"), ("C3", "M"), ("G2", "M")]
    part_b = [("F3", "M"), ("G2", "M"), ("A2", "m"), ("D3", "m"), ("F3", "M"), ("C3", "M"), ("G2", "M"), ("A2", "m")]
    prog = part_a + [("A2", "m")] + part_a + [("D3", "m")] + part_b + part_b
    chords = [chord(midi(r), q) for r, q in prog]
    scale = scale_notes(midi("D4") % 12, "dorian", 50, 88)
    for ci, ch in enumerate(chords):
        b0 = ci * 3
        in_b = ci >= 16
        tr.at(b0, pluck(freq(ch[0] - 12), 1.6, 0.7, 2.2, rng), 0.9)
        if in_b:
            # B part: boom-chick lute, bass on each dotted beat and strums between
            tr.at(b0 + 1.5, pluck(freq(ch[2] - 12), 1.2, 0.7, 2.5, rng), 0.7)
            for k in (1, 2, 4, 5):
                for j, n in enumerate((ch[1], ch[2], ch[0] + 12)):
                    tr.at(b0 + k * 0.5 + j * 0.012 / tr.beat, pluck(freq(n), 0.5, 0.85, 5.0, rng), 0.3 if k in (1, 4) else 0.22)
        else:
            # A part: broken chord in eighths, two shapes alternating
            if ci % 2 == 0:
                pattern = [ch[0], ch[1], ch[2], ch[0] + 12, ch[2], ch[1]]
            else:
                pattern = [ch[0], ch[2], ch[0] + 12, ch[1] + 12, ch[0] + 12, ch[2]]
            for k, n in enumerate(pattern):
                tr.at(b0 + k * 0.5, pluck(freq(n), 0.9, 0.8, 3.5, rng), 0.6 if k % 3 == 0 else 0.45)
        # frame drum, with a fill into each new part
        if ci >= 4:
            tr.at(b0, drum("bodhran", rng), 0.8)
            tr.at(b0 + 1.5, drum("bodhran", rng, 0.6), 0.6)
            tr.at(b0 + 2.5, drum("rim", rng), 0.5)
            if ci % 8 == 7:
                tr.at(b0 + 2.0, drum("bodhran", rng, 0.5), 0.5)
                tr.at(b0 + 2.5, drum("bodhran", rng, 0.7), 0.6)
            if in_b:
                for k in range(6):
                    tr.at(b0 + k * 0.5, drum("shaker", rng, 1.0 if k % 3 == 0 else 0.6), 0.7)
    for (b, d, n) in tune(JIG, 0.5, 3):
        dur = d * tr.beat
        part = int(b // 24)
        if part == 0:  # A: flute alone
            tr.at(b, flute(freq(n), dur + 0.05, rng), 0.9)
        elif part == 1:  # A again: fiddle
            tr.at(b, fiddle(freq(n), dur + 0.04, rng), 0.95)
        elif part == 2:  # B: fiddle, flute a third below
            tr.at(b, fiddle(freq(n), dur + 0.04, rng), 0.9)
            tr.at(b, flute(freq(third_below(n, scale)), dur + 0.05, rng), 0.45)
        else:  # B again: flute, fiddle an octave down
            tr.at(b, flute(freq(n), dur + 0.05, rng), 0.85)
            tr.at(b, fiddle(freq(n - 12), dur + 0.04, rng), 0.5)
    return normalize(tr.finish(0.22, 1.4), 0.8)


def track_menu(seed=3):
    tr = Track(bars=16, bpm=66, beats_per_bar=4, seed=seed)
    rng = tr.rng
    prog = [("A2", "m"), ("F2", "M"), ("C3", "M"), ("G2", "M"), ("A2", "m"), ("D3", "m"), ("E3", "M"), ("E3", "sus")] * 2
    chords = [chord(midi(r), q) for r, q in prog]
    scale = scale_notes(midi("A3") % 12, "aeolian", 50, 88)
    for ci, ch in enumerate(chords):
        b0 = ci * 4
        tr.at(b0, pad(freq(ch[0]), 4 * tr.beat + 0.6, rng, harm=5), 1.0)
        tr.at(b0, pad(freq(ch[1] + 12), 4 * tr.beat + 0.6, rng, harm=4), 0.7)
        arp = [ch[0], ch[1], ch[2], ch[1] + 12, ch[2] + 12, ch[1] + 12, ch[2], ch[1]]
        for k, n in enumerate(arp):
            tr.at(b0 + k * 0.5, pluck(freq(n), 1.8, 0.75, 1.6, rng), 0.35)
    mel = melody(rng, chords, scale, 4, [1.0, 1.0, 2.0, 1.5, 0.5], midi("E5"), span=(64, 84))
    for (b, d, n) in mel:
        if b >= 8:
            tr.at(b, flute(freq(n), d * tr.beat + 0.1, rng, vib=4.8), 0.8)
    for b in range(0, 64, 16):
        tr.at(b, bell(freq(midi("A5")), 3.0, 0.9), 0.25)
    return normalize(tr.finish(0.35, 2.2), 0.75)


# Battle in E minor, 32 bars of 4/4 in four sections: ostinato with a horn
# call, the theme, a heroic bridge, the theme again. Every section ends on
# B major so it pulls back into E minor (and the loop seam does the same).
BATTLE_THEME_PROG = [("E3", "m"), ("C3", "M"), ("D3", "M"), ("E3", "m"), ("E3", "m"), ("C3", "M"), ("D3", "M"), ("B2", "M")]
BATTLE_PROG = ([("E3", "m"), ("E3", "m"), ("C3", "M"), ("D3", "M"), ("E3", "m"), ("E3", "m"), ("C3", "M"), ("B2", "M")]
               + BATTLE_THEME_PROG
               + [("C3", "M"), ("D3", "M"), ("G3", "M"), ("E3", "m"), ("C3", "M"), ("D3", "M"), ("B2", "M"), ("B2", "M")]
               + BATTLE_THEME_PROG)
BATTLE_HORN_CALL = ["E4:3 B3:1", "E4:1 G4:1 B4:2", "C5:2 B4:1 G4:1", "A4:4",
                    "E4:3 B3:1", "E4:1 G4:1 B4:2", "C5:2 G4:1 E4:1", "D#4:1 F#4:1 A4:2"]
BATTLE_THEME = ["B4:1 E5:1.5 F#5:0.5 G5:1", "E5:1.5 D5:0.5 C5:1 B4:1", "A4:1 D5:1.5 E5:0.5 F#5:1", "G5:1.5 F#5:0.5 E5:2",
                "B4:1 E5:1.5 F#5:0.5 G5:1", "E5:1.5 G5:0.5 C6:1 B5:1", "A5:1.5 F#5:0.5 D5:1 E5:1", "F#5:1.5 E5:0.5 D#5:2"]
BATTLE_BRIDGE = ["E4:2 G4:1.5 C5:0.5", "D5:2 A4:1 F#4:1", "G4:1.5 B4:0.5 D5:2", "E5:2 D5:1 B4:1",
                 "C5:1.5 B4:0.5 C5:1 E5:1", "D5:1.5 A4:0.5 D5:1 F#5:1", "D#5:2 B4:1 D#5:1", "F#5:4"]


def track_combat(seed=21, layer=False):
    tr = Track(bars=32, bpm=120, beats_per_bar=4, seed=seed)
    rng = tr.rng
    chords = [chord(midi(r), q) for r, q in BATTLE_PROG]
    if layer:
        # danger layer: driving percussion and a high string tremolo on the chord
        for ci, ch in enumerate(chords):
            b0 = ci * 4
            for k in range(16):
                tr.at(b0 + k * 0.25, drum("shaker", rng, 1.0 if k % 4 == 0 else 0.6), 1.0)
            for k in (0.75, 1.75, 2.75, 3.25, 3.75):
                tr.at(b0 + k, drum("rim", rng), 0.8)
            for k in range(16):
                n = (ch[2] if k % 2 == 0 else ch[1]) + 12
                tr.at(b0 + k * 0.25, fiddle(freq(n), 0.13, rng, vib=0, harm=6), 0.2)
            if ci % 4 == 3:
                tr.at(b0 + 3, drum("cymbal", rng), 1.0)
        return normalize(tr.finish(0.18, 1.2), 0.7)
    for ci, ch in enumerate(chords):
        b0 = ci * 4
        sec = ci // 8  # 0 ostinato, 1 theme, 2 bridge, 3 theme again
        root, third = ch[0], ch[1] - ch[0]
        # low strings: galloping bass, broad half notes under the bridge
        if sec == 2:
            for k in (0, 2):
                tr.at(b0 + k, fiddle(freq(root - 12), 1.9 * tr.beat, rng, vib=0, harm=8), 0.55)
        else:
            for beat in range(4):
                n = root - 12 + (7 if beat == 3 else 0)
                for off, d, g in ((0, 0.45, 0.55), (0.5, 0.22, 0.38), (0.75, 0.22, 0.42)):
                    tr.at(b0 + beat + off, fiddle(freq(n), d * tr.beat, rng, vib=0, harm=8), g)
        # mid strings: arpeggio ostinato, two shapes alternating
        shape = [0, 7, 12, 7, third, 7, 12, 7] if ci % 2 == 0 else [0, 7, third, 7, 12, 7, third + 12, 7]
        for k, iv in enumerate(shape):
            tr.at(b0 + k * 0.5, fiddle(freq(root + iv), 0.42 * tr.beat, rng, vib=0, harm=6), 0.3 if k % 2 else 0.38)
        tr.at(b0, pad(freq(root), 4 * tr.beat + 0.3, rng, harm=6, attack=0.3), 0.7)
        if sec >= 2:
            tr.at(b0, choir(freq(root), 4 * tr.beat + 0.5, rng), 0.9)
            tr.at(b0, choir(freq(ch[2]), 4 * tr.beat + 0.5, rng), 0.7)
        # war drums
        tr.at(b0, drum("taiko", rng), 1.0)
        if sec == 2:
            tr.at(b0 + 2.5, drum("taiko", rng, 0.6), 0.6)
        else:
            tr.at(b0 + 1.5, drum("tom", rng), 0.6)
            tr.at(b0 + 2, drum("taiko", rng, 0.7), 0.8)
            tr.at(b0 + 3.5, drum("tom", rng, 0.8), 0.5)
        if sec in (1, 3):
            tr.at(b0 + 1, drum("rim", rng), 0.6)
            tr.at(b0 + 3, drum("rim", rng), 0.6)
        if sec == 3:
            tr.at(b0 + 2.5, drum("taiko", rng, 0.6), 0.6)
        if ci % 8 == 0:
            tr.at(b0, drum("cymbal", rng), 0.9)
        if ci in (22, 23):  # snare-like build out of the bridge
            for k in range(16):
                tr.at(b0 + k * 0.25, drum("rim", rng, 0.3 + 0.7 * ((ci - 22) * 16 + k) / 32), 0.6)
        elif ci % 8 == 7:  # tom fill into the next section
            for k in range(4):
                tr.at(b0 + 3 + k * 0.25, drum("tom", rng, 0.6 + 0.12 * k), 0.6)
    for (b, d, n) in tune(BATTLE_HORN_CALL, 1, 4):
        tr.at(b, horn(freq(n), d * tr.beat + 0.05, rng), 0.7)
    for (b, d, n) in tune(BATTLE_THEME, 1, 4):
        for start in (32, 96):
            # two slightly detuned fiddles read as a string section
            tr.at(start + b, fiddle(freq(n), d * tr.beat, rng, vib=6.5), 0.4)
            tr.at(start + b, fiddle(freq(n) * 1.003, d * tr.beat, rng, vib=6.0), 0.4)
        tr.at(96 + b, horn(freq(n - 12), d * tr.beat + 0.05, rng), 0.55)
    for (b, d, n) in tune(BATTLE_BRIDGE, 1, 4):
        tr.at(64 + b, horn(freq(n - 12), d * tr.beat + 0.05, rng), 0.7)
        tr.at(64 + b, fiddle(freq(n), d * tr.beat, rng, vib=5.5), 0.35)
    return normalize(tr.finish(0.18, 1.2), 0.82)


# Every biome has its own battle track, and all of them carry the battle
# theme's head as their motif: scale degrees 5 1 2 3 | 1 7 6 5, in the rhythm
# quarter, dotted quarter, eighth, quarter. Each biome rewrites it in its own
# key, mode and metre and gives it to its own instruments. Track layout: four
# 8-bar sections (call, theme, bridge, theme again), each ending on the
# dominant so it pulls into the next and across the loop seam.

# The Unremembered: the motif half forgotten. C phrygian, choir and bells; the
# motif comes back on a music-box bell, then on strings that lose notes and
# drift out of tune, with the bell echoing whatever is left.
HUSH_PROG = [("C3", "m"), ("C3", "m"), ("Db3", "M"), ("C3", "m"), ("Ab2", "M"), ("G2", "dim"), ("Db3", "M"), ("C3", "5")] * 3
HUSH_THEME = ["G4:1 C5:1.5 Db5:0.5 Eb5:1", "C5:1.5 Bb4:0.5 Ab4:1 G4:1", "Ab4:1 Db5:1.5 Eb5:0.5 F5:1", "Eb5:4",
              "G4:1 C5:1.5 Db5:0.5 Eb5:1", "Db5:1.5 Bb4:0.5 G4:2", "Ab4:2 F4:2", "G4:4"]


def track_hush(seed=31, layer=False):
    tr = Track(bars=24, bpm=92, beats_per_bar=4, seed=seed)
    rng = tr.rng
    chords = [chord(midi(r), q) for r, q in HUSH_PROG]
    if layer:
        def extra(ci, ch, b0):
            # a heartbeat, and a cymbal drawn backwards into every fourth bar
            for k in (0, 2):
                tr.at(b0 + k, drum("bodhran", rng), 0.9)
                tr.at(b0 + k + 0.35, drum("bodhran", rng, 0.6), 0.6)
            if ci % 4 == 3:
                rev = drum("cymbal", rng)[::-1]
                tr.at(b0 + 4 - len(rev) / SR / tr.beat, rev, 1.4)
        cluster = lambda f, d: fiddle(f, d, rng, vib=0, harm=6) + 0.6 * fiddle(f * 2 ** (1 / 12), d, rng, vib=0, harm=6)  # noqa: E731
        return danger_layer(tr, chords, 8, "rim", (), cluster, trem_gain=0.16, accent=2, cymbal_every=8, extra=extra)
    for ci, ch in enumerate(chords):
        b0 = ci * 4
        tr.at(b0, choir(freq(ch[0]), 4 * tr.beat + 0.8, rng), 1.0)
        tr.at(b0, choir(freq(ch[2]), 4 * tr.beat + 0.8, rng), 0.7)
        tr.at(b0, drum("taiko", rng, 0.8), 0.8)
        tr.at(b0 + 2.5, drum("tom", rng, 0.6), 0.5)
        tr.at(b0 + 1, bell(freq(ch[1] + 24), 2.5, 1.4), 0.2)
        tr.at(b0 + 3, bell(freq(ch[0] + 25), 2.5, 1.6), 0.12)
        for k in range(4):
            tr.at(b0 + k, pluck(freq(ch[0] - 12), 1.2, 0.5, 3.0, rng), 0.5)
        if ci >= 8:
            tr.at(b0, pad(freq(ch[0] - 12), 4 * tr.beat + 0.5, rng, harm=5, attack=0.8), 0.6)
    lay(tr, HUSH_THEME, 32, lambda f, d: bell(f * 2, 2.4, 1.5), 0.4)
    mem = np.random.default_rng(seed + 7)
    for (b, d, n) in tune(HUSH_THEME, 1, 4):
        forgotten = b >= 4 and mem.random() < 0.3
        drift = 2 ** (mem.uniform(-0.35, 0.35) / 12)
        if not forgotten:
            tr.at(64 + b, fiddle(freq(n - 12) * drift, d * tr.beat, rng, vib=4.0), 0.6)
            tr.at(64 + b + 0.5, bell(freq(n) * drift, 2.0, 1.8), 0.18)
    return normalize(tr.finish(0.45, 2.6), 0.78)


# Coast of the Drowned Bells: a sea shanty in D minor, 6/8 written in eighths.
# A foghorn horn states the motif in long notes; a sunken bell tolls slightly
# out of tune over the surf.
COAST_THEME_PROG = [("D3", "m"), ("Bb2", "M"), ("C3", "M"), ("F3", "M"), ("D3", "m"), ("D3", "m"), ("G2", "m"), ("A2", "M")]
COAST_PROG = ([("D3", "m"), ("D3", "m"), ("Bb2", "M"), ("C3", "M"), ("D3", "m"), ("D3", "m"), ("G2", "m"), ("A2", "M")]
              + COAST_THEME_PROG
              + [("F3", "M"), ("C3", "M"), ("D3", "m"), ("Bb2", "M"), ("F3", "M"), ("C3", "M"), ("G2", "m"), ("A2", "M")]
              + COAST_THEME_PROG)
COAST_CALL = ["A3:3 D4:3", "E4:3 F4:3", "D4:6", "r:6", "A3:3 D4:3", "E4:3 F4:3", "Bb4:2 A4:1 G4:2 F4:1", "E4:6"]
COAST_THEME = ["A4:1 D5:2 E5:1 F5:2", "D5:2 C5:1 Bb4:2 A4:1", "G4:1 C5:2 D5:1 E5:2", "F5:3 A4:2 G4:1",
               "A4:1 D5:2 E5:1 F5:2", "A5:2 G5:1 F5:2 E5:1", "D5:2 G5:1 F5:1 E5:1 D5:1", "C#5:3 E5:3"]
COAST_BRIDGE = ["C5:3 A4:2 C5:1", "E5:3 G5:2 E5:1", "F5:2 E5:1 D5:2 A4:1", "Bb4:3 D5:3",
                "C5:2 F5:1 A5:2 F5:1", "G5:2 E5:1 C5:2 E5:1", "D5:2 Bb4:1 G4:2 Bb4:1", "A4:3 C#5:2 E5:1"]


def track_coast(seed=51, layer=False):
    tr = Track(bars=32, bpm=138, beats_per_bar=3, seed=seed)
    rng = tr.rng
    chords = [chord(midi(r), q) for r, q in COAST_PROG]
    if layer:
        def extra(ci, ch, b0):
            if ci % 2 == 1:  # a bodhran roll up to the next downbeat
                for k in range(4):
                    tr.at(b0 + 2 + k * 0.25, drum("bodhran", rng, 0.5 + 0.15 * k), 0.6)
        return danger_layer(tr, chords, 12, "shaker", (1.5, 2.5), lambda f, d: fiddle(f, d, rng, vib=0, harm=6), accent=3, extra=extra)
    for ci, ch in enumerate(chords):
        b0 = ci * 3
        sec = ci // 8  # 0 foghorn call, 1 theme, 2 bridge, 3 theme again
        root, third = ch[0], ch[1] - ch[0]
        # low strings on the two dotted beats; the lute rolls up and back like the swell
        tr.at(b0, fiddle(freq(root - 12), 1.4 * tr.beat, rng, vib=0, harm=8), 0.55)
        tr.at(b0 + 1.5, fiddle(freq(root - 5), 1.4 * tr.beat, rng, vib=0, harm=8), 0.45)
        for k, iv in enumerate([0, 7, 12, third + 12, 12, 7]):
            tr.at(b0 + k * 0.5, pluck(freq(root + iv), 0.9, 0.8, 3.0, rng), 0.5 if k % 3 == 0 else 0.38)
        tr.at(b0, pad(freq(root), 3 * tr.beat + 0.3, rng, harm=5, attack=0.4), 0.6)
        if sec >= 2:
            tr.at(b0, choir(freq(root), 3 * tr.beat + 0.5, rng), 0.9)
            tr.at(b0, choir(freq(ch[2]), 3 * tr.beat + 0.5, rng), 0.6)
        # stomp, stomp-and-clap
        tr.at(b0, drum("bodhran", rng), 0.9)
        tr.at(b0 + 1.5, drum("bodhran", rng, 0.8), 0.7)
        tr.at(b0 + 1.5, drum("rim", rng), 0.55)
        if sec >= 1:
            tr.at(b0, drum("taiko", rng, 0.8), 0.7)
            tr.at(b0 + 2.5, drum("bodhran", rng, 0.5), 0.45)
        if sec == 3:
            tr.at(b0 + 1.5, drum("taiko", rng, 0.6), 0.5)
        if ci % 8 == 0:
            tr.at(b0, drum("cymbal", rng), 0.9)
        elif ci % 8 == 7:
            for k in range(3):
                tr.at(b0 + 1.5 + k * 0.5, drum("tom", rng, 0.6 + 0.15 * k), 0.6)
        # the sea, and the drowned bell
        if ci % 2 == 0:
            tr.at(b0, surf(6 * tr.beat, rng), 0.5)
        if ci % 4 == 0:
            tr.at(b0, bell(freq(midi("D3")), 4.0, 0.5), 0.35)
            tr.at(b0, bell(freq(midi("D3")) * 1.013, 4.0, 0.55), 0.2)
    lay(tr, COAST_CALL, 0, lambda f, d: horn(f, d + 0.05, rng), 0.7, unit=0.5)
    for start in (24, 72):
        lay(tr, COAST_THEME, start, lambda f, d: fiddle(f, d, rng, vib=6.5), 0.4, unit=0.5)
        lay(tr, COAST_THEME, start, lambda f, d: fiddle(f * 1.003, d, rng, vib=6.0), 0.4, unit=0.5)
    lay(tr, COAST_THEME, 72, lambda f, d: horn(f, d + 0.05, rng), 0.5, shift=-12, unit=0.5)
    lay(tr, COAST_BRIDGE, 48, lambda f, d: flute(f, d + 0.05, rng), 0.75, unit=0.5)
    lay(tr, COAST_BRIDGE, 48, lambda f, d: fiddle(f, d, rng, vib=5.5), 0.35, shift=-12, unit=0.5)
    return normalize(tr.finish(0.25, 1.8), 0.82)


# Lampwick Stilts: A dorian over hand drums in 3-3-2. The marimba ostinato
# climbs root, fifth, octave, ninth, tenth - the motif's own steps - under a
# wooden flute; a misty pad hangs over the canals.
JUNGLE_THEME_PROG = [("A2", "m"), ("D3", "M"), ("A2", "m"), ("G2", "M"), ("A2", "m"), ("D3", "M"), ("C3", "M"), ("E3", "m")]
JUNGLE_PROG = ([("A2", "m"), ("D3", "M"), ("A2", "m"), ("D3", "M"), ("A2", "m"), ("D3", "M"), ("C3", "M"), ("E3", "m")]
               + JUNGLE_THEME_PROG
               + [("F2", "M"), ("G2", "M"), ("E3", "m"), ("A2", "m"), ("F2", "M"), ("G2", "M"), ("E3", "M"), ("E3", "M")]
               + JUNGLE_THEME_PROG)
JUNGLE_CALL = ["r:4", "r:4", "E4:1 A4:3", "r:2 B4:0.5 C5:1.5", "A4:4", "r:4", "E4:1 A4:1.5 B4:0.5 C5:1", "B4:3 r:1"]
JUNGLE_THEME = ["E4:1 A4:1.5 B4:0.5 C5:1", "A4:1.5 G4:0.5 F#4:1 E4:1", "E4:1 A4:1.5 B4:0.5 C5:1", "D5:1.5 C5:0.5 B4:1 G4:1",
                "E4:0.5 E4:0.5 A4:1.5 B4:0.5 C5:1", "D5:1 E5:1.5 D5:0.5 A4:1", "G4:1 C5:1 E5:1.5 D5:0.5", "B4:2.5 r:1.5"]
JUNGLE_BRIDGE = ["C5:1.5 A4:0.5 C5:1 F5:1", "D5:1.5 B4:0.5 D5:1 G5:1", "E5:2 D5:1 B4:1", "C5:2 A4:2",
                 "A4:1 C5:1 F5:1.5 E5:0.5", "D5:1 B4:1 G4:1 D5:1", "E5:1 B4:1 G#4:1 B4:1", "B4:2 G#4:1 r:1"]


def track_jungle(seed=61, layer=False):
    tr = Track(bars=32, bpm=116, beats_per_bar=4, seed=seed)
    rng = tr.rng
    chords = [chord(midi(r), q) for r, q in JUNGLE_PROG]
    if layer:
        def extra(ci, ch, b0):
            for k in (0.25, 1.25, 2.25, 3.25):
                tr.at(b0 + k, drum("hand", rng, 0.7), 0.7)
        return danger_layer(tr, chords, 16, "shaker", (0.75, 1.75, 2.75, 3.75), lambda f, d: mallet(f, d * 2.0),
                            trem_gain=0.15, extra=extra)
    for ci, ch in enumerate(chords):
        b0 = ci * 4
        sec = ci // 8  # 0 flute call, 1 theme, 2 bridge, 3 theme again
        root, third = ch[0], ch[1] - ch[0]
        for k, iv in enumerate([0, 7, 12, 14, third + 12, 12, 7, 14]):
            tr.at(b0 + k * 0.5, mallet(freq(root + 12 + iv), 0.8), 0.5 if k % 3 == 0 else 0.36)
        for off, iv, d in ((0, 0, 1.4), (1.5, 0, 0.4), (2, 7, 0.9), (3.5, 12, 0.4)):
            tr.at(b0 + off, pluck(freq(root + iv), d * tr.beat + 0.2, 0.5, 3.0, rng), 0.75)
        tr.at(b0, pad(freq(root + 12), 4 * tr.beat + 0.6, rng, harm=4, attack=1.0), 0.5)
        tr.at(b0, pad(freq(ch[2] + 12), 4 * tr.beat + 0.6, rng, harm=3, attack=1.2), 0.35)
        # hand drums in 3-3-2, ghost slaps between, a stick on two and four
        tr.at(b0, drum("doum", rng), 0.8)
        tr.at(b0 + 1.5, drum("hand", rng), 0.8)
        tr.at(b0 + 3, drum("hand", rng, 0.9), 0.75)
        for k in (0.75, 2.25, 3.5):
            tr.at(b0 + k, drum("hand", rng, 0.5), 0.45)
        tr.at(b0 + 1, drum("tek", rng), 0.5)
        tr.at(b0 + 3, drum("tek", rng), 0.5)
        sub = 0.25 if sec in (1, 3) else 0.5
        for k in range(int(4 / sub)):
            tr.at(b0 + k * sub, drum("shaker", rng, 1.0 if k % 2 == 0 else 0.6), 0.7)
        if ci % 2 == 1:
            tr.at(b0 + 2.5, drum("block", rng), 0.6)
        if sec == 3 or ci % 8 == 0:
            tr.at(b0, drum("taiko", rng, 0.8), 0.7)
        if ci % 8 == 0:
            tr.at(b0, drum("cymbal", rng), 0.8)
        elif ci % 8 == 7:
            for k in range(4):
                tr.at(b0 + 3 + k * 0.25, drum("hand", rng, 0.6 + 0.12 * k), 0.7)
        if sec in (0, 2) and ci % 4 == 1:  # a bird somewhere above the mist
            chirp = sweep(2600, 3700, 0.07) * fx_env(int(0.07 * SR), 0.003, 30)
            tr.at(b0 + 1.25, chirp, 0.1)
            tr.at(b0 + 1.45, chirp, 0.07)
    lay(tr, JUNGLE_CALL, 0, lambda f, d: flute(f, d + 0.05, rng, breath=0.12), 0.85)
    for start in (32, 96):
        lay(tr, JUNGLE_THEME, start, lambda f, d: flute(f, d + 0.05, rng), 0.8)
        lay(tr, JUNGLE_THEME, start, lambda f, d: mallet(f, d + 0.4), 0.35, shift=12)
    lay(tr, JUNGLE_THEME, 96, lambda f, d: horn(f, d + 0.05, rng), 0.4, shift=-12)
    lay(tr, JUNGLE_BRIDGE, 64, lambda f, d: mallet(f, d + 0.4), 0.6)
    lay(tr, JUNGLE_BRIDGE, 64, lambda f, d: horn(f, d + 0.05, rng), 0.45, shift=-12)
    return normalize(tr.finish(0.3, 1.9), 0.82)


# The Ember Wood: a battle waltz in G minor, 3/4. The motif stretches over
# four bars; a cello calls it, harp keeps the waltz turning, shrine bells and
# crackling embers sit between the beats.
AUTUMN_THEME_PROG = [("G2", "m"), ("G2", "m"), ("Eb3", "M"), ("Bb2", "M"), ("F3", "M"), ("C3", "m"), ("D3", "M"), ("D3", "M")]
AUTUMN_PROG = ([("G2", "m"), ("G2", "m"), ("Eb3", "M"), ("Bb2", "M"), ("G2", "m"), ("G2", "m"), ("C3", "m"), ("D3", "M")]
               + AUTUMN_THEME_PROG
               + [("Eb3", "M"), ("F3", "M"), ("Bb2", "M"), ("G2", "m"), ("Eb3", "M"), ("F3", "M"), ("D3", "M"), ("D3", "M")]
               + AUTUMN_THEME_PROG)
AUTUMN_CALL = ["D4:1 G4:1.5 A4:0.5", "Bb4:3", "G4:1.5 F4:0.5 Eb4:1", "D4:3", "Bb3:2 A3:1", "G3:3", "C4:1.5 Bb3:0.5 A3:1", "D4:3"]
AUTUMN_THEME = ["D5:1 G5:1.5 A5:0.5", "Bb5:3", "G5:1.5 F5:0.5 Eb5:1", "D5:3",
                "C5:1 F5:1.5 G5:0.5", "G5:2 Eb5:1", "A5:1.5 G5:0.5 F#5:1", "D5:3"]
AUTUMN_BRIDGE = ["Bb4:1 Eb5:1.5 F5:0.5", "A5:2 F5:1", "D5:1.5 F5:0.5 Bb5:1", "G5:2 D5:1",
                 "Eb5:1 G5:1.5 Bb5:0.5", "C6:2 A5:1", "A5:1.5 F#5:0.5 D5:1", "F#5:2 A5:1"]


def track_autumn(seed=71, layer=False):
    tr = Track(bars=32, bpm=144, beats_per_bar=3, seed=seed)
    rng = tr.rng
    chords = [chord(midi(r), q) for r, q in AUTUMN_PROG]
    if layer:
        def extra(ci, ch, b0):
            tr.at(b0 + 2.75, drum("block", rng), 0.6)
            tr.at(b0, crackle(3 * tr.beat, rng, 30.0), 0.12)
        return danger_layer(tr, chords, 12, "shaker", (1.5, 2.5), lambda f, d: fiddle(f, d, rng, vib=0, harm=6), extra=extra)
    for ci, ch in enumerate(chords):
        b0 = ci * 3
        sec = ci // 8  # 0 cello call, 1 theme, 2 bridge, 3 theme again
        root, third = ch[0], ch[1] - ch[0]
        shape = [0, 7, 12, third + 12, 19, 24] if sec == 2 else [0, 7, 12, third + 12, 12, 7]
        for k, iv in enumerate(shape):
            tr.at(b0 + k * 0.5, pluck(freq(root + 12 + iv), 1.2, 0.9, 2.2, rng), 0.42 if k % 2 == 0 else 0.32)
        # waltz strings: the deep note on one, the chord on two and three
        tr.at(b0, fiddle(freq(root), 0.95 * tr.beat, rng, vib=0, harm=8), 0.6)
        for k in (1, 2):
            for n in (ch[1] + 12, ch[2] + 12):
                tr.at(b0 + k, fiddle(freq(n), 0.45 * tr.beat, rng, vib=0, harm=6), 0.2)
        tr.at(b0, pad(freq(root + 12), 3 * tr.beat + 0.4, rng, harm=5, attack=0.4), 0.5)
        if sec >= 2:
            tr.at(b0, choir(freq(root + 12), 3 * tr.beat + 0.5, rng), 0.9)
            tr.at(b0, choir(freq(ch[2] + 12), 3 * tr.beat + 0.5, rng), 0.6)
        tr.at(b0, drum("taiko" if sec >= 1 else "bodhran", rng, 0.9), 0.85)
        tr.at(b0 + 1, drum("bodhran", rng, 0.5), 0.45)
        tr.at(b0 + 2, drum("bodhran", rng, 0.5), 0.45)
        if sec in (1, 3):
            tr.at(b0 + 2.5, drum("rim", rng), 0.5)
        if sec == 3:
            tr.at(b0 + 1.5, drum("block", rng), 0.5)
        if ci % 8 == 0:
            tr.at(b0, drum("cymbal", rng), 0.8)
        elif ci % 8 == 7:
            for k in range(3):
                tr.at(b0 + 2 + k / 3, drum("tom", rng, 0.6 + 0.15 * k), 0.6)
        # shrine bells and embers
        if ci % 2 == 0:
            tr.at(b0, bell(freq(ch[2] + 36), 2.5, 1.3), 0.16)
        if ci % 4 == 2:
            tr.at(b0 + 1.5, bell(freq(root + 36), 2.5, 1.5), 0.1)
        if ci % 4 == 0:
            tr.at(b0, crackle(12 * tr.beat, rng), 0.15)
    lay(tr, AUTUMN_CALL, 0, lambda f, d: fiddle(f, d, rng, vib=5.0), 0.7)
    for start in (24, 72):
        lay(tr, AUTUMN_THEME, start, lambda f, d: fiddle(f, d, rng, vib=6.5), 0.4)
        lay(tr, AUTUMN_THEME, start, lambda f, d: fiddle(f * 1.003, d, rng, vib=6.0), 0.4)
    lay(tr, AUTUMN_THEME, 72, lambda f, d: flute(f, d + 0.05, rng), 0.45)
    lay(tr, AUTUMN_THEME, 72, lambda f, d: horn(f, d + 0.05, rng), 0.45, shift=-12)
    lay(tr, AUTUMN_BRIDGE, 48, lambda f, d: horn(f, d + 0.05, rng), 0.65, shift=-12)
    lay(tr, AUTUMN_BRIDGE, 48, lambda f, d: fiddle(f, d, rng, vib=5.5), 0.35)
    return normalize(tr.finish(0.3, 2.1), 0.82)


# The Sunken Dunes: E phrygian dominant over an open E drone. The motif's
# second and third steps become F and G#; a reed sings it over an oud winding
# through the mode and a goblet drum in maqsum; glass chimes from the ruins.
DESERT_THEME_PROG = [("E3", "M"), ("A2", "m"), ("D3", "m"), ("E3", "M"), ("E3", "M"), ("F3", "M"), ("D3", "m"), ("E3", "M")]
DESERT_PROG = ([("E3", "M"), ("E3", "M"), ("E3", "M"), ("F3", "M"), ("E3", "M"), ("E3", "M"), ("D3", "m"), ("E3", "M")]
               + DESERT_THEME_PROG
               + [("A2", "m"), ("D3", "m"), ("G2", "M"), ("C3", "M"), ("F3", "M"), ("D3", "m"), ("E3", "M"), ("E3", "M")]
               + DESERT_THEME_PROG)
DESERT_CALL = ["r:4", "r:4", "B3:2 E4:2", "F4:2 G#4:1 F4:0.5 E4:0.5", "E4:4", "r:4", "D4:1 F4:1 E4:1 D4:1",
               "C4:1 B3:1 C4:0.5 B3:0.5 G#3:1"]
DESERT_THEME = ["B4:1 E5:1.5 F5:0.5 G#5:1", "E5:1.5 D5:0.5 C5:1 B4:1", "A4:1 D5:1.5 E5:0.5 F5:1", "G#5:1.5 F5:0.5 E5:2",
                "B4:1 E5:1.5 F5:0.5 G#5:1", "A5:1.5 G#5:0.5 F5:1 E5:1", "D5:1 F5:0.5 E5:0.5 D5:1 C5:1", "B4:2 C5:0.5 B4:0.5 G#4:1"]
DESERT_BRIDGE = ["C5:2 B4:1 A4:1", "D5:2 F5:1 E5:1", "D5:1.5 B4:0.5 G4:2", "C5:1 E5:1 G5:2",
                 "A5:2 C6:1 A5:1", "F5:1.5 E5:0.5 D5:2", "E5:1 F5:1 G#5:1 B5:1", "G#5:2 F5:1 E5:1"]


def track_desert(seed=81, layer=False):
    tr = Track(bars=32, bpm=100, beats_per_bar=4, seed=seed)
    rng = tr.rng
    chords = [chord(midi(r), q) for r, q in DESERT_PROG]
    scale = scale_notes(midi("E3") % 12, "phrygdom", 36, 76)
    if layer:
        def extra(ci, ch, b0):
            tr.at(b0, drum("doum", rng), 0.8)
            tr.at(b0 + 2.5, drum("doum", rng, 0.7), 0.6)
            tr.at(b0 + 3.5, bell(freq(midi("E7")), 0.5, 6.0), 0.12)
        return danger_layer(tr, chords, 16, "tek", (0.75, 1.75, 2.75, 3.25), lambda f, d: fiddle(f, d, rng, vib=0, harm=6), extra=extra)
    for ci, ch in enumerate(chords):
        b0 = ci * 4
        sec = ci // 8  # 0 reed call, 1 theme, 2 bridge, 3 theme again
        root = ch[0]
        # the drone holds E and B open under every chord
        tr.at(b0, pad(freq(midi("E2")), 4 * tr.beat + 0.6, rng, harm=7, attack=0.5), 0.7)
        tr.at(b0, pad(freq(midi("B2")), 4 * tr.beat + 0.6, rng, harm=5, attack=0.5), 0.4)
        if root % 12 != 4:
            tr.at(b0, pad(freq(root), 4 * tr.beat + 0.6, rng, harm=5, attack=0.5), 0.4)
        # oud: winds through the mode from the chord root; arpeggios under the bridge
        if sec == 2:
            run = [root + iv for iv in (0, 7, 12, 7, ch[1] - root + 12, 7, 12, 7)]
        else:
            i = min(range(len(scale)), key=lambda j: abs(scale[j] - root))
            run = [scale[i + s] for s in (0, 1, 2, 1, 0, -1, -2, -1)]
        for k, n in enumerate(run):
            tr.at(b0 + k * 0.5, pluck(freq(n), 0.8, 0.95, 3.5, rng), 0.45 if k % 2 == 0 else 0.35)
        # goblet drum in maqsum: DUM tek . tek DUM . tek .
        tr.at(b0, drum("doum", rng), 0.9)
        tr.at(b0 + 2, drum("doum", rng, 0.85), 0.75)
        for k in (0.5, 1.5, 3):
            tr.at(b0 + k, drum("tek", rng), 0.7)
        tr.at(b0 + 3.5, drum("tek", rng, 0.6), 0.35)
        if sec in (1, 3):  # riq jingles
            for k in range(8):
                tr.at(b0 + k * 0.5, drum("shaker", rng, 1.0 if k % 2 == 0 else 0.6), 0.6)
            tr.at(b0 + 1, bell(freq(midi("E7")), 0.5, 6.0), 0.08)
            tr.at(b0 + 3, bell(freq(midi("E7")), 0.5, 6.0), 0.08)
        if ci % 8 == 0 or (sec == 3 and ci % 2 == 0):
            tr.at(b0, drum("taiko", rng, 0.8), 0.7)
        if ci % 8 == 0:
            tr.at(b0, drum("cymbal", rng), 0.8)
        elif ci % 8 == 7:
            for k in range(6):
                tr.at(b0 + 2.5 + k * 0.25, drum("tek", rng, 0.5 + 0.1 * k), 0.7)
        if sec == 2:
            tr.at(b0, choir(freq(root + 12), 4 * tr.beat + 0.5, rng), 0.8)
            tr.at(b0, choir(freq(ch[2] + 12), 4 * tr.beat + 0.5, rng), 0.55)
        # glass chimes from the ruins, and the wind over the dunes
        if sec in (1, 3) and ci % 2 == 1:
            tr.at(b0, bell(freq(ch[2] + 24), 2.0, 2.0), 0.15)
            tr.at(b0 + 0.25, bell(freq(ch[0] + 36), 1.5, 2.5), 0.08)
        if ci % 4 == 0:
            tr.at(b0, wind(16 * tr.beat, rng), 0.35)
    lay(tr, DESERT_CALL, 0, lambda f, d: reed(f, d + 0.04, rng), 0.8)
    for start in (32, 96):
        lay(tr, DESERT_THEME, start, lambda f, d: reed(f, d + 0.04, rng), 0.75)
    lay(tr, DESERT_THEME, 96, lambda f, d: fiddle(f, d, rng, vib=6.0), 0.4, shift=-12)
    lay(tr, DESERT_BRIDGE, 64, lambda f, d: reed(f, d + 0.04, rng), 0.6)
    lay(tr, DESERT_BRIDGE, 64, lambda f, d: fiddle(f, d, rng, vib=5.5), 0.3)
    return normalize(tr.finish(0.3, 2.3), 0.82)


def track_final(seed=41, layer=False):
    tr = Track(bars=16, bpm=112, beats_per_bar=4, seed=seed)
    rng = tr.rng
    prog = [("D3", "m"), ("Bb2", "M"), ("F3", "M"), ("C3", "M"), ("D3", "m"), ("G2", "m"), ("A2", "M"), ("A2", "sus")] * 2
    chords = [chord(midi(r), q) for r, q in prog]
    if not layer:
        for ci, ch in enumerate(chords):
            b0 = ci * 4
            tr.at(b0, choir(freq(ch[0]), 4 * tr.beat + 0.5, rng), 1.0)
            tr.at(b0, choir(freq(ch[1] + 12), 4 * tr.beat + 0.5, rng), 0.8)
            tr.at(b0, pad(freq(ch[0] - 12), 4 * tr.beat + 0.3, rng, harm=7, attack=0.2), 0.9)
            for k in range(8):
                tr.at(b0 + k * 0.5, fiddle(freq(ch[0] - 12 + (12 if k % 2 else 0)), 0.22, rng, vib=0, harm=8), 0.4)
            tr.at(b0, drum("taiko", rng), 1.0)
            tr.at(b0 + 1, drum("tom", rng), 0.5)
            tr.at(b0 + 2, drum("taiko", rng, 0.8), 0.8)
            tr.at(b0 + 2.5, drum("taiko", rng, 0.6), 0.6)
            tr.at(b0 + 3, drum("tom", rng), 0.6)
        scale = scale_notes(midi("D3") % 12, "harmonic", 52, 86)
        mel = melody(np.random.default_rng(seed + 2), chords, scale, 4, [1.0, 1.0, 0.5, 2.0], midi("A4"), span=(64, 81))
        for (b, d, n) in mel:
            tr.at(b, fiddle(freq(n), d * tr.beat, rng, vib=6.0), 0.7)
        return normalize(tr.finish(0.3, 2.0), 0.85)
    for ci, ch in enumerate(chords):
        b0 = ci * 4
        for k in range(8):
            tr.at(b0 + k * 0.5, drum("rim", rng, 0.9), 0.7)
        tr.at(b0, bell(freq(ch[0] + 24), 2.2, 1.0), 0.35)
        tr.at(b0 + 2, bell(freq(ch[2] + 24), 2.2, 1.0), 0.25)
        if ci % 2 == 1:
            tr.at(b0 + 3, drum("cymbal", rng), 1.0)
    return normalize(tr.finish(0.3, 2.0), 0.7)


MUSIC = {
    "guild": lambda: track_guild(),
    "menu": lambda: track_menu(),
    "combat": lambda: track_combat(),
    "combat_layer": lambda: track_combat(layer=True),
    "combat_coast": lambda: track_coast(),
    "combat_coast_layer": lambda: track_coast(layer=True),
    "combat_jungle": lambda: track_jungle(),
    "combat_jungle_layer": lambda: track_jungle(layer=True),
    "combat_autumn": lambda: track_autumn(),
    "combat_autumn_layer": lambda: track_autumn(layer=True),
    "combat_desert": lambda: track_desert(),
    "combat_desert_layer": lambda: track_desert(layer=True),
    "hush_battle": lambda: track_hush(),
    "hush_battle_layer": lambda: track_hush(layer=True),
    "final": lambda: track_final(),
    "final_layer": lambda: track_final(layer=True),
}


# ------------------------------------------------------------------ sound effects
def fx_env(n, attack=0.002, decay=10.0):
    t = np.arange(n) / SR
    e = np.exp(-t * decay)
    a = max(1, int(attack * SR))
    e[:a] *= np.linspace(0, 1, a)
    return e


def sweep(f0, f1, dur, shape="sine"):
    t = t_axis(dur)
    f = f0 * (f1 / f0) ** (t / dur)
    ph = 2 * np.pi * np.cumsum(f) / SR
    if shape == "square":
        return np.sign(np.sin(ph)) * 0.5
    if shape == "saw":
        return 2 * ((ph / (2 * np.pi)) % 1) - 1
    return np.sin(ph)


def mixn(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def delay(x, secs, gain=1.0):
    return np.concatenate([np.zeros(int(secs * SR)), x * gain])


VOWELS = {"a": (800, 1250), "o": (500, 900), "e": (420, 2100), "i": (320, 2600), "u": (350, 800)}


def syllable(f0, dur, vowel, rng, bend=0.0):
    """A voiced syllable: a glottal buzz shaped by two vowel formants."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = f0 * (1 + bend * t / dur) * (1 + 0.02 * np.sin(2 * np.pi * 6 * t))
    ph = np.cumsum(f) / SR
    buzz = 2 * (ph % 1) - 1
    f1, f2 = VOWELS[vowel]
    y = bandpass_fft(buzz, f1 * 0.8, f1 * 1.25) * 1.0 + bandpass_fft(buzz, f2 * 0.85, f2 * 1.15) * 0.5
    y += bandpass_fft(noise(n, rng), 2500, 6000) * 0.04
    return y * env_adsr(n, 0.015, 0.03, 0.8, 0.04)


def babble(rng, count, f0, vowels, bends, dur=0.09, gap=0.025):
    parts = []
    for k in range(count):
        parts.append(syllable(f0 * rng.uniform(0.94, 1.08), dur * rng.uniform(0.8, 1.2), vowels[k % len(vowels)], rng, bends[k % len(bends)]))
        parts.append(np.zeros(int(gap * SR)))
    return np.concatenate(parts)


def sfx_all(seed=5):
    rng = np.random.default_rng(seed)
    N = lambda d: noise(int(d * SR), rng)  # noqa: E731
    S = {}
    # --- UI
    S["ui_click"] = bandpass_fft(N(0.05), 1500, 6000) * fx_env(int(0.05 * SR), 0.001, 70) * 0.8 + sweep(1400, 900, 0.05) * fx_env(int(0.05 * SR), 0.001, 60) * 0.3
    S["ui_hover"] = sweep(2400, 2600, 0.03) * fx_env(int(0.03 * SR), 0.001, 90) * 0.25
    S["ui_select"] = mixn(pluck(freq(midi("E5")), 0.3, 0.8, 8, rng), delay(pluck(freq(midi("A5")), 0.35, 0.8, 7, rng), 0.06))
    S["page"] = bandpass_fft(N(0.28), 800, 5000) * np.sin(np.linspace(0, np.pi, int(0.28 * SR))) ** 2 * 0.7
    S["cloth"] = bandpass_fft(N(0.22), 400, 3000) * np.sin(np.linspace(0, np.pi, int(0.22 * SR))) ** 1.5 * 0.6
    S["loot"] = mixn(*[delay(pluck(freq(midi(n)), 0.4, 0.9, 6, rng) * 0.7, i * 0.05) for i, n in enumerate(["E5", "G#5", "B5", "E6"])])
    S["chest"] = mixn(bandpass_fft(N(0.3), 150, 1200) * fx_env(int(0.3 * SR), 0.005, 12),
                      delay(mixn(*[delay(bell(freq(midi(n)), 0.8, 3.0), i * 0.07) for i, n in enumerate(["C6", "E6", "G6"])]), 0.15))
    S["rope"] = mixn(bandpass_fft(N(0.35), 300, 2500) * fx_env(int(0.35 * SR), 0.01, 7) * 0.6, delay(drum("rim", rng) * 0.6, 0.2))
    S["objective"] = mixn(*[delay(bell(freq(midi(n)), 1.2, 2.0), i * 0.12) for i, n in enumerate(["D5", "A5", "D6"])])
    # --- battle start / end
    S["battle_start"] = mixn(drum("taiko", rng) * 1.2, delay(drum("taiko", rng) * 1.0, 0.28), delay(sweep(180, 360, 0.9, "saw") * env_adsr(int(0.9 * SR), 0.05, 0.2, 0.6, 0.3) * 0.25, 0.1),
                             delay(bell(freq(midi("D5")), 1.5, 1.5) * 0.6, 0.55))
    S["victory"] = mixn(*[delay(pluck(freq(midi(n)), 1.4, 0.85, 2.0, rng) * 1.1, i * 0.14) for i, n in enumerate(["D4", "F#4", "A4", "D5"])],
                        delay(flute(freq(midi("A5")), 0.9, rng) * 1.2, 0.56), delay(flute(freq(midi("D6")), 1.2, rng) * 1.2, 0.95))
    S["defeat"] = mixn(*[delay(fiddle(freq(midi(n)), 0.9, rng, vib=4) * 1.5, i * 0.45) for i, n in enumerate(["A3", "G3", "F3", "E3"])], drum("taiko", rng) * 0.7)
    # --- combat hits
    thud = lambda d=0.18, lo=60, hi=900: bandpass_fft(N(d), lo, hi) * fx_env(int(d * SR), 0.001, 22)  # noqa: E731
    S["hit"] = mixn(thud() * 1.3, sweep(160, 70, 0.15) * fx_env(int(0.15 * SR), 0.001, 25) * 0.8, bandpass_fft(N(0.06), 2000, 7000) * fx_env(int(0.06 * SR), 0.001, 60) * 0.5)
    S["crit"] = mixn(S["hit"] * 1.2, delay(bell(freq(midi("E6")), 0.5, 4.0) * 0.6, 0.01), sweep(900, 200, 0.2, "saw") * fx_env(int(0.2 * SR), 0.001, 16) * 0.3)
    S["block"] = mixn(bell(freq(midi("A5")), 0.4, 6.0) * 0.8, bell(freq(midi("D#6")), 0.35, 7.0) * 0.5, thud(0.1) * 0.6)
    S["armor_break"] = mixn(bell(freq(midi("F5")), 0.5, 5.0) * 0.6, bandpass_fft(N(0.35), 1500, 8000) * fx_env(int(0.35 * SR), 0.001, 9) * 0.7, thud(0.2) * 0.8)
    S["miss"] = bandpass_fft(N(0.22), 700, 4000) * np.sin(np.linspace(0, np.pi, int(0.22 * SR))) ** 2 * 0.55
    S["swing"] = bandpass_fft(N(0.2), 600, 3500) * np.sin(np.linspace(0, np.pi, int(0.2 * SR))) ** 3 * 0.7
    S["step"] = bandpass_fft(N(0.07), 100, 1200) * fx_env(int(0.07 * SR), 0.002, 45) * 0.6
    S["bow"] = mixn(sweep(220, 110, 0.12) * fx_env(int(0.12 * SR), 0.001, 30) * 0.6, delay(bandpass_fft(N(0.25), 1500, 6000) * np.linspace(1, 0, int(0.25 * SR)) * 0.4, 0.02))
    S["throw"] = bandpass_fft(N(0.18), 1000, 5000) * np.sin(np.linspace(0, np.pi, int(0.18 * SR))) * 0.5
    S["downed"] = mixn(thud(0.35, 40, 500) * 1.4, delay(sweep(300, 120, 0.5) * env_adsr(int(0.5 * SR), 0.02, 0.1, 0.7, 0.2) * 0.3, 0.05))
    S["death"] = mixn(thud(0.3, 40, 700), sweep(220, 60, 0.45, "saw") * env_adsr(int(0.45 * SR), 0.01, 0.1, 0.6, 0.2) * 0.25)
    S["death_sting"] = mixn(*[delay(fiddle(freq(midi(n)), 1.8, rng, vib=4) * 1.3, 0.0) for n in ["D4", "F4", "A4", "C5"]], bell(freq(midi("D5")), 3.0, 0.7) * 0.8)
    S["heartbeat"] = mixn(drum("bodhran", rng) * 0.8, delay(drum("bodhran", rng) * 0.6, 0.22))
    S["revive"] = mixn(*[delay(bell(freq(midi(n)), 0.9, 2.5), i * 0.08) for i, n in enumerate(["C5", "E5", "G5", "C6"])])
    S["spawn"] = mixn(sweep(80, 240, 0.5, "saw") * env_adsr(int(0.5 * SR), 0.1, 0.2, 0.5, 0.2) * 0.3, bandpass_fft(N(0.5), 200, 2000) * env_adsr(int(0.5 * SR), 0.2, 0.1, 0.6, 0.2) * 0.4)
    S["reveal"] = mixn(bandpass_fft(N(0.4), 500, 4000) * fx_env(int(0.4 * SR), 0.01, 8) * 0.5, bell(freq(midi("B5")), 0.6, 3) * 0.4)
    S["extract"] = mixn(*[delay(flute(freq(midi(n)), 0.25, rng) * 1.3, i * 0.09) for i, n in enumerate(["G5", "B5", "D6"])])
    S["trap"] = mixn(bell(freq(midi("C6")), 0.2, 12) * 0.7, thud(0.2, 100, 3000) * 1.0)
    # --- magic and elements
    S["cast"] = mixn(sweep(300, 900, 0.35) * env_adsr(int(0.35 * SR), 0.05, 0.1, 0.6, 0.15) * 0.35, bandpass_fft(N(0.35), 2000, 8000) * env_adsr(int(0.35 * SR), 0.1, 0.1, 0.5, 0.1) * 0.25)
    S["heal_cast"] = mixn(*[delay(bell(freq(midi(n)), 0.8, 2.0) * 0.8, i * 0.06) for i, n in enumerate(["G5", "D6", "G6"])], pad(freq(midi("G4")), 0.8, rng) * 2.0)
    S["heal"] = mixn(bell(freq(midi("E6")), 0.6, 3.0) * 0.6, delay(bell(freq(midi("B6")), 0.5, 3.5) * 0.4, 0.05))
    S["buff"] = mixn(sweep(500, 1000, 0.25) * env_adsr(int(0.25 * SR), 0.02, 0.05, 0.6, 0.1) * 0.3, delay(bell(freq(midi("A5")), 0.5, 3.0) * 0.4, 0.08))
    S["status_bad"] = mixn(sweep(500, 250, 0.3, "square") * env_adsr(int(0.3 * SR), 0.01, 0.05, 0.5, 0.1) * 0.18, bandpass_fft(N(0.3), 200, 1500) * fx_env(int(0.3 * SR), 0.01, 9) * 0.3)
    S["fire"] = bandpass_fft(N(0.6), 150, 2500) * env_adsr(int(0.6 * SR), 0.03, 0.2, 0.6, 0.3) * (1 + 0.5 * np.sin(np.arange(int(0.6 * SR)) / SR * 2 * np.pi * 13)) * 0.6
    S["frost"] = mixn(bandpass_fft(N(0.45), 3000, 9000) * fx_env(int(0.45 * SR), 0.005, 6) * 0.5, *[delay(bell(freq(midi(n)), 0.4, 6.0) * 0.4, i * 0.05) for i, n in enumerate(["E7", "B6", "G7"])])
    lz = bandpass_fft(N(0.5), 200, 6000) * fx_env(int(0.5 * SR), 0.001, 7)
    lz *= (rng.random(len(lz)) < 0.35) * 1.5 + 0.3
    S["lightning"] = mixn(lz * 0.8, drum("taiko", rng) * 0.6)
    S["poison"] = mixn(*[delay(sweep(300 + 80 * i, 180, 0.12) * fx_env(int(0.12 * SR), 0.005, 25) * 0.4, i * 0.07) for i in range(4)])
    S["bleed"] = mixn(bandpass_fft(N(0.2), 300, 1500) * fx_env(int(0.2 * SR), 0.005, 18) * 0.6, sweep(200, 120, 0.15) * fx_env(int(0.15 * SR), 0.005, 25) * 0.3)
    S["water"] = mixn(*[delay(sweep(400 + rng.integers(0, 500), 900 + rng.integers(0, 600), 0.08) * fx_env(int(0.08 * SR), 0.003, 35) * 0.3, rng.uniform(0, 0.4)) for _ in range(9)],
                      bandpass_fft(N(0.6), 300, 3000) * env_adsr(int(0.6 * SR), 0.05, 0.2, 0.4, 0.3) * 0.3)
    S["roots"] = mixn(bandpass_fft(N(0.5), 60, 600) * env_adsr(int(0.5 * SR), 0.02, 0.2, 0.5, 0.2) * 0.9, *[delay(drum("rim", rng) * 0.4, 0.1 * i) for i in range(4)])
    S["smoke"] = bandpass_fft(N(0.6), 200, 3000) * env_adsr(int(0.6 * SR), 0.05, 0.2, 0.5, 0.3) * 0.55
    S["teleport"] = mixn(sweep(200, 1600, 0.3) * env_adsr(int(0.3 * SR), 0.01, 0.1, 0.6, 0.1) * 0.3, delay(sweep(1600, 300, 0.3) * env_adsr(int(0.3 * SR), 0.01, 0.1, 0.6, 0.1) * 0.25, 0.15))
    S["shout"] = mixn(sweep(180, 240, 0.35, "saw") * env_adsr(int(0.35 * SR), 0.02, 0.1, 0.7, 0.1) * 0.25, bandpass_fft(N(0.35), 500, 2500) * env_adsr(int(0.35 * SR), 0.02, 0.1, 0.5, 0.1) * 0.25)
    S["hush"] = mixn(choir(freq(midi("C4")), 1.4, rng) * 3.0, choir(freq(midi("C#4")), 1.4, rng) * 2.0, sweep(120, 60, 1.2) * env_adsr(int(1.2 * SR), 0.3, 0.2, 0.6, 0.5) * 0.3)
    # --- voices (babble, pitched per member in game)
    S["voice_talk"] = babble(rng, 3, 190, ["e", "a", "o"], [0.1, -0.05, -0.15])
    S["voice_shout"] = babble(rng, 2, 230, ["a", "o"], [0.25, -0.2], dur=0.12)
    S["voice_hurt"] = babble(rng, 2, 210, ["u", "a"], [0.3, -0.45], dur=0.13, gap=0.01)
    S["bell_far"] = convolve_reverb(np.concatenate([bell(freq(midi("D4")), 2.5, 0.8), np.zeros(SR)]), 2.5, rng) * 1.2 + np.concatenate([bell(freq(midi("D4")), 2.5, 0.8), np.zeros(SR)]) * 0.35
    out = {}
    for k, y in S.items():
        y = np.asarray(y, dtype=float)
        tail = int(0.01 * SR)
        if len(y) > tail:
            y[-tail:] *= np.linspace(1, 0, tail)
        out[k] = normalize(y, 0.8 if k not in ("ui_hover", "step") else 0.5)
    return out


def main():
    args = sys.argv[1:]
    only = args[args.index("--only") + 1] if "--only" in args else ""
    track = args[args.index("--track") + 1] if "--track" in args else ""
    if only in ("", "sfx") and not track:
        for k, y in sfx_all().items():
            write_wav(os.path.join(OUT_SFX, k + ".wav"), y)
        print("sfx:", len(os.listdir(OUT_SFX)))
    if only in ("", "music"):
        for k, fn in MUSIC.items():
            if track and k != track:
                continue
            y = fn()
            write_wav(os.path.join(OUT_MUSIC, k + ".wav"), y)
            print("music:", k, "%.1fs" % (len(y) / SR))


if __name__ == "__main__":
    main()
