"""Where a finger is on each plate's phone screen, frame by frame.

Works in the screen's own space: each frame is warped flat (390×844, the
recorded app's size) through the tracked screen corners, and a finger is
skin-coloured pixels lying in front of the screen's key colour. A finger
enters from an edge, so its tip is the point of that shape farthest from
where it crosses the edge. (A hand model struggles on keyed footage; the
key colour itself says exactly what is in front of the glass.)

  python fingers.py src/plates.json [name ...]

Writes public/plates/<name>.fingers.json: {"frames": [null | {"u", "v",
"area"}]} with u across and v down the display, 0..1. touch.py turns these
into the scrolls and taps the app recording replays.
"""

import json
import sys
from pathlib import Path

import cv2
import numpy as np

from screen_comp import OUT, screen_mask, track_plate

SW, SH = 390, 844  # the recorded app's logical size


def flat(frame, quad):
    """The screen, warped flat to SW×SH."""
    M = cv2.getPerspectiveTransform(quad.astype(np.float32), np.float32([[0, 0], [SW, 0], [SW, SH], [0, SH]]))
    return cv2.warpPerspective(frame, M, (SW, SH), flags=cv2.INTER_AREA)


def fingertip(screen, kind):
    """The tip of the biggest finger over the screen, or None."""
    hsv = cv2.cvtColor(screen, cv2.COLOR_BGR2HSV)
    key = screen_mask(hsv, kind).astype(bool)
    b, g, r = (screen[..., i].astype(int) for i in range(3))
    skin = (r > 90) & (r > g) & (r > b) & (r - np.minimum(g, b) > 12)
    m = (skin & ~key).astype(np.uint8)
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))
    n, lab, stats, _ = cv2.connectedComponentsWithStats(m, 8)
    best = None
    for i in range(1, n):
        a = stats[i][4]
        if a < 500:
            continue
        comp = lab == i
        # where it crosses the screen's edge (a finger comes in from outside)
        edge = np.zeros_like(comp)
        edge[:4, :] = edge[-4:, :] = True
        edge[:, :4] = edge[:, -4:] = True
        ey, ex = np.nonzero(comp & edge)
        if len(ex) < 3:
            continue
        cy, cx = np.nonzero(comp)
        d = (cx - ex.mean()) ** 2 + (cy - ey.mean()) ** 2
        k = int(np.argmax(d))
        if best is None or a > best['area']:
            best = {'u': round(cx[k] / SW, 4), 'v': round(cy[k] / SH, 4), 'area': int(a)}
    return best


def main():
    specs = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
    for name in sys.argv[2:] or list(specs):
        p = specs[name]
        raw, quads, _ = track_plate(name, p)
        out = [fingertip(flat(f, quads[i]), p['screen']) for i, f in enumerate(raw)]
        path = OUT / f'{name}.fingers.json'
        path.write_text(json.dumps({'frames': out}), encoding='utf-8')
        print(f'{path}: {len(out)} frames, a finger on the screen in {sum(1 for t in out if t)}')


if __name__ == '__main__':
    main()
