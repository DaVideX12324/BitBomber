"""Generator muzyki BitBombera: dwa chiptune'owe loopy (menu, walka) → WAV 32000 Hz mono 16 bit.

Użycie:  python tools/gen_music.py [resources/music]
Plik ma chunk „smpl” z pętlą na cały utwór — Godot (import WAV, loop „Detect From WAV”) zapętla go sam.
Melodie są zapisane niżej jako (nuta, długość w ósemkach); zmiana utworu = zmiana tych list.
"""
import os
import struct
import sys

import numpy as np
from scipy.signal import lfilter

SR = 32000
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "resources", "music")
rng = np.random.default_rng(11)

NOTE_INDEX = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}
CHORDS = {  # półtony od prymy
    "": (0, 4, 7), "m": (0, 3, 7),
}


def midi(name):
    """'A4' → numer MIDI, 'r' → None (pauza)."""
    if name == "r":
        return None
    return 12 * (int(name[-1]) + 1) + NOTE_INDEX[name[:-1]]


def freq(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def chord_notes(symbol, octave):
    """'Am' → MIDI prymy, tercji i kwinty w danej oktawie."""
    root = symbol[:2] if len(symbol) > 1 and symbol[1] == "#" else symbol[:1]
    quality = symbol[len(root):]
    base = 12 * (octave + 1) + NOTE_INDEX[root]
    return [base + i for i in CHORDS[quality]]


# --- oscylatory ---------------------------------------------------------------

def osc(kind, f, n, duty=0.5, vibrato=0.0):
    t = np.arange(n) / SR
    fm = f * (1 + vibrato * np.sin(2 * np.pi * 5.5 * t) * np.clip(t / 0.25 - 0.4, 0, 1))
    phase = np.cumsum(fm) / SR % 1.0
    if kind == "square":
        return np.where(phase < duty, 1.0, -1.0)
    if kind == "tri":
        return 4 * np.abs(phase - 0.5) - 1
    return np.sin(2 * np.pi * phase)


def adsr(n, a=0.004, d=0.08, s=0.6, r=0.03):
    e = np.full(n, s)
    na, nd, nr = int(SR * a), int(SR * d), min(int(SR * r), n // 2)
    e[:na] = np.linspace(0, 1, na)
    e[na:na + nd] = np.linspace(1, s, len(e[na:na + nd]))
    e[n - nr:] *= np.linspace(1, 0, nr)
    return e


def lowpass(x, cutoff):
    a = 1 - np.exp(-2 * np.pi * cutoff / SR)
    return lfilter([a], [1, a - 1], x)


# --- perkusja -----------------------------------------------------------------

def kick():
    n = int(SR * 0.16)
    t = np.arange(n) / SR
    f = 150 * np.exp(-t * 28) + 42
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 14)


def snare():
    n = int(SR * 0.14)
    t = np.arange(n) / SR
    noise = lowpass(rng.uniform(-1, 1, n), 6000) * np.exp(-t * 22)
    return noise * 0.8 + np.sin(2 * np.pi * 190 * t) * np.exp(-t * 30) * 0.4


def hat():
    n = int(SR * 0.04)
    x = rng.uniform(-1, 1, n)
    x = x - lowpass(x, 7000)  # górnoprzepustowy
    return x * np.exp(-np.arange(n) / SR * 90)


# --- układanie ----------------------------------------------------------------

class Song:
    def __init__(self, bpm, bars):
        self.step = 60.0 / bpm / 2           # ósemka w sekundach
        self.n = int(round(bars * 8 * self.step * SR))
        self.buf = np.zeros(self.n + SR)      # zapas na ogony, zawijany na początek pętli

    def at(self, eighth):
        return int(round(eighth * self.step * SR))

    def add(self, start_eighth, x, gain):
        i = self.at(start_eighth)
        self.buf[i:i + len(x)] += x * gain

    def note(self, start, length, m, kind, gain, duty=0.5, vibrato=0.0, env=None):
        n = int(length * self.step * SR)
        x = osc(kind, freq(m), n, duty, vibrato) * adsr(n, **(env or {}))
        self.add(start, x, gain)

    def melody(self, notes, kind, gain, duty=0.5, vibrato=0.004, transpose=0):
        pos = 0
        for name, length in notes:
            m = midi(name)
            if m is not None:
                self.note(pos, length * 0.95, m + transpose, kind, gain, duty, vibrato if length >= 3 else 0.0)
            pos += length

    def render(self):
        out = self.buf[:self.n].copy()
        tail = self.buf[self.n:]
        out[:len(tail)] += tail                # bezszwowa pętla
        return out


def save(name, x, peak=0.72):
    x = x / max(1e-9, np.max(np.abs(x))) * peak
    data = (x * 32767).astype("<i2").tobytes()
    n = len(x)
    fmt = struct.pack("<HHIIHH", 1, 1, SR, SR * 2, 2, 16)
    # smpl: producent, produkt, okres próbki [ns], nuta MIDI, ułamek, SMPTE ×2, liczba pętli, dane; pętla: id, typ, start, koniec, ułamek, powtórzenia
    smpl = struct.pack("<9I", 0, 0, int(1e9 / SR), 60, 0, 0, 0, 1, 0) + struct.pack("<6I", 0, 0, 0, n - 1, 0, 0)
    chunks = b"fmt " + struct.pack("<I", len(fmt)) + fmt
    chunks += b"data" + struct.pack("<I", len(data)) + data
    chunks += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name + ".wav"), "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", 4 + len(chunks)) + b"WAVE" + chunks)
    print(name, "%.1fs" % (n / SR))


