"""Turns a plate's finger track (fingers.py) into the touches the app
recording replays, so the screen moves with the finger in the footage.

A finger moving up the glass is a swipe: it goes down where the swipe
starts, follows the finger, and lifts when the finger stops climbing or
leaves the glass. The harness replays these as real touch gestures, so the
app scrolls, flings and stretches at the end of a list with its own physics.
A finger moving back down is a thumb returning for the next swipe, so it
isn't touching. No finger, no touch.

  python touch.py src/plates.json name ...

Writes marketing/ads/source/rec2/touch/<name>.json: {"screen": <flow>,
"touch": [null | [x, y] in logical px, per plate frame]} for the screenshot
harness's "follow" recordings.
"""

import json
import sys
from pathlib import Path

import numpy as np

from screen_comp import OUT, SRC

SW, SH = 390, 844
DRAG = -0.003  # v per frame: slower than this up the glass is a resting finger
JUMP = 0.08  # v per frame: faster than this is the tracker jumping, not a finger
EDGE = 0.03  # a tip this close to the screen's edge is a finger crossing it
NAV = 0.9  # below this the bottom navigation bar, which doesn't scroll: a
# swipe takes hold once the finger is over the page


def touches(track):
    def on_glass(t):
        return t and EDGE < t['u'] < 1 - EDGE and EDGE < t['v'] < 1 - EDGE

    pts = [(t['u'] * SW, t['v'] * SH) if on_glass(t) else None for t in track]
    # a light 3-frame median on the finger
    sm = []
    for i in range(len(pts)):
        w = [p for p in pts[max(0, i - 1): i + 2] if p]
        sm.append((float(np.median([p[0] for p in w])), float(np.median([p[1] for p in w]))) if pts[i] and w else None)
    out, down, still = [], False, 0
    for i, p in enumerate(sm):
        prev = sm[i - 1] if i else None
        dv = (p[1] - prev[1]) / SH if p and prev else None
        climbing = dv is not None and -JUMP < dv < DRAG
        if climbing and (down or p[1] / SH < NAV):
            down, still = True, 0
        elif down:
            still += 1
            if p is None or still >= 2 or (dv is not None and dv > -DRAG):
                down = False
        out.append([round(p[0], 1), round(p[1], 1)] if down and p else None)
    # a gap of a frame or two inside a swipe is the tracker blinking, and a
    # swipe of a few frames is a resting finger's jitter
    for i in range(1, len(out) - 2):
        if out[i] is None and out[i - 1] and (out[i + 1] or out[i + 2]):
            out[i] = out[i - 1]
    i = 0
    while i < len(out):
        if out[i]:
            j = i
            while j < len(out) and out[j]:
                j += 1
            if j - i < 5:
                out[i:j] = [None] * (j - i)
            i = j
        else:
            i += 1
    return out


def main():
    specs = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
    dest = SRC / 'rec2' / 'touch'
    dest.mkdir(parents=True, exist_ok=True)
    for name in sys.argv[2:]:
        track = json.loads((OUT / f'{name}.fingers.json').read_text(encoding='utf-8'))['frames']
        t = touches(track)
        screen = specs[name]['follow']
        (dest / f'{name}.json').write_text(json.dumps({'screen': screen, 'touch': t}), encoding='utf-8')
        strokes = sum(1 for i, x in enumerate(t) if x and not (i and t[i - 1]))
        print(f'{name}: {screen}, {len(t)} frames, {strokes} swipes, finger down {sum(1 for x in t if x)} frames')


if __name__ == '__main__':
    main()
