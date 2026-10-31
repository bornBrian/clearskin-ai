"""Puts the real app on real phones: screen replacement for ad 14.

Each plate is a stock clip of a hand holding (or a desk holding) a phone with
a blue or green screen. For every frame this finds the screen, fits its four
edges (extended through the rounded corners, so the picture reaches into
them like a real display), warps a recorded app flow onto it and keeps
anything in front of the screen (a thumb, a tapping finger, the notch) in
front. The original screen's brightness falloff is carried onto the app, so
it picks up the clip's own lighting. Green backdrops are keyed out and
replaced with a brand colour.

  python screen_comp.py src/plates.json [name ...]

Reads plate specs from the JSON (see src/plates.json); writes
public/plates/<name>.mp4 at 1080×1920, 30 fps.
"""

import json
import subprocess
import sys
from pathlib import Path

import cv2
import numpy as np

HERE = Path(__file__).parent
ROOT = HERE.parents[2]
SRC = ROOT / 'marketing/ads/source'
OUT = HERE / 'public/plates'
W, H, FPS = 1080, 1920, 30

# Hue bands (OpenCV 0..180) of a keying blue and a keying green.
SCREEN = {'blue': ((95, 135), 90, 50), 'green': ((38, 88), 70, 60)}


def frames(path, ss, dur, speed):
    """Source frames at 30 fps output timing, starting at [ss] s, played at [speed]."""
    cap = cv2.VideoCapture(str(path))
    fps = cap.get(cv2.CAP_PROP_FPS)
    n_out = round(dur * FPS)
    want = [ss + i / FPS * speed for i in range(n_out)]
    cap.set(cv2.CAP_PROP_POS_MSEC, ss * 1000)
    idx = int(round(ss * fps))
    cur = None
    out = []
    for t in want:
        target = int(round(t * fps))
        while idx <= target or cur is None:
            ok, f = cap.read()
            if not ok:
                break
            cur = f
            idx += 1
        out.append(cur)
    return out


def crop916(img, x, zoom, y=0.5):
    """A 9:16 window [zoom] times the frame height, positioned by [x] and [y]
    (0..1). Below zoom 1 the window is taller than the frame: the frame keeps
    its bottom edge (so a wrist still leaves the picture) and the space above
    is filled with the backdrop's colour, keyed out later."""
    h, w = img.shape[:2]
    ch = h / zoom
    cw = min(ch * 9 / 16, w)
    x0 = (w - cw) * x
    y0 = (h - ch) * (1.0 if zoom < 1 else y)
    s = W / cw
    M = np.float32([[s, 0, -x0 * s], [0, H / ch, -y0 * H / ch]])
    fill = tuple(int(c) for c in np.median(img[:8].reshape(-1, 3), axis=0))
    return cv2.warpAffine(img, M, (W, H), flags=cv2.INTER_AREA, borderMode=cv2.BORDER_CONSTANT, borderValue=fill)


def screen_mask(hsv, kind):
    (lo, hi), smin, vmin = SCREEN[kind]
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    return ((h >= lo) & (h <= hi) & (s >= smin) & (v >= vmin)).astype(np.uint8)


def key_backdrop(bgr):
    """Alpha of the foreground over a green backdrop (1 = keep), and the despilled frame."""
    f = bgr.astype(np.float32)
    b, g, r = f[..., 0], f[..., 1], f[..., 2]
    d = g - np.maximum(r, b)
    alpha = np.clip(1 - (d - 18) / 40, 0, 1)
    alpha = cv2.GaussianBlur(alpha, (0, 0), 1.2)
    g2 = np.minimum(g, np.maximum(r, b) + 6)
    return alpha, np.dstack([b, g2, r])


