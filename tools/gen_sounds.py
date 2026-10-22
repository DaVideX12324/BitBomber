"""Generator efektów dźwiękowych BitBombera (synteza numpy → WAV 22050 Hz mono 16 bit).

Użycie:  python tools/gen_sounds.py [resources/sounds]
Deterministyczne (stały seed szumu).
"""
import os
import sys
import wave

import numpy as np

SR = 22050
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "resources", "sounds")
rng = np.random.default_rng(7)


def t(dur):
    return np.arange(int(SR * dur)) / SR


def env(n, attack=0.005, decay_pow=2.0):
    """Szybki atak, potem opadanie (1 - x)^pow."""
    a = max(1, int(SR * attack))
    e = np.ones(n)
    e[:a] = np.linspace(0, 1, a)
    e[a:] = (1 - np.linspace(0, 1, n - a)) ** decay_pow
    return e


def sweep(f0, f1, dur, shape="sine"):
    tt = t(dur)
    f = np.geomspace(f0, f1, len(tt))
    ph = 2 * np.pi * np.cumsum(f) / SR
    if shape == "square":
        return np.sign(np.sin(ph)) * 0.6 + np.sin(ph) * 0.4
    if shape == "tri":
        return 2 / np.pi * np.arcsin(np.sin(ph))
    return np.sin(ph)


def lowpass(x, cutoff):
    """Jednobiegunowy filtr dolnoprzepustowy (cutoff może być tablicą — sweep)."""
    cutoff = np.broadcast_to(np.asarray(cutoff, float), x.shape)
    a = 1 - np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a[i] * (x[i] - acc)
        y[i] = acc
    return y


def noise(dur):
    return rng.uniform(-1, 1, int(SR * dur))


def note(freq, dur, shape="tri", decay=2.0):
    x = sweep(freq, freq, dur, shape)
    return x * env(len(x), 0.004, decay)


def cat(*parts):
    return np.concatenate(parts)


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def save(name, x, gain=0.9):
    x = x / max(1e-9, np.max(np.abs(x))) * gain
    path = os.path.join(OUT, name + ".wav")
    os.makedirs(OUT, exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype("<i2").tobytes())
    print(name, "%.2fs" % (len(x) / SR))


def gen():
    # Kładzenie bomby: niski „tump” + klik
    x = sweep(170, 55, 0.16) * env(int(SR * 0.16), 0.002, 2.5)
    x[:60] += rng.uniform(-1, 1, 60) * np.linspace(1, 0, 60) * 0.6
    save("bomb_place", x, 0.7)

    # Wybuch: szum z opadającym filtrem + basowe „bum”
    d = 0.75
    n = noise(d)
    cut = np.geomspace(5000, 180, len(n))
    boom = sweep(90, 35, d) * env(len(n), 0.003, 2.2)
    x = lowpass(n, cut) * env(len(n), 0.002, 1.6) * 1.6 + boom * 0.9
    save("explosion", x, 0.95)

    # Podniesienie przedmiotu: arpeggio C6 E6 G6 C7
    x = cat(*[note(f, 0.07, "square", 1.2) * 0.5 for f in (1047, 1319, 1568, 2093)])
    save("pickup", lowpass(x, 6000), 0.6)

    # Kopnięcie: krótki świst (szum, filtr w górę)
    d = 0.18
    x = lowpass(noise(d), np.geomspace(400, 4000, int(SR * d))) * env(int(SR * d), 0.01, 1.5)
    x = mix(x, sweep(220, 330, d) * env(int(SR * d), 0.002, 3) * 0.4)
    save("kick", x, 0.6)

    # Śmierć: opadający ton z wibrato
    d = 0.6
    tt = t(d)
    f = np.geomspace(700, 120, len(tt)) * (1 + 0.04 * np.sin(2 * np.pi * 14 * tt))
    x = np.sin(2 * np.pi * np.cumsum(f) / SR)
    x = (np.sign(x) * 0.3 + x * 0.7) * env(len(tt), 0.005, 1.3)
    save("death", lowpass(x, 3500), 0.7)

    # Pęknięcie tarczy: wysoki „dzyń” + szum
    d = 0.35
    x = mix(note(2637, d, "sine", 3) * 0.6, note(3951, d, "sine", 4) * 0.4,
            lowpass(noise(0.08), 8000) * env(int(SR * 0.08), 0.001, 2) * 0.5)
    save("shield_break", x, 0.6)

    # Nagła śmierć: alarm (3 × dwa tony)
    beeps = []
    for _ in range(3):
        beeps += [note(880, 0.13, "square", 0.6) * 0.6, note(660, 0.13, "square", 0.6) * 0.6, np.zeros(int(SR * 0.04))]
    save("sudden_death", lowpass(cat(*beeps), 5000), 0.7)

    # Spadający blok: ciężki „łup”
    d = 0.22
    x = mix(sweep(120, 40, d) * env(int(SR * d), 0.002, 3), lowpass(noise(d), 900) * env(int(SR * d), 0.001, 4) * 0.8)
    save("block_drop", x, 0.6)

    # Start rundy: dwa narastające dźwięki
    x = cat(note(784, 0.12, "tri", 1.0), np.zeros(int(SR * 0.05)), note(1175, 0.22, "tri", 1.5))
    save("round_start", x, 0.6)

    # Wygrana rundy: krótka fanfara
    x = cat(*[note(f, dur, "tri", 1.2) for f, dur in ((523, 0.11), (659, 0.11), (784, 0.11), (1047, 0.4))])
    save("round_win", x, 0.65)


if __name__ == "__main__":
    gen()
