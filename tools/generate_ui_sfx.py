"""Create original, quiet synthetic UI sounds using only Python's standard library.

No API, credentials, samples or paid services. Does not enable audio in the game.
"""
from __future__ import annotations

import math
import argparse
from pathlib import Path
import random
import struct
import wave

RATE = 44100
OUT = Path(__file__).resolve().parents[1] / "assets" / "audio" / "sfx"


def envelope(t, duration, attack=0.008, release=0.06):
    if t < 0 or t >= duration:
        return 0.0
    return min(1.0, t / attack) * min(1.0, (duration - t) / release)


def noise(duration, seed, lowpass=0.12):
    rng = random.Random(seed)
    value = 0.0
    data = []
    for _ in range(round(duration * RATE)):
        value += lowpass * (rng.uniform(-1, 1) - value)
        data.append(value)
    return data


def tone(t, frequency, duration, amplitude=1.0):
    return amplitude * envelope(t, duration) * math.exp(-3.0 * max(0, t) / duration) * (
        math.sin(math.tau * frequency * t) + 0.14 * math.sin(math.tau * frequency * 2 * t))


def click(t):
    return 0.6 * tone(t, 820, 0.07) + 0.25 * tone(t - 0.013, 560, 0.055)


def card_play(t, air):
    i = min(len(air) - 1, round(t * RATE))
    sweep = air[i] * envelope(t, 0.24, 0.025, 0.11) * math.sin(math.pi * t / 0.24) ** 2
    # No pitched landing tail: the complete sound is a single paper-like swish.
    return sweep * 1.6


def effect_arrive(t):
    return 0.7 * tone(t, 660, 0.15) + 0.22 * tone(t - 0.025, 990, 0.14)


def turn_settle(t, air):
    i = min(len(air) - 1, round(t * RATE))
    paper = 0.8 * air[i] * envelope(t, 0.19, 0.025, 0.095)
    landing = t - 0.16
    # A short damped contact, rather than a melodic notification or chime.
    contact = 0.0
    if 0 <= landing < 0.075:
        contact = 0.20 * math.sin(math.tau * 105 * landing) * math.exp(-65 * landing) * envelope(landing, 0.075, 0.004, 0.04)
    return paper + contact


def reward(t):
    return sum(tone(t - delay, freq, length, level) for delay, freq, length, level in (
        (0, 523.25, 0.42, 0.55), (0.075, 659.25, 0.43, 0.45), (0.15, 783.99, 0.48, 0.35)))


def alert(t):
    return tone(t, 220, 0.55, 0.6) + tone(t - 0.09, 311.13, 0.46, 0.24)


def victory(t):
    return sum(tone(t - delay, freq, length, level) for delay, freq, length, level in (
        (0, 523.25, 0.45, 0.40), (0.12, 659.25, 0.45, 0.36),
        (0.24, 783.99, 0.55, 0.34), (0.40, 1046.50, 0.72, 0.28)))


def defeat(t):
    return sum(tone(t - delay, freq, length, level) for delay, freq, length, level in (
        (0, 329.63, 0.47, 0.42), (0.17, 261.63, 0.47, 0.35), (0.35, 196, 0.64, 0.30)))


def save(name, duration, sample, peak_db):
    samples = [sample(index / RATE) for index in range(round(duration * RATE))]
    # Remove DC bias, normalize without hard clipping and leave mixing headroom.
    mean = sum(samples) / len(samples)
    samples = [value - mean for value in samples]
    peak = max(abs(value) for value in samples)
    gain = 10 ** (peak_db / 20) / max(peak, 1e-9)
    pcm = []
    for index, value in enumerate(samples):
        fade = min(1.0, index / (RATE * 0.004), (len(samples) - 1 - index) / (RATE * 0.012))
        pcm.append(round(value * gain * max(0, fade) * 32767))
    assert max(abs(value) for value in pcm) < 32767
    with wave.open(str(OUT / name), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(struct.pack("<" + "h" * len(pcm), *pcm))
    print(f"{name}: {duration:.2f}s, peak <= {peak_db} dBFS")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--only", nargs="+", help="Generate only the named WAV files")
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    paper = noise(0.30, 197, 0.22)
    settle = noise(0.54, 821, 0.07)
    definitions = [
        ("ui_click.wav", 0.09, click, -17),
        ("card_play.wav", 0.26, lambda t: card_play(t, paper), -14),
        ("effect_arrive.wav", 0.20, effect_arrive, -18),
        ("turn_settle.wav", 0.27, lambda t: turn_settle(t, settle), -17),
        ("reward_gain.wav", 0.68, reward, -15),
        ("event_alert.wav", 0.60, alert, -16),
        ("victory.wav", 1.18, victory, -13),
        ("defeat.wav", 1.05, defeat, -15),
    ]
    if args.only and set(args.only) - {item[0] for item in definitions}:
        parser.error("Unknown sound name")
    for definition in definitions:
        if not args.only or definition[0] in args.only:
            save(*definition)


if __name__ == "__main__":
    main()