def find_screen(bgr, kind, backdrop, occluders=True):
    """Screen matte (0..1) and its four corners (TL, TR, BR, BL), or None."""
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
    m = screen_mask(hsv, kind)
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    n, lab, stats, _ = cv2.connectedComponentsWithStats(m, 8)
    best, area = 0, 0
    for i in range(1, n):
        x, y, w, h, a = stats[i]
        # with a green backdrop and a green screen, the screen is the green that
        # doesn't touch the frame edge
        if backdrop and kind == 'green' and (x == 0 or y == 0 or x + w >= W or y + h >= H):
            continue
        if a > area:
            best, area = i, a
    if area < 4000:
        return None
    comp = (lab == best).astype(np.uint8)
    cnts, _ = cv2.findContours(comp, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    hull = cv2.convexHull(max(cnts, key=cv2.contourArea))
    filled = np.zeros_like(comp)
    cv2.fillConvexPoly(filled, hull, 1)
    # in front of the screen: skin (warm, saturated) or anything clearly not
    # the key colour and not the black/white tracking marks
    key = comp.astype(bool)
    # skin by the classic RGB rule (red clearly above green and blue), so the
    # grey edges of tracking marks never count as a finger
    b, g, r = (bgr[..., i].astype(int) for i in range(3))
    skin = (r > 95) & (g > 40) & (b > 20) & (r > g) & (r > b) & (r - np.minimum(g, b) > 15) & (np.abs(r - g) > 15)
    front = skin & ~key if occluders else np.zeros_like(key)
    matte = (filled.astype(bool) & ~front).astype(np.float32)
    matte = cv2.erode(matte, np.ones((3, 3), np.uint8))
    matte = cv2.GaussianBlur(matte, (0, 0), 1.0)
    return matte, corners(hull[:, 0, :].astype(np.float64))


def corners(pts):
    """Four corners from a rounded-rect outline: fit a line to each side
    (ignoring the rounded ends) and intersect neighbours."""
    (cx, cy), (rw, rh), ang = cv2.minAreaRect(pts.astype(np.float32))
    box = cv2.boxPoints(((cx, cy), (rw, rh), ang))
    # dense outline along the hull, so every side has points
    dense = []
    for a, b in zip(pts, np.roll(pts, -1, axis=0)):
        k = max(2, int(np.hypot(*(b - a)) / 3))
        dense.extend(a + (b - a) * t for t in np.linspace(0, 1, k, endpoint=False))
    dense = np.array(dense)
    lines = []
    for i in range(4):
        p, q = box[i], box[(i + 1) % 4]
        L = np.hypot(*(q - p))
        u = (q - p) / L
        nrm = np.array([-u[1], u[0]])
        rel = dense - p
        along = rel @ u
        dist = np.abs(rel @ nrm)
        sel = dense[(along > 0.18 * L) & (along < 0.82 * L) & (dist < 0.06 * L + 6)]
        if len(sel) < 5:
            return None
        vx, vy, x0, y0 = cv2.fitLine(sel.astype(np.float32), cv2.DIST_HUBER, 0, 0.01, 0.01).ravel()
        lines.append((np.array([x0, y0]), np.array([vx, vy])))
    quad = []
    for i in range(4):
        (p1, d1), (p2, d2) = lines[i - 1], lines[i]
        A = np.array([d1, -d2]).T
        t = np.linalg.solve(A, p2 - p1)
        quad.append(p1 + d1 * t[0])
    quad = np.array(quad)
    # order: the long sides run top to bottom; TL is the top-most end's left
    c = quad.mean(axis=0)
    ang = np.arctan2(quad[:, 1] - c[1], quad[:, 0] - c[0])
    quad = quad[np.argsort(ang)]  # clockwise from left in image space
    edges = [np.hypot(*(quad[(i + 1) % 4] - quad[i])) for i in range(4)]
    # rotate so edge 0 (TL→TR) is a short side at the top
    best = min(range(4), key=lambda i: (edges[i] > np.median(edges), (quad[i][1] + quad[(i + 1) % 4][1])))
    return np.roll(quad, -best, axis=0)


def smooth(quads, k=2):
    q = np.array(quads)
    out = q.copy()
    for i in range(len(q)):
        a, b = max(0, i - k), min(len(q), i + k + 1)
        out[i] = np.median(q[a:b], axis=0)
    return out


def content_frames(spec, n):
    """The app frames for the plate: segments in order, each holding its last frame."""
    seq = []
    for seg in spec:
        d = SRC / 'rec2' / seg['flow']
        files = sorted(d.glob('*.png'))
        start = seg.get('from', 0)
        length = round(seg['seconds'] * FPS)
        speed = seg.get('speed', 1.0)
        for i in range(length):
            seq.append(files[min(len(files) - 1, start + int(i * speed))])
    while len(seq) < n:
        seq.append(seq[-1])
    return seq[:n]


def track_plate(name, p):
    """The plate's source frames (cropped to 9:16) and, per frame, the screen's
    corners and matte."""
    src = SRC / 'footage' / p['clip']
    raw = frames(src, p['from'], p['seconds'], p.get('speed', 1.0))
    raw = [crop916(f, p.get('x', 0.5), p.get('zoom', 1.0), p.get('y', 0.5)) for f in raw]
    if p.get('flip'):
        raw = [cv2.flip(f, 1) for f in raw]
    # "occluders": false for a screen nothing passes in front of (its tracking
    # marks then can't be mistaken for a finger)
    found = [find_screen(f, p['screen'], bool(p.get('backdrop')), p.get('occluders', True)) for f in raw]
    ok = [f is not None and f[1] is not None for f in found]
    if not all(ok):
        print(f'{name}: screen lost in {ok.count(False)} frames; holding the last good one')
    # frames before the first good one borrow it
    last = next((f for f in found if f is not None and f[1] is not None), None)
    if last is None:
        raise SystemExit(f'{name}: no screen found; check x/zoom so the whole screen is in frame')
    quads, mattes = [], []
    for f in found:
        if f is not None and f[1] is not None:
            last = f
        quads.append(last[1])
        mattes.append(last[0])
    return raw, smooth(quads), mattes


def build(name, p):
    raw, quads, mattes = track_plate(name, p)
    backdrop = p.get('backdrop')
    app = content_frames(p['content'], len(raw))
    if backdrop:
        bg = backdrop_image(backdrop)
    OUT.mkdir(parents=True, exist_ok=True)
    out = OUT / f'{name}.mp4'
    ff = subprocess.Popen(
        ['ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'bgr24', '-s', f'{W}x{H}', '-r', str(FPS),
         '-i', '-', '-c:v', 'libx264', '-crf', '14', '-preset', 'slow', '-g', '15', '-bf', '0', '-pix_fmt', 'yuv420p', str(out)],
        stdin=subprocess.PIPE)
    cache = {}
    for i, f in enumerate(raw):
        path = app[i]
        if path not in cache:
            cache.clear()
            cache[path] = cv2.imread(str(path))
        a = cache[path]
        ah, aw = a.shape[:2]
        Hm = cv2.getPerspectiveTransform(np.float32([[0, 0], [aw, 0], [aw, ah], [0, ah]]), quads[i].astype(np.float32))
        warped = cv2.warpPerspective(a, Hm, (W, H), flags=cv2.INTER_AREA).astype(np.float32)
        frame = f.astype(np.float32)
        matte = mattes[i][..., None]
        # the clip's own light on the screen: its brightness falloff, gently
        # (measured on key-coloured pixels only, so tracking marks and fingers
        # don't print onto the picture)
        hsv = cv2.cvtColor(f, cv2.COLOR_BGR2HSV)
        v = hsv[..., 2].astype(np.float32)
        key = screen_mask(hsv, p['screen']).astype(np.float32) * (mattes[i] > 0.5)
        if key.sum() > 500:
            ref = np.median(v[key > 0])
            ratio = np.clip(v / max(ref, 1), 0.6, 1.3)
            shade = cv2.GaussianBlur(ratio * key, (0, 0), 25) / np.maximum(cv2.GaussianBlur(key, (0, 0), 25), 1e-3)
            shade = shade[..., None]
            warped = warped * (0.9 + 0.1 * shade) * p.get('screenGain', 0.95)
        if backdrop:
            alpha, despill = key_backdrop(f)
            frame = despill * alpha[..., None] + bg * (1 - alpha[..., None])
        comp = frame * (1 - matte) + warped * matte
        ff.stdin.write(np.clip(comp, 0, 255).astype(np.uint8).tobytes())
    ff.stdin.close()
    ff.wait()
    print(f'{out}: {len(raw)} frames')


def backdrop_image(spec):
    """A soft vertical wash between two brand colours, with a light centre."""
    top = np.array(hexbgr(spec[0]), np.float32)
    bot = np.array(hexbgr(spec[1]), np.float32)
    t = np.linspace(0, 1, H)[:, None, None]
    img = top * (1 - t) + bot * t
    img = np.repeat(img, W, axis=1)
    yy, xx = np.mgrid[0:H, 0:W]
    glow = np.exp(-(((xx - W * 0.55) / (W * 0.7)) ** 2 + ((yy - H * 0.45) / (H * 0.5)) ** 2))
    return img * (0.92 + 0.12 * glow[..., None])


def hexbgr(h):
    h = h.lstrip('#')
    r, g, b = (int(h[i:i + 2], 16) for i in (0, 2, 4))
    return (b, g, r)


def main():
    specs = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
    names = sys.argv[2:] or list(specs)
    for n in names:
        build(n, specs[n])


if __name__ == '__main__':
    main()