# --- utwory -------------------------------------------------------------------

BATTLE_CHORDS = ["Am", "Am", "F", "F", "C", "C", "G", "G", "Am", "Am", "F", "F", "Dm", "Dm", "E", "E"]
BATTLE_LEAD = [
    ("A4", 1), ("C5", 1), ("E5", 2), ("D5", 1), ("C5", 1), ("B4", 1), ("C5", 1),
    ("A4", 4), ("r", 2), ("E4", 1), ("A4", 1),
    ("F5", 2), ("E5", 1), ("D5", 1), ("C5", 2), ("A4", 2),
    ("C5", 3), ("D5", 1), ("C5", 2), ("r", 2),
    ("E5", 1), ("G5", 1), ("C6", 2), ("B5", 1), ("G5", 1), ("E5", 2),
    ("G5", 4), ("r", 2), ("E5", 1), ("G5", 1),
    ("D5", 2), ("G5", 2), ("F5", 1), ("E5", 1), ("D5", 1), ("B4", 1),
    ("D5", 4), ("B4", 2), ("G4", 2),
    ("A5", 2), ("G5", 1), ("E5", 1), ("A5", 2), ("C6", 2),
    ("B5", 1), ("A5", 1), ("G5", 1), ("E5", 1), ("A5", 4),
    ("F5", 1), ("A5", 1), ("C6", 2), ("A5", 1), ("F5", 1), ("C5", 2),
    ("D5", 2), ("C5", 1), ("A4", 1), ("C5", 4),
    ("D5", 1), ("F5", 1), ("A5", 2), ("G5", 1), ("F5", 1), ("E5", 1), ("D5", 1),
    ("F5", 4), ("A5", 2), ("F5", 2),
    ("E5", 2), ("G#5", 2), ("B5", 2), ("D6", 2),
    ("E6", 2), ("D6", 1), ("B5", 1), ("G#5", 2), ("E5", 2),
]

