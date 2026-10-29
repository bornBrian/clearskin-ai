"""Scores a motion ad: music written to the picture plus sound design.

Each ad has a spec in src/sound/<Id>.json, shared with the composition so
picture and sound use the same tempo and beat grid:

  bpm, beats, tail          tempo, length in beats, ring-out in seconds
  bars                      one chord per bar ("Am", "F", "Csus2", "G/B" ...)
  sections                  beat ranges and which layers play, how loud
  cues                      sound effects on beats (impacts, risers, whooshes)

Everything is synthesised here (no samples), so it is ours to use anywhere.

  python sound.py src/sound/Guessing.json out.wav            # music + effects
  python sound.py src/sound/Guessing.json out.wav --sfx-only # effects only
"""

import json
import sys
import wave

import numpy as np
from scipy import signal

SR = 48000
RNG = np.random.default_rng(7)

# ── Basics ────────────────────────────────────────────────────────────

NOTE = {'C': 0, 'C#': 1, 'Db': 1, 'D': 2, 'D#': 3, 'Eb': 3, 'E': 4, 'F': 5, 'F#': 6, 'Gb': 6,
        'G': 7, 'G#': 8, 'Ab': 8, 'A': 9, 'A#': 10, 'Bb': 10, 'B': 11}
QUALITY = {'': [0, 4, 7], 'm': [0, 3, 7], 'sus2': [0, 2, 7], 'sus4': [0, 5, 7], 'add9': [0, 4, 7, 14],
           'madd9': [0, 3, 7, 14], 'maj7': [0, 4, 7, 11], 'm7': [0, 3, 7, 10]}


def chord(name):
    """'F#m7' -> (root pitch class, intervals); 'G/B' uses B as the bass."""
    name, _, bass = name.partition('/')
    root = name[:2] if len(name) > 1 and name[1] in '#b' else name[:1]
    return NOTE[root], QUALITY[name[len(root):]], NOTE[bass] if bass else None


def hz(midi):
    return 440.0 * 2 ** ((np.asarray(midi, dtype=float) - 69) / 12)


def tt(n):
    return np.arange(n) / SR


def noise(n):
    return RNG.standard_normal(n)


def saw(freq, n, phase=0.0):
    """Band-limited (polyBLEP) sawtooth; [freq] may vary per sample."""
    inc = np.broadcast_to(np.asarray(freq, dtype=float) / SR, (n,))
    ph = (phase + np.cumsum(inc)) % 1.0
    y = 2 * ph - 1
    m = ph < inc
    x = ph[m] / inc[m]
    y[m] -= x + x - x * x - 1
    m = ph > 1 - inc
    x = (ph[m] - 1) / inc[m]
    y[m] -= x * x + x + x + 1
    return y


def sine(freq, n, phase=0.0):
    inc = np.broadcast_to(np.asarray(freq, dtype=float) / SR, (n,))
    return np.sin(2 * np.pi * (phase + np.cumsum(inc)))


def lp(x, f, order=2):
    return signal.sosfilt(signal.butter(order, min(f, SR / 2 - 100), 'low', fs=SR, output='sos'), x, axis=0)


def hp(x, f, order=2):
    return signal.sosfilt(signal.butter(order, f, 'high', fs=SR, output='sos'), x, axis=0)


def bp(x, lo, hi, order=2):
    return signal.sosfilt(signal.butter(order, [lo, min(hi, SR / 2 - 100)], 'band', fs=SR, output='sos'), x, axis=0)


def sweep_filter(x, cutoff, kind='low', block=256):
    """Filter whose cutoff follows the per-sample curve [cutoff] (mono or stereo)."""
    x = np.atleast_2d(x.T).T
    out = np.zeros_like(x)
    zi = None
    for i in range(0, len(x), block):
        c = float(np.clip(cutoff[min(i, len(cutoff) - 1)], 30, SR / 2 - 200))
        if kind == 'band':
            sos = signal.butter(2, [c / 1.6, min(c * 1.6, SR / 2 - 100)], 'band', fs=SR, output='sos')
        else:
            sos = signal.butter(2, c, kind, fs=SR, output='sos')
        if zi is None:
            zi = np.zeros((sos.shape[0], 2, x.shape[1]))
        out[i:i + block], zi = signal.sosfilt(sos, x[i:i + block], axis=0, zi=zi)
    return out


def stereo(x, pan=0.0):
    """Mono -> stereo with constant-power pan (-1 left .. 1 right); pan may vary per sample."""
    a = (np.asarray(pan) + 1) * np.pi / 4
    return np.stack([x * np.cos(a), x * np.sin(a)], axis=1)


