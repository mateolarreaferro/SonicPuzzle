"""Generates the UI sound effects in assets/audio/sfx. Run: python3 tools/make_sfx.py

Everything is short, dry and soft on purpose: these play on the UI bus,
outside the room acoustics, while the player is listening critically.
"""
import wave
from pathlib import Path

import numpy as np

SR = 48000
OUT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "sfx"


def env(n, attack, decay):
    t = np.arange(n) / SR
    a = np.clip(t / attack, 0, 1)
    return a * np.exp(-t / decay)


def bell(freq, dur, decay, partials=((1, 1.0), (2.0, 0.25), (3.01, 0.08))):
    n = int(dur * SR)
    t = np.arange(n) / SR
    s = sum(g * np.sin(2 * np.pi * freq * r * t) * np.exp(-t * r / decay) for r, g in partials)
    return s * env(n, 0.004, 10.0)


def place(buf, sig, at):
    i = int(at * SR)
    buf[i:i + len(sig)] += sig[: len(buf) - i]


def write(name, sig, peak_db=-6.0):
    sig = sig / np.max(np.abs(sig)) * 10 ** (peak_db / 20)
    fade = int(0.01 * SR)
    sig[-fade:] *= np.linspace(1, 0, fade)
    data = (sig * 32767).astype("<i2").tobytes()
    with wave.open(str(OUT / name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)
    print("wrote", name)


def select():
    # Soft wooden tock: a pitch-dropping sine plus a tiny filtered click.
    n = int(0.12 * SR)
    t = np.arange(n) / SR
    f = 620 + 500 * np.exp(-t / 0.012)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.001, 0.025)
    rng = np.random.default_rng(1)
    click = np.convolve(rng.standard_normal(n), np.ones(12) / 12, "same") * env(n, 0.0005, 0.003)
    return body + 0.4 * click


def correct():
    # Two rising bell notes (a fifth apart).
    buf = np.zeros(int(1.1 * SR))
    place(buf, bell(1046.5, 1.0, 0.35), 0.0)
    place(buf, bell(1568.0, 1.0, 0.4), 0.08)
    return buf


def clear():
    # Rising major arpeggio over a soft swelling pad.
    dur = 3.2
    buf = np.zeros(int(dur * SR))
    t = np.arange(len(buf)) / SR
    pad_env = np.clip(t / 0.8, 0, 1) * np.exp(-np.maximum(t - 0.8, 0) / 0.9)
    for f in (261.63, 392.0, 523.25, 659.25):
        buf += 0.12 * np.sin(2 * np.pi * f * t + np.sin(2 * np.pi * 0.3 * t)) * pad_env
    for i, f in enumerate((523.25, 659.25, 783.99, 1046.5, 1318.5)):
        place(buf, bell(f, 1.8, 0.6), 0.09 * i)
    return buf


OUT.mkdir(parents=True, exist_ok=True)
write("select.wav", select(), -8.0)
write("correct.wav", correct(), -6.0)
write("clear.wav", clear(), -4.0)
