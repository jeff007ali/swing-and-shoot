#!/usr/bin/env python3
"""Synthesizes the sounds the Kenney packs don't have: the sniper shot and bolt, and the knife swish.

Run from the project root: python3 tools/build_sfx.py
Writes 16-bit mono WAVs to assets/audio/sfx/. Seeded, so the output is the same every run.
"""

import math
import random
import struct
import wave

RATE = 44100
OUT = "assets/audio/sfx/"


def silence(seconds):
    return [0.0] * int(RATE * seconds)


def mix(dst, src, at=0.0, gain=1.0):
    start = int(at * RATE)
    if len(dst) < start + len(src):
        dst.extend([0.0] * (start + len(src) - len(dst)))
    for i, v in enumerate(src):
        dst[start + i] += v * gain
    return dst


def noise(rng, seconds):
    return [rng.uniform(-1.0, 1.0) for _ in range(int(RATE * seconds))]


def envelope(samples, attack, decay):
    """Linear attack, then exponential decay with time constant decay (s)."""
    out = []
    a = max(1, int(attack * RATE))
    for i, v in enumerate(samples):
        t = i / RATE
        g = (i / a) if i < a else math.exp(-(t - attack) / decay)
        out.append(v * g)
    return out


def lowpass(samples, cutoff):
    k = 1.0 - math.exp(-2.0 * math.pi * cutoff / RATE)
    y = 0.0
    out = []
    for v in samples:
        y += k * (v - y)
        out.append(y)
    return out


def highpass(samples, cutoff):
    low = lowpass(samples, cutoff)
    return [v - l for v, l in zip(samples, low)]


def bandpass(samples, center, q, sweep_to=None):
    """Biquad band-pass; with sweep_to the center glides there over the sound."""
    out = []
    x1 = x2 = y1 = y2 = 0.0
    n = len(samples)
    for i, x in enumerate(samples):
        f = center if sweep_to is None else center * (sweep_to / center) ** (i / max(1, n - 1))
        w = 2.0 * math.pi * f / RATE
        alpha = math.sin(w) / (2.0 * q)
        b0, b2 = alpha, -alpha
        a0, a1, a2 = 1.0 + alpha, -2.0 * math.cos(w), 1.0 - alpha
        y = (b0 * x + b2 * x2 - a1 * y1 - a2 * y2) / a0
        x2, x1 = x1, x
        y2, y1 = y1, y
        out.append(y)
    return out


def tone(freq_from, freq_to, seconds, decay):
    out = []
    phase = 0.0
    n = int(RATE * seconds)
    for i in range(n):
        f = freq_from * (freq_to / freq_from) ** (i / max(1, n - 1))
        phase += 2.0 * math.pi * f / RATE
        out.append(math.sin(phase) * math.exp(-(i / RATE) / decay))
    return out


def write(name, samples, peak=0.9):
    top = max(abs(v) for v in samples) or 1.0
    with wave.open(OUT + name + ".wav", "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        frames = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v / top * peak)) * 32767)) for v in samples)
        w.writeframes(frames)


def sniper_shot(rng):
    """A hard crack, a deep boom and a long rolling echo: heard across the arena."""
    out = silence(1.2)
    crack = envelope(highpass(noise(rng, 0.08), 2500.0), 0.0005, 0.012)
    boom = tone(140.0, 38.0, 0.7, 0.22)
    body = envelope(lowpass(noise(rng, 0.5), 900.0), 0.002, 0.08)
    echo = envelope(lowpass(noise(rng, 1.1), 500.0), 0.05, 0.35)
    mix(out, crack, 0.0, 1.0)
    mix(out, boom, 0.0, 0.9)
    mix(out, body, 0.0, 1.4)
    mix(out, echo, 0.06, 0.5)
    return out


def click(rng, ring_hz):
    burst = envelope(bandpass(noise(rng, 0.05), ring_hz, 3.0), 0.0005, 0.008)
    ping = [a + b for a, b in zip(tone(ring_hz, ring_hz * 0.98, 0.09, 0.025), tone(ring_hz * 1.53, ring_hz * 1.5, 0.09, 0.018))]
    return mix(burst, ping, 0.0, 0.25)


def sniper_bolt(rng):
    """Bolt back, slide, bolt home: the sniper has been picked up."""
    out = silence(0.55)
    mix(out, click(rng, 2300.0), 0.0, 1.0)
    slide = envelope(bandpass(noise(rng, 0.14), 1400.0, 1.5, 2600.0), 0.03, 0.05)
    mix(out, slide, 0.05, 0.6)
    mix(out, click(rng, 3100.0), 0.24, 1.2)
    mix(out, envelope(lowpass(noise(rng, 0.06), 400.0), 0.0005, 0.02), 0.24, 0.8)
    return out


def knife_swish(rng):
    """Air rushing past a blade, then a faint metallic shing."""
    out = silence(0.32)
    n = noise(rng, 0.22)
    swish = bandpass(n, 700.0, 1.2, 4200.0)
    shaped = []
    for i, v in enumerate(swish):
        k = i / len(swish)
        shaped.append(v * math.sin(math.pi * k) ** 1.5)
    mix(out, shaped, 0.0, 1.0)
    shing = [a + b for a, b in zip(tone(5200.0, 5000.0, 0.16, 0.05), tone(7400.0, 7200.0, 0.16, 0.035))]
    mix(out, shing, 0.12, 0.12)
    return out


def main():
    rng = random.Random(41)
    write("sniper_shot", sniper_shot(rng))
    write("sniper_bolt", sniper_bolt(rng), 0.8)
    write("knife_swish", knife_swish(rng), 0.8)


if __name__ == "__main__":
    main()