def env(n, a, d, s, r, hold=None):
    """ADSR in seconds; [hold] is when release starts (default: n - r)."""
    t = tt(n)
    hold = (n / SR - r) if hold is None else hold
    e = np.where(t < a, t / max(a, 1e-4), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-4)))
    rel = np.clip((t - hold) / max(r, 1e-4), 0, 1)
    return e * (1 - rel) ** 2


def place(bus, x, at):
    """Adds stereo clip [x] to [bus] starting at second [at] (clipped to the bus)."""
    i = int(round(at * SR))
    if i < 0:
        x, i = x[-i:], 0
    j = min(len(bus), i + len(x))
    if j > i:
        bus[i:j] += x[:j - i]


def reverb_ir(seconds=2.6, damp=5000, pre=0.012):
    n = int(seconds * SR)
    t = tt(n)
    decay = np.exp(-6.91 * t / seconds)
    ir = np.stack([lp(noise(n), damp) * decay, lp(noise(n), damp) * decay], axis=1)
    # darker as it decays, like a real room
    ir = ir * (0.35 + 0.65 * np.exp(-t / 0.5))[:, None] + lp(ir, 1800) * (1 - np.exp(-t / 0.5))[:, None]
    ir[: int(pre * SR)] = 0
    for k, (dl, g) in enumerate([(0.017, 0.5), (0.023, 0.42), (0.031, 0.35), (0.041, 0.3)]):
        ir[int((pre + dl) * SR), k % 2] += g
    return ir / np.sqrt((ir ** 2).sum(axis=0)).max()


IR = reverb_ir()
IR_LONG = reverb_ir(4.5, 4000, 0.02)


def verb(x, ir=IR):
    return np.stack([signal.fftconvolve(x[:, c], ir[:, c])[: len(x)] for c in range(2)], axis=1)


def delay(x, seconds, feedback=0.4, taps=5, pingpong=True):
    out = x.copy()
    d = int(seconds * SR)
    for k in range(1, taps + 1):
        shifted = np.zeros_like(x)
        shifted[k * d:] = x[: len(x) - k * d] * feedback ** k
        if pingpong and k % 2:
            shifted = shifted[:, ::-1]
        out += lp(shifted, 5000 - 500 * k)
    return out


# ── Instruments ───────────────────────────────────────────────────────

def supersaw_note(midi, n, voices=5, detune=0.14):
    out = np.zeros((n, 2))
    for v in range(voices):
        off = (v - (voices - 1) / 2) / ((voices - 1) / 2)
        f = hz(midi + off * detune)
        out += stereo(saw(f, n, RNG.random()), off * 0.8)
    return out / voices


def kick(punch=1.0):
    n = int(0.55 * SR)
    t = tt(n)
    f = 52 + 130 * np.exp(-t / 0.03) * punch
    body = sine(f, n) * np.exp(-t / 0.2)
    click = hp(noise(n), 2500) * np.exp(-t / 0.005) * 0.6 + bp(noise(n), 900, 3000) * np.exp(-t / 0.012) * 0.25
    return stereo(np.tanh(1.6 * (body + click)) * 0.9)


def clap():
    n = int(0.5 * SR)
    t = tt(n)
    e = sum(np.exp(-np.clip(t - d, 0, None) / 0.012) * (t >= d) for d in (0, 0.011, 0.022)) / 3
    e += np.exp(-np.clip(t - 0.03, 0, None) / 0.13) * (t >= 0.03) * 0.6
    x = bp(noise(n), 900, 2600) * e
    return stereo(x * 0.9) + verb(stereo(x * 0.4))


def hat(open_=False):
    n = int((0.25 if open_ else 0.06) * SR)
    t = tt(n)
    x = hp(noise(n), 6500, 4) * np.exp(-t / (0.09 if open_ else 0.02))
    return stereo(x * 0.9, 0.25)


def pluck(midi, length=0.4):
    n = int(length * SR)
    t = tt(n)
    f = hz(midi)
    x = (sine(f, n) + 0.35 * sine(2 * f, n) + 0.12 * saw(f, n)) * np.exp(-t / 0.16)
    x *= np.clip(t / 0.003, 0, 1)
    return lp(x, 4200)


def bass_note(midi, n):
    t = tt(n)
    f = hz(midi)
    # sine for weight, filtered saw so phone speakers hear the notes
    x = 0.8 * sine(f, n) + 0.55 * lp(saw(f, n), 900)
    x = np.tanh(1.4 * x) * env(n, 0.006, 0.12, 0.75, 0.05)
    return stereo(x)