MENU_CHORDS = ["C", "Am", "F", "G", "C", "Am", "F", "G", "F", "G", "Em", "Am", "F", "G", "C", "C"]
MENU_LEAD = [
    ("E5", 2), ("G5", 2), ("C6", 2), ("G5", 2),
    ("A5", 4), ("E5", 2), ("C5", 2),
    ("F5", 2), ("A5", 2), ("C6", 2), ("A5", 2),
    ("G5", 4), ("D5", 2), ("B4", 2),
    ("C5", 2), ("E5", 2), ("G5", 3), ("A5", 1),
    ("G5", 2), ("E5", 2), ("C5", 4),
    ("D5", 2), ("F5", 2), ("A5", 2), ("G5", 2),
    ("G5", 6), ("r", 2),
    ("A5", 2), ("C6", 2), ("A5", 2), ("F5", 2),
    ("B5", 2), ("D6", 2), ("B5", 2), ("G5", 2),
    ("G5", 2), ("E5", 2), ("B4", 2), ("E5", 2),
    ("C5", 2), ("E5", 2), ("A5", 4),
    ("F5", 3), ("G5", 1), ("A5", 2), ("C6", 2),
    ("B5", 2), ("A5", 2), ("G5", 2), ("D5", 2),
    ("E5", 4), ("G5", 2), ("E5", 2),
    ("C5", 6), ("r", 2),
]


def check(lead, bars):
    total = sum(length for _, length in lead)
    assert total == bars * 8, "melodia ma %d ósemek zamiast %d" % (total, bars * 8)


def battle():
    bars = len(BATTLE_CHORDS)
    check(BATTLE_LEAD, bars)
    s = Song(150, bars)
    s.melody(BATTLE_LEAD, "square", 0.30, duty=0.25)
    s.melody(BATTLE_LEAD, "square", 0.07, duty=0.5, transpose=-12)   # echo oktawę niżej
    for b, ch in enumerate(BATTLE_CHORDS):
        root = chord_notes(ch, 2)[0]
        for i, off in enumerate((0, 0, 12, 0, 0, 12, 0, 12)):           # bas ósemkami z oktawą
            s.note(b * 8 + i, 0.9, root + off, "tri", 0.42, env={"d": 0.05, "s": 0.8})
        arp = chord_notes(ch, 4)
        for i in range(16):                                              # arpeggio szesnastkami
            s.note(b * 8 + i / 2, 0.45, arp[i % 3] + (12 if i % 6 >= 3 else 0), "square", 0.06,
                   duty=0.125, env={"d": 0.04, "s": 0.3, "r": 0.01})
        for i in range(8):
            if i in (0, 4) or (i == 5 and b % 2 == 1):
                s.add(b * 8 + i, kick(), 0.55)
            if i in (2, 6):
                s.add(b * 8 + i, snare(), 0.32)
            s.add(b * 8 + i + 0.5 * (i % 2), hat(), 0.10 if i % 2 else 0.07)
        if b == bars - 1:                                                # przejście na koniec pętli
            for k in range(4):
                s.add(b * 8 + 6 + k * 0.5, snare(), 0.18 + 0.04 * k)
    return lowpass(s.render(), 9000)


def menu():
    bars = len(MENU_CHORDS)
    check(MENU_LEAD, bars)
    s = Song(104, bars)
    s.melody(MENU_LEAD, "tri", 0.40, vibrato=0.006)
    s.melody(MENU_LEAD, "square", 0.05, duty=0.125, transpose=12)
    for b, ch in enumerate(MENU_CHORDS):
        root = chord_notes(ch, 2)[0]
        for i, off in enumerate((0, 7, 12, 7)):                          # bas ćwierćnutami
            s.note(b * 8 + i * 2, 1.8, root + off, "tri", 0.35, env={"d": 0.2, "s": 0.5})
        arp = chord_notes(ch, 4)
        for i in range(8):                                               # spokojne arpeggio ósemkami
            s.note(b * 8 + i, 0.9, arp[(0, 1, 2, 1)[i % 4]] + (12 if i >= 4 else 0), "square", 0.05,
                   duty=0.25, env={"d": 0.15, "s": 0.25})
        s.add(b * 8, kick(), 0.35)
        s.add(b * 8 + 4, kick(), 0.25)
        for i in range(4):
            s.add(b * 8 + i * 2 + 1, hat(), 0.07)
    return lowpass(s.render(), 7000)


if __name__ == "__main__":
    save("battle", battle())
    save("menu", menu())
