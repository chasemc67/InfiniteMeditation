#!/usr/bin/env python3
"""Synthesize the singing-bowl chimes bundled with the iPhone app.

The sounds are generated from scratch with additive synthesis (no samples,
no third-party code), so they carry no licensing obligations. Re-run this
script to regenerate them byte-for-byte:

    python3 Tools/generate_chimes.py

Model: a struck metal bowl rings at a handful of inharmonic modes. Each mode
is rendered as two slightly detuned sine waves so it "beats" the way a real
bowl shimmers, with an exponential decay that is longer for low modes. A soft
mallet attack (a few ms) avoids clicks.
"""

import math
import struct
import wave
from pathlib import Path

SAMPLE_RATE = 44100
PEAK = 0.70  # about -3 dBFS

# (frequency ratio to fundamental, relative amplitude, T60 decay seconds, beat Hz)
BOWL_MODES = [
    (1.00, 1.00, 1.00, 0.55),
    (2.71, 0.42, 0.62, 1.30),
    (5.12, 0.18, 0.36, 2.10),
    (8.21, 0.07, 0.20, 2.90),
]


def render(fundamental, duration, decay_scale, attack_ms, fade_ms=600):
    n = int(duration * SAMPLE_RATE)
    attack = max(1, int(attack_ms / 1000 * SAMPLE_RATE))
    fade = int(fade_ms / 1000 * SAMPLE_RATE)
    out = [0.0] * n
    for ratio, amp, t60_fraction, beat in BOWL_MODES:
        freq = fundamental * ratio
        t60 = decay_scale * t60_fraction
        k = math.log(1000.0) / t60  # amplitude falls 60 dB over t60 seconds
        w1 = 2 * math.pi * (freq - beat / 2) / SAMPLE_RATE
        w2 = 2 * math.pi * (freq + beat / 2) / SAMPLE_RATE
        phase = ratio * 0.9  # fixed per-mode phase offsets keep output deterministic
        for i in range(n):
            env = amp * math.exp(-k * i / SAMPLE_RATE)
            if env < 1e-5:
                break
            out[i] += env * 0.5 * (math.sin(w1 * i + phase) + math.sin(w2 * i))
    for i in range(min(attack, n)):
        out[i] *= 0.5 - 0.5 * math.cos(math.pi * i / attack)
    for j in range(min(fade, n)):
        idx = n - 1 - j
        out[idx] *= j / fade
    peak = max(abs(s) for s in out) or 1.0
    return [s / peak * PEAK for s in out]


def write_wav(path, samples):
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)
        frames = b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples
        )
        wav.writeframes(frames)


def main():
    out_dir = Path(__file__).resolve().parent.parent / "InfiniteMeditation" / "Sounds"
    # Regular mark: a small, bright bowl (around G4) with a medium ring.
    write_wav(out_dir / "chime_minor.wav", render(392.0, 7.0, 7.0, attack_ms=6))
    # Major mark: a larger, deeper bowl (around C4) that rings noticeably longer.
    write_wav(out_dir / "chime_major.wav", render(261.6, 11.0, 12.0, attack_ms=10))
    print(f"Wrote chimes to {out_dir}")


if __name__ == "__main__":
    main()