# ── Sound effects ─────────────────────────────────────────────────────

def sfx_impact(big=1.0):
    n = int(3.2 * SR)
    t = tt(n)
    boom = sine(38 + 80 * np.exp(-t / 0.08), n) * np.exp(-t / (0.55 * big))
    crack = bp(noise(n), 400, 9000) * np.exp(-t / 0.06)
    body = bp(noise(n), 120, 900) * np.exp(-t / 0.35) * 0.7
    dry = stereo(np.tanh(1.3 * (boom * 0.8 + crack * 0.8 + body)))
    return dry + verb(stereo(crack * 0.6 + body * 0.5), IR_LONG) * 0.9


def sfx_hit():
    n = int(1.0 * SR)
    t = tt(n)
    tone = sine(90 + 140 * np.exp(-t / 0.03), n) * np.exp(-t / 0.18)
    snap = bp(noise(n), 1500, 7000) * np.exp(-t / 0.025)
    x = stereo(np.tanh(1.5 * (tone + 0.5 * snap)))
    return x + verb(stereo(snap * 0.3)) * 0.8


def sfx_whoosh(seconds=0.7, up=True, pan_from=-0.7, pan_to=0.7):
    n = int(seconds * SR)
    t = tt(n) / seconds
    shape = np.sin(np.pi * np.clip(t, 0, 1)) ** 3
    f = 350 * (12 ** (t if up else 1 - t))
    x = sweep_filter(noise(n), f * 1.0, 'band')[:, 0] * shape
    x += sweep_filter(noise(n), f * 2.2, 'band')[:, 0] * shape * 0.5
    return stereo(x * 1.6, pan_from + (pan_to - pan_from) * t)


def sfx_riser(seconds):
    n = int(seconds * SR)
    t = tt(n) / seconds
    amp = t ** 2.2
    nz = sweep_filter(noise(n), 300 * 30 ** t, 'band')[:, 0]
    tone = sum(saw(hz(57 + 24 * t ** 1.5) * m, n) for m in (1, 1.005, 0.995)) / 3
    x = (nz * 1.2 + lp(tone, 3000) * 0.35) * amp
    return stereo(x) + verb(stereo(x * 0.3)) * 0.5


def sfx_swell(seconds):
    """A reversed reverb tail: sucks in towards the beat."""
    n = int(seconds * SR)
    src = np.zeros((n, 2))
    src[:200] = stereo(noise(200) * 0.6)
    tail = verb(src + stereo(lp(noise(n), 3000) * np.exp(-tt(n) / 0.05) * 0.4), IR_LONG)
    return tail[::-1] * 1.4


def sfx_sub(seconds=1.4):
    n = int(seconds * SR)
    t = tt(n)
    return stereo(np.tanh(1.2 * sine(85 * np.exp(-t / 0.5) + 26, n) * np.exp(-t / (seconds / 2.5))))


def sfx_tick():
    n = int(0.12 * SR)
    t = tt(n)
    x = (sine(2900, n) + 0.4 * sine(5800, n)) * np.exp(-t / 0.012)
    return stereo(x * 0.5) + verb(stereo(x * 0.12))


def sfx_pop():
    n = int(0.25 * SR)
    t = tt(n)
    x = sine(500 + 900 * (1 - np.exp(-t / 0.02)), n) * np.exp(-t / 0.05)
    return stereo(x * 0.55) + verb(stereo(x * 0.15))


def sfx_ding():
    n = int(2.0 * SR)
    t = tt(n)
    x = sum(sine(f, n) * np.exp(-t / 0.5) * np.clip((t - d) * 1e9, 0, 1) for f, d in ((1318.5, 0), (1661.2, 0.07)))
    return stereo(x * 0.3) + verb(stereo(x * 0.2))


def sfx_buzz():
    n = int(0.45 * SR)
    t = tt(n)
    sq = np.sign(sine(110, n)) * 0.5 + np.sign(sine(116.5, n)) * 0.5
    x = lp(sq, 1800) * env(n, 0.005, 0.1, 0.7, 0.08) * (0.7 + 0.3 * (np.sin(2 * np.pi * 18 * t) > 0))
    return stereo(x * 0.45) + verb(stereo(x * 0.1))


def sfx_glitch():
    n = int(0.35 * SR)
    out = np.zeros(n)
    for _ in range(9):
        a = RNG.integers(0, n - 2000)
        ln = RNG.integers(400, 2500)
        out[a:a + ln] += np.sign(sine(RNG.uniform(200, 2400), ln)) * RNG.uniform(0.2, 0.5)
    return stereo(hp(out, 150), 0) * 0.6


