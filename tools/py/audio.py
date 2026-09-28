"""Procedural music and sound effects for A Guilda (numpy only).

Music: medieval folk in the guild (lute, fiddle, flute, frame drum), tense
percussion and strings in combat, with danger layers that line up sample for
sample with their base track. Loops are seamless: everything that rings past
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
    raise ValueError(kind)


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


# ------------------------------------------------------------------ tracks
def track_guild(seed=11):
    # tavern jig in D dorian, 6/8 felt as two beats of three eighths
    tr = Track(bars=32, bpm=104, beats_per_bar=3, seed=seed)
    rng = tr.rng
    root = midi("D4")
    prog = [("D3", "m"), ("C3", "M"), ("D3", "m"), ("A2", "m"), ("F3", "M"), ("C3", "M"), ("G2", "M"), ("A2", "m")] * 4
    chords = [chord(midi(r), q) for r, q in prog]
    scale = scale_notes(root % 12, "dorian", 50, 88)
    for ci, ch in enumerate(chords):
        b0 = ci * 3
        # lute: bass + broken chord in eighths (triplet feel)
        tr.at(b0, pluck(freq(ch[0] - 12), 1.6, 0.7, 2.2, rng), 0.9)
        pattern = [ch[0], ch[1], ch[2], ch[1] + 12, ch[2], ch[1]]
        for k, n in enumerate(pattern):
            tr.at(b0 + k * 0.5, pluck(freq(n), 0.9, 0.8, 3.5, rng), 0.45 if k % 3 else 0.6)
        # frame drum
        if ci >= 4:
            tr.at(b0, drum("bodhran", rng), 0.8)
            tr.at(b0 + 1.5, drum("bodhran", rng, 0.6), 0.6)
            tr.at(b0 + 2.5, drum("rim", rng), 0.5)
    mel = melody(rng, chords, scale, 3, [0.5, 0.5, 1.0, 1.5], midi("A4"), span=(62, 81))
    for (b, d, n) in mel:
        if b < 12:  # first phrase: flute alone
            tr.at(b, flute(freq(n), d * tr.beat + 0.05, rng), 0.9)
        elif (b // 24) % 2 == 0:
            tr.at(b, fiddle(freq(n), d * tr.beat + 0.04, rng), 0.95)
        else:
            tr.at(b, flute(freq(n + 12), d * tr.beat + 0.05, rng), 0.7)
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


def _combat_base(tr, rng, prog, root_scale, hush=False):
    chords = [chord(midi(r), q) for r, q in prog]
    for ci, ch in enumerate(chords):
        b0 = ci * 4
        # low string ostinato in eighths
        for k in range(8):
            n = ch[0] - 12 if k % 4 != 3 else ch[0] - 12 + (7 if k % 8 == 3 else 5)
            tr.at(b0 + k * 0.5, fiddle(freq(n), 0.5 * tr.beat * 0.9, rng, vib=0, harm=8), 0.55 if k % 2 == 0 else 0.4)
        tr.at(b0, pad(freq(ch[0]), 4 * tr.beat + 0.3, rng, harm=6, attack=0.3), 0.8)
        # war drums
        tr.at(b0, drum("taiko", rng), 1.0)
        tr.at(b0 + 1.5, drum("tom", rng), 0.6)
        tr.at(b0 + 2, drum("taiko", rng, 0.7), 0.8)
        tr.at(b0 + 3.5, drum("tom", rng, 0.8), 0.5)
        if hush:
            tr.at(b0, bell(freq(ch[0] + 24 + (1 if ci % 2 else 0)), 3.5, 0.6), 0.22)
    return chords


def track_combat(seed=21, layer=False):
    tr = Track(bars=16, bpm=124, beats_per_bar=4, seed=seed)
    rng = tr.rng
    prog = [("E2", "m"), ("E2", "m"), ("F2", "M"), ("E2", "m"), ("C3", "M"), ("D3", "M"), ("B2", "dim"), ("E2", "5")] * 2
    if not layer:
        chords = _combat_base(tr, rng, prog, "phrygian")
        scale = scale_notes(midi("E3") % 12, "phrygian", 52, 84)
        mel = melody(np.random.default_rng(seed + 1), chords, scale, 4, [0.5, 0.5, 1.0, 1.5], midi("B4"), span=(64, 79))
        for (b, d, n) in mel:
            if (b // 16) % 2 == 1:
                tr.at(b, fiddle(freq(n), d * tr.beat, rng, vib=6.5), 0.55)
        return normalize(tr.finish(0.18, 1.2), 0.82)
    # danger layer: driving percussion and a high tremolo
    chords = [chord(midi(r), q) for r, q in prog]
    for ci, ch in enumerate(chords):
        b0 = ci * 4
        for k in range(16):
            tr.at(b0 + k * 0.25, drum("shaker", rng, 1.0 if k % 4 == 0 else 0.6), 1.0)
        for k in (0.75, 1.75, 2.75, 3.25, 3.75):
            tr.at(b0 + k, drum("rim", rng), 0.8)
        for k in range(8):
            tr.at(b0 + k * 0.5, fiddle(freq(ch[2] + 12), 0.24, rng, vib=0, harm=6), 0.25)
        if ci % 4 == 3:
            tr.at(b0 + 3, drum("cymbal", rng), 1.0)
    return normalize(tr.finish(0.18, 1.2), 0.7)


def track_hush(seed=31):
    tr = Track(bars=16, bpm=92, beats_per_bar=4, seed=seed)
    rng = tr.rng
    prog = [("C3", "m"), ("C3", "m"), ("Db3", "M"), ("C3", "m"), ("Ab2", "M"), ("G2", "dim"), ("Db3", "M"), ("C3", "5")] * 2
    chords = [chord(midi(r), q) for r, q in prog]
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
    return normalize(tr.finish(0.45, 2.6), 0.78)


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
    "hush_battle": lambda: track_hush(),
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
