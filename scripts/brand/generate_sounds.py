"""Generates ClearSkin's notification sounds, one per kind of moment.

    python scripts/brand/generate_sounds.py

Like fitness apps, each moment has its own sound so people know what it is
before they look: bright to start the day, calm at night, a friendly nudge
when a streak is at risk, a small celebration for milestones, and a neutral
chime for everything else. All synthesised from scratch (no licensing),
mono 44.1 kHz WAV, written to android/app/src/main/res/raw/ and ios/Runner/.

Each note is a marimba-like voice: a sine body with a soft attack and a
natural exponential decay, plus a quiet overtone that only lives for the
strike. Intervals are major/perfect (fifths, thirds, octaves): they sound
resolved and pleasant, never alarming.
"""

import math
import struct
import wave
from pathlib import Path

RATE = 44100

C5, E5, G5 = 523.25, 659.26, 783.99
A5, C6, E6, G6 = 880.00, 1046.50, 1318.51, 1567.98
C7 = 2093.00


def voice(t, freq, *, attack=0.006, decay=0.42, strike=0.18, octave=0.07):
    if t < 0:
        return 0.0
    a = min(1.0, t / attack)
    body = math.exp(-t / decay) * math.sin(2 * math.pi * freq * t)
    hit = strike * math.exp(-t / 0.05) * math.sin(2 * math.pi * freq * 3.98 * t)
    octv = octave * math.exp(-t / 0.25) * math.sin(2 * math.pi * freq * 2 * t)
    return a * (body + hit + octv)


def sparkle(t):
    """A short, high shimmer for celebrations: two detuned partials with a
    quick tremolo, gone in under half a second."""
    if t < 0:
        return 0.0
    env = math.exp(-t / 0.18) * min(1.0, t / 0.01)
    trem = 0.6 + 0.4 * math.sin(2 * math.pi * 14 * t)
    return 0.12 * env * trem * (
        math.sin(2 * math.pi * 4186.0 * t) + math.sin(2 * math.pi * 4199.0 * t)
    )


SOUNDS = {
    # Neutral two-note chime: scan day, UV, come-back, renewal, expiry.
    "clearskin_chime": dict(
        length=1.45,
        peak=0.5,
        notes=[(0.00, C6, 0.85, {}), (0.12, G6, 1.0, {})],
    ),
    # Sunrise: three quick rising notes, bright, the last one rings.
    "clearskin_morning": dict(
        length=1.3,
        peak=0.5,
        notes=[
            (0.00, C6, 0.75, dict(decay=0.25, strike=0.22)),
            (0.09, E6, 0.85, dict(decay=0.25, strike=0.22)),
            (0.18, G6, 1.0, dict(decay=0.45, strike=0.22)),
        ],
    ),
    # Lullaby: two soft falling notes, slow attack, long and quiet.
    "clearskin_evening": dict(
        length=2.0,
        peak=0.36,
        notes=[
            (0.00, E5, 0.9, dict(attack=0.03, decay=0.75, strike=0.04, octave=0.1)),
            (0.24, C5, 1.0, dict(attack=0.03, decay=0.9, strike=0.04, octave=0.1)),
        ],
    ),
    # Streak at risk: "da-da-DING", noticeable without being an alarm.
    "clearskin_streak": dict(
        length=1.25,
        peak=0.55,
        notes=[
            (0.00, A5, 0.7, dict(decay=0.12, strike=0.25)),
            (0.12, A5, 0.75, dict(decay=0.12, strike=0.25)),
            (0.26, E6, 1.0, dict(decay=0.4, strike=0.22)),
        ],
    ),
    # Milestone: a rising run, a sparkle, and a warm chord underneath.
    "clearskin_milestone": dict(
        length=2.2,
        peak=0.5,
        notes=[
            (0.00, C6, 0.6, dict(decay=0.2)),
            (0.07, E6, 0.65, dict(decay=0.2)),
            (0.14, G6, 0.7, dict(decay=0.25)),
            (0.21, C7, 0.85, dict(decay=0.6)),
            # The chord pad: soft, slow, under the run.
            (0.20, C5, 0.25, dict(attack=0.05, decay=1.0, strike=0, octave=0)),
            (0.20, E5, 0.22, dict(attack=0.05, decay=1.0, strike=0, octave=0)),
            (0.20, G5, 0.22, dict(attack=0.05, decay=1.0, strike=0, octave=0)),
        ],
        sparkle_at=0.21,
    ),
}


def render(spec):
    n = int(RATE * spec["length"])
    out = []
    for i in range(n):
        t = i / RATE
        s = sum(amp * voice(t - start, f, **kw) for start, f, amp, kw in spec["notes"])
        if "sparkle_at" in spec:
            s += sparkle(t - spec["sparkle_at"])
        tail = spec["length"] - t
        if tail < 0.15:  # fade out so it never clicks
            s *= tail / 0.15
        out.append(s)
    peak = max(abs(x) for x in out)
    return [x * spec["peak"] / peak for x in out]


def write(path, samples):
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(
            b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32767)) for s in samples)
        )


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[2]
    for name, spec in SOUNDS.items():
        samples = render(spec)
        for folder in ["android/app/src/main/res/raw", "ios/Runner"]:
            target = root / folder / f"{name}.wav"
            write(target, samples)
        print(f"{name}: {spec['length']} s, {target.stat().st_size // 1024} KB")