def sfx_shimmer(seconds=2.0, root=81):
    n = int(seconds * SR)
    out = np.zeros((n, 2))
    for k, m in enumerate([0, 7, 12, 16, 19, 24, 28]):
        d = k * 0.045
        x = pluck(root + m, seconds - d) * 0.25
        place(out, stereo(x, RNG.uniform(-0.8, 0.8)), d)
    return out + verb(out, IR_LONG) * 0.8


def sfx_snap():
    """A camera-shutter style snap for the scan."""
    n = int(0.3 * SR)
    t = tt(n)
    x = bp(noise(n), 2000, 9000) * (np.exp(-t / 0.006) + 0.6 * np.exp(-np.clip(t - 0.06, 0, None) / 0.01) * (t > 0.06))
    return stereo(x * 0.8) + verb(stereo(x * 0.2))


SFX = {
    'impact': lambda c: sfx_impact(c.get('big', 1.0)),
    'hit': lambda c: sfx_hit(),
    'whoosh': lambda c: sfx_whoosh(c.get('seconds', 0.7), c.get('up', True), *c.get('pan', [-0.7, 0.7])),
    'riser': lambda c: sfx_riser(c['seconds']),
    'swell': lambda c: sfx_swell(c['seconds']),
    'sub': lambda c: sfx_sub(),
    'tick': lambda c: sfx_tick(),
    'pop': lambda c: sfx_pop(),
    'ding': lambda c: sfx_ding(),
    'buzz': lambda c: sfx_buzz(),
    'glitch': lambda c: sfx_glitch(),
    'shimmer': lambda c: sfx_shimmer(),
    'snap': lambda c: sfx_snap(),
}
# Effects whose peak sits at the end or middle, not the start.
ALIGN = {'riser': 'end', 'swell': 'end', 'whoosh': 'mid'}


# ── Score ─────────────────────────────────────────────────────────────

def section_curve(spec, key, n_beats, beat, default=0.0):
    """Per-sample value of section field [key]: a number, or [from, to] ramped over the section."""
    out = np.full(int(n_beats * beat * SR), default, dtype=float)
    for s in spec['sections']:
        a, b = int(s['from'] * beat * SR), int(s['to'] * beat * SR)
        v = s.get(key, default)
        ramp = np.linspace(v[0], v[1], max(b - a, 1)) if isinstance(v, list) else np.full(max(b - a, 1), v)
        b = min(b, len(out))
        if b > a:
            out[a:b] = ramp[: b - a]
    return out


def score(spec):
    bpm = spec['bpm']
    beat = 60 / bpm
    n_beats = spec['beats']
    total = int((n_beats * beat + spec.get('tail', 2.5)) * SR)
    music = {k: np.zeros((total, 2)) for k in ('pad', 'pluck', 'bass', 'drums')}
    level = {k: section_curve(spec, k, n_beats, beat) for k in ('pad', 'pluck', 'bass', 'kick', 'hat', 'clap')}
    cutoff = section_curve(spec, 'cutoff', n_beats, beat, 1200)

    def lvl(k, at):
        i = int(at * SR)
        return level[k][i] if i < len(level[k]) else 0.0

    bars = spec['bars']
    base = spec.get('octave', 48)
    kicks = []
    for bar, name in enumerate(bars):
        root, ivs, bass_pc = chord(name)
        t0 = bar * 4 * beat
        if t0 >= n_beats * beat:
            break
        r = base + (root - base) % 12
        # pad: open voicing, held for the bar with a soft overlap
        n = int((4 * beat + 0.9) * SR)
        voicing = [r, r + 7, r + 12 + ivs[1], r + 12 + ivs[2], r + 24 + (ivs[3] - 12 if len(ivs) > 3 else 0)]
        pad = sum(supersaw_note(m, n) for m in voicing) / len(voicing)
        pad *= env(n, 0.25, 0.6, 0.85, 0.8, hold=4 * beat)[:, None]
        g = lvl('pad', t0 + 0.01)
        if g:
            place(music['pad'], pad * g, t0)
        # bass: root on 8ths, a little rest before each note
        bm = 36 + ((bass_pc if bass_pc is not None else root) - 36) % 12
        for k in range(8):
            at = t0 + k * beat / 2
            g = lvl('bass', at)
            if g:
                place(music['bass'], bass_note(bm, int(beat / 2 * 0.86 * SR)) * g, at)
        # pluck arpeggio on 16ths
        tones = [r + 24 + i for i in ivs[:3]] + [r + 36]
        pattern = [0, 1, 2, 3, 2, 1, 2, 3]
        for k in range(16):
            at = t0 + k * beat / 4
            g = lvl('pluck', at)
            if g:
                p = pluck(tones[pattern[k % 8]]) * (0.9 if k % 4 == 0 else 0.6) * g
                place(music['pluck'], stereo(p, 0.35 * np.sin(k)), at)
        # drums
        for k in range(4):
            at = t0 + k * beat
            if lvl('kick', at):
                place(music['drums'], kick() * lvl('kick', at), at)
                kicks.append(at)
            if lvl('clap', at) and k % 2 == 1:
                place(music['drums'], clap() * 0.55 * lvl('clap', at), at)
            for h in (0.5,) if lvl('hat', at) < 0.6 else (0.25, 0.5, 0.75):
                ah = at + h * beat
                if lvl('hat', ah):
                    place(music['drums'], hat(open_=h == 0.5) * 0.5 * lvl('hat', ah), ah)

    # Sidechain: pad and bass breathe with the kick.
    duck = np.ones(total)
    t = tt(total)
    for k in kicks:
        i = int(k * SR)
        seg = t[i:] - k
        duck[i:] = np.minimum(duck[i:], 1 - 0.55 * np.exp(-seg / 0.11))

    pad = sweep_filter(music['pad'], np.concatenate([cutoff, np.full(total - len(cutoff), cutoff[-1])]), 'low')
    pad = pad * duck[:, None] ** 0.7
    pluck_bus = delay(music['pluck'], beat * 0.75, 0.35)
    bass = music['bass'] * duck[:, None]
    mix = pad * 0.6 + bass * 0.38 + music['drums'] * 0.75 + pluck_bus * 0.55
    mix += verb(pad * 0.35 + pluck_bus * 0.3 + music['drums'] * 0.06) * 0.6
    # gaps: silence the music for a breath before a drop
    for a, b in spec.get('gaps', []):
        i, j = int(a * beat * SR), int(b * beat * SR)
        fade = np.ones(total)
        fade[i:j] = 0
        mix *= signal.savgol_filter(fade, 481, 1)[:, None].clip(0, 1)
    # the music ends with the last bar; let it ring
    end = int(n_beats * beat * SR)
    mix[end:] *= np.exp(-tt(total - end) / 0.6)[:, None]
    return mix, beat, total


def effects(spec, beat, total):
    bus = np.zeros((total, 2))
    for c in spec['cues']:
        clip = SFX[c['sfx']](c)
        at = c['beat'] * beat
        if ALIGN.get(c['sfx']) == 'end':
            at -= len(clip) / SR
        elif ALIGN.get(c['sfx']) == 'mid':
            at -= len(clip) / SR / 2
        place(bus, clip * 10 ** (c.get('gain', 0) / 20), at)
    return bus


def limit(x, ceiling=0.89):
    """Look-ahead peak limiter."""
    from scipy.ndimage import minimum_filter1d, uniform_filter1d
    win = int(0.008 * SR)
    gain = np.minimum(1, ceiling / np.maximum(np.abs(x).max(axis=1), 1e-9))
    # hold the lowest gain around each peak, then smooth inside that hold
    gain = uniform_filter1d(minimum_filter1d(gain, 2 * win + 1), win)
    gain = uniform_filter1d(minimum_filter1d(gain, 2 * win + 1), win)
    return x * gain[:, None]


def main():
    spec = json.load(open(sys.argv[1], encoding='utf-8'))
    out = sys.argv[2]
    sfx_only = '--sfx-only' in sys.argv
    music, beat, total = score(spec)
    sfx = effects(spec, beat, total)
    music *= 10 ** (spec.get('music_gain', -3) / 20)
    mix = sfx if sfx_only else music + sfx
    mix = hp(mix, 32)
    # gentle presence and air, so it reads on phone speakers
    mix = mix + 0.35 * hp(mix, 2800) + 0.25 * bp(mix, 900, 2500)
    mix = limit(mix / max(np.abs(mix).max(), 1e-9) * 1.25)
    pcm = (np.clip(mix, -1, 1) * 32767).astype('<i2')
    with wave.open(out, 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    rms = np.sqrt((mix ** 2).mean())
    print(f'{out}: {total / SR:.1f}s, peak {np.abs(mix).max():.2f}, rms {20 * np.log10(rms):.1f} dBFS')


if __name__ == '__main__':
    main()
