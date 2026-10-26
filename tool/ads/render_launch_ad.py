"""Renders ClearSkin launch ad 01 — a 28-second 1080x1920 vertical video.

Every product shot is the real app: real screen renders (design/renders) and
the real face mesh and skin-lens maps from the on-device engine (exported by
tool/ads/export_face_data_test.dart). No stock faces.

  flutter test tool/ads/export_face_data_test.dart   (with OUT=<data dir>)
  python tool/ads/render_launch_ad.py <data dir> <out.mp4> [--stills 1.0,5.2]
"""

import json
import math
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
W, H, FPS, DUR = 1080, 1920, 30, 28.0

CHARCOAL = (35, 35, 33)
CHARCOAL_2 = (52, 49, 45)
CREAM = (243, 230, 202)
SAGE = (238, 242, 237)
INK = (21, 26, 23)
MUTED = (104, 112, 106)
LEAF = (78, 154, 95)
GOLD = (255, 217, 154)
LENS = {
    'radiance': (255, 226, 174),
    'redness': (255, 122, 102),
    'tone': (233, 169, 85),
    'texture': (191, 230, 214),
}

# ── Helpers ────────────────────────────────────────────────────────────

_fonts = {}


def font(weight, size):
    key = (weight, size)
    if key not in _fonts:
        name = {200: 'ExtraLight', 300: 'Light', 400: 'Regular', 500: 'Medium',
                600: 'SemiBold', 700: 'Bold', 800: 'ExtraBold'}[weight]
        _fonts[key] = ImageFont.truetype(
            str(ROOT / f'assets/fonts/PlusJakartaSans-{name}.ttf'), size)
    return _fonts[key]


def clamp(v, lo=0.0, hi=1.0):
    return max(lo, min(hi, v))


def out_cubic(p):
    p = clamp(p)
    return 1 - (1 - p) ** 3


def in_out_cubic(p):
    p = clamp(p)
    return 4 * p ** 3 if p < 0.5 else 1 - (-2 * p + 2) ** 3 / 2


def out_back(p):
    p = clamp(p)
    c1, c3 = 1.70158, 2.70158
    return 1 + c3 * (p - 1) ** 3 + c1 * (p - 1) ** 2


def lerp(a, b, t):
    return a + (b - a) * t


def mix(c1, c2, t):
    return tuple(round(lerp(a, b, t)) for a, b in zip(c1, c2))


def rgba(c, a):
    return (*c, round(255 * clamp(a)))


def vgradient(top, bottom, w=W, h=H):
    g = np.linspace(0, 1, h)[:, None, None]
    arr = (np.array(top)[None, None, :] * (1 - g) + np.array(bottom)[None, None, :] * g)
    return Image.fromarray(np.repeat(arr, w, axis=1).astype(np.uint8), 'RGB')


def rounded_mask(size, radius):
    m = Image.new('L', size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius, fill=255)
    return m


def words_layer(img, lines, t, t0, size, weight, color, y, gap=0.12,
                accent=None, line_h=1.12, rise=46, center=True):
    """Kinetic caption: each word rises in and fades up, one after another.
    `lines` is a list of strings; words wrapped in *stars* use `accent`."""
    d = ImageDraw.Draw(img)
    f = font(weight, size)
    k = 0
    for li, line in enumerate(lines):
        words = line.split(' ')
        widths = [f.getlength(w.strip('*')) for w in words]
        space = f.getlength(' ')
        total = sum(widths) + space * (len(words) - 1)
        x = (W - total) / 2 if center else 90
        yy = y + li * size * line_h
        for w, ww in zip(words, widths):
            p = (t - (t0 + k * gap)) / 0.38
            if p > 0:
                e = out_cubic(p)
                c = accent if w.startswith('*') and accent else color
                d.text((x, yy + (1 - e) * rise), w.strip('*'), font=f, fill=rgba(c, e))
            x += ww + space
            k += 1


def text_center(d, xy, s, f, fill):
    w = f.getlength(s)
    d.text((xy[0] - w / 2, xy[1]), s, font=f, fill=fill)


# ── Assets ─────────────────────────────────────────────────────────────

DATA = Path(sys.argv[1])
OUT = Path(sys.argv[2])
STILLS = []
if '--stills' in sys.argv:
    STILLS = [float(x) for x in sys.argv[sys.argv.index('--stills') + 1].split(',')]

R = ROOT / 'design/renders'
mesh = json.loads((DATA / 'mesh.json').read_text())
lens_masks = {k: Image.open(DATA / f'lens_{k}.png').convert('L') for k in LENS}
logo = Image.open(ROOT / 'assets/brand/logo-lockup-inverse.png').convert('RGBA')

SCREEN_W = 600
SCREEN_H = round(SCREEN_W * 2532 / 1170)
BEZEL = 16


def screen_img(name):
    return Image.open(R / name).convert('RGB').resize((SCREEN_W, SCREEN_H), Image.LANCZOS)


SCREENS = {
    'plan': screen_img('10-plan-reveal.png'),
    'shelf': screen_img('07-shelf.png'),
    'journey': screen_img('14-journey.png'),
}
breakdown = Image.open(R / '05b-scan-report-full.png').convert('RGB').crop((0, 4470, 1170, 5560))
breakdown = breakdown.resize((960, round(960 * breakdown.height / breakdown.width)), Image.LANCZOS)

PHONE_SIZE = (SCREEN_W + 2 * BEZEL, SCREEN_H + 2 * BEZEL)
PHONE_MASK = rounded_mask(PHONE_SIZE, 82)
SCREEN_MASK = rounded_mask((SCREEN_W, SCREEN_H), 66)
PHONE_SHADOW = Image.new('L', (PHONE_SIZE[0] + 160, PHONE_SIZE[1] + 160), 0)
ImageDraw.Draw(PHONE_SHADOW).rounded_rectangle((80, 110, PHONE_SIZE[0] + 80, PHONE_SIZE[1] + 90), 82, fill=110)
PHONE_SHADOW = PHONE_SHADOW.filter(ImageFilter.GaussianBlur(36))


def paste_phone(base, screen, cx, top, scale=1.0, alpha=1.0):
    """A phone with `screen` (SCREEN_W×SCREEN_H) at centre-x `cx`."""
    phone = Image.new('RGBA', PHONE_SIZE, (0, 0, 0, 0))
    body = Image.new('RGBA', PHONE_SIZE, (16, 17, 16, 255))
    phone.paste(body, (0, 0), PHONE_MASK)
    phone.paste(screen.convert('RGB'), (BEZEL, BEZEL), SCREEN_MASK)
    shadow = Image.new('RGBA', PHONE_SHADOW.size, (20, 30, 24, 0))
    shadow.putalpha(PHONE_SHADOW.point(lambda v: v * alpha))
    if scale != 1.0:
        phone = phone.resize((round(PHONE_SIZE[0] * scale), round(PHONE_SIZE[1] * scale)), Image.LANCZOS)
        shadow = shadow.resize((round(shadow.width * scale), round(shadow.height * scale)), Image.LANCZOS)
    if alpha < 1:
        phone.putalpha(phone.getchannel('A').point(lambda v: v * alpha))
    x = round(cx - phone.width / 2)
    base.alpha_composite(shadow, (x - round(80 * scale), round(top) - round(80 * scale)))
    base.alpha_composite(phone, (x, round(top)))


# ── The sculpted face: the real landmark mesh, shaded like carved stone ──

PTS = mesh['points']
TRIS = mesh['tris']
CONTOURS = mesh['contours']
fx = [p[0] for p in mesh['contours']['face']]
fy = [p[1] for p in mesh['contours']['face']]
FACE_CX, FACE_CY = (min(fx) + max(fx)) / 2, (min(fy) + max(fy)) / 2
FACE_W, FACE_H = max(fx) - min(fx), max(fy) - min(fy)


def catmull(pts, closed=True, steps=8):
    out = []
    n = len(pts)
    rng = range(n) if closed else range(n - 1)
    for i in rng:
        p0 = pts[(i - 1) % n] if closed else pts[max(i - 1, 0)]
        p1, p2 = pts[i], pts[(i + 1) % n]
        p3 = pts[(i + 2) % n] if closed else pts[min(i + 2, n - 1)]
        for s in range(steps):
            t = s / steps
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * t
                                    + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t2
                                    + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t3) for j in range(2)))
    if closed:
        out.append(out[0])
    return out


def sculpture(box_w, silhouette=False):
    """The face as AR tracking sees it, for a photo box `box_w` wide (aspect
    from the scan): fine light lines and feature contours with only a
    whisper of form, glowing slightly. `silhouette` draws the backlit face
    the camera sees before the person turns to the light. Returns
    (image, box_h)."""
    box_h = round(box_w / mesh['aspect'])
    s = 2  # supersample
    img = Image.new('RGBA', (box_w * s, box_h * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    line = (46, 40, 35) if silhouette else CREAM

    def px(p):
        return (p[0] * box_w * s, p[1] * box_h * s)

    for i, (a, b, c) in enumerate(TRIS):
        cx = (PTS[a][0] + PTS[b][0] + PTS[c][0]) / 3
        cy = (PTS[a][1] + PTS[b][1] + PTS[c][1]) / 3
        rx, ry = (cx - FACE_CX) / (FACE_W / 2), (cy - FACE_CY) / (FACE_H / 2)
        r = min(1.0, math.hypot(rx, ry * 0.9))
        shade = clamp(0.25 + 0.75 * (1 - r ** 2) - 0.12 * rx - 0.08 * ry
                      + ((i * 2654435761) % 997) / 997 * 0.08)
        fill = rgba((58, 51, 45), 0.78) if silhouette else rgba(CREAM, 0.03 + 0.11 * shade)
        d.polygon([px(PTS[a]), px(PTS[b]), px(PTS[c])], fill=fill)
    for a, b, c in TRIS:
        d.line([px(PTS[a]), px(PTS[b]), px(PTS[c]), px(PTS[a])],
               fill=rgba(line, 0.22 if silhouette else 0.30), width=2)
    for key in ('leftEye', 'rightEye'):
        if key in CONTOURS:
            d.line([px(p) for p in catmull(CONTOURS[key])], fill=rgba(line, 0.95), width=4)
    if 'upperLipTop' in CONTOURS and 'lowerLipBottom' in CONTOURS:
        lips = CONTOURS['upperLipTop'] + CONTOURS['lowerLipBottom'][::-1]
        d.line([px(p) for p in catmull(lips)], fill=rgba(line, 0.85), width=4)
    for key in ('leftEyebrowTop', 'rightEyebrowTop'):
        if key in CONTOURS:
            d.line([px(p) for p in catmull(CONTOURS[key], closed=False)], fill=rgba(line, 0.8), width=4)
    d.line([px(p) for p in catmull(CONTOURS['face'])], fill=rgba(line, 0.7), width=3)
    for p in PTS:
        x, y = px(p)
        d.ellipse((x - 2.6, y - 2.6, x + 2.6, y + 2.6), fill=rgba(line, 0.9))
    img = img.resize((box_w, box_h), Image.LANCZOS)
    if silhouette:
        return img, box_h
    # A soft bloom under the lines, so the tracking reads as light.
    glow = img.filter(ImageFilter.GaussianBlur(6))
    out = Image.new('RGBA', img.size, (0, 0, 0, 0))
    out.alpha_composite(glow)
    out.alpha_composite(img)
    return out, box_h


def lens_layer(name, box_w, box_h, gain):
    """The real lens map, tinted, with a soft bloom."""
    m = lens_masks[name].resize((box_w, box_h), Image.BICUBIC)
    a = np.clip(np.asarray(m, dtype=np.float32) / 255 * gain, 0, 1)
    # Radiance covers most of an even face: show where it's strongest, as
    # light, rather than tinting the whole face.
    a = a ** (2.2 if name == 'radiance' else 0.85)
    col = np.zeros((box_h, box_w, 4), dtype=np.uint8)
    col[..., :3] = LENS[name]
    col[..., 3] = (a * (170 if name == 'radiance' else 235)).astype(np.uint8)
    sharp = Image.fromarray(col, 'RGBA')
    bloom = sharp.filter(ImageFilter.GaussianBlur(26))
    out = Image.new('RGBA', sharp.size, (0, 0, 0, 0))
    out.alpha_composite(bloom)
    out.alpha_composite(sharp)
    return out


# Measure scene: big face. Scan scene: face inside the phone's oval.
BIG_W = 1000
BIG, BIG_H = sculpture(BIG_W)
BIG_LEFT = round(540 - FACE_CX * BIG_W)
BIG_TOP = round(1010 - FACE_CY * BIG_H)
GAIN = {'radiance': 1.15, 'redness': 4.0, 'tone': 3.2, 'texture': 2.4}
LENS_LAYERS = {k: lens_layer(k, BIG_W, BIG_H, GAIN[k]) for k in LENS}

OVAL_C = (SCREEN_W / 2, SCREEN_H * 0.42)
OVAL_W, OVAL_H = SCREEN_W * 0.62, SCREEN_W * 0.84
SMALL_W = round(OVAL_W * 0.95 / FACE_W)
SMALL, SMALL_H = sculpture(SMALL_W)
SMALL_DIM, _ = sculpture(SMALL_W, silhouette=True)

# ── Scenes ─────────────────────────────────────────────────────────────


def scene_hook(t):
    img = Image.new('RGBA', (W, H), (*CHARCOAL, 255))
    d = ImageDraw.Draw(img)
    # The score dial, faint, its ticks lighting up behind the words.
    cx, cy, r = 540, 960, 420
    lit = round(72 * 0.76 * out_cubic((t - 0.5) / 1.8))
    for i in range(72):
        a = -math.pi / 2 + i / 72 * math.tau + (1 - out_cubic(t / 2.4)) * 0.4
        major = i % 6 == 0
        ln = 34 if major else 22
        dx, dy = math.cos(a), math.sin(a)
        d.line((cx + dx * r, cy + dy * r, cx + dx * (r - ln), cy + dy * (r - ln)),
               fill=rgba(CREAM, 0.55 if i < lit else 0.10), width=5 if major else 3)
    f = font(800, 150)
    for k, (word, y, col) in enumerate([('Your skin', 690, CREAM), ('has a', 860, CREAM), ('score.', 1030, GOLD)]):
        p = (t - (0.1 + k * 0.3)) / 0.32
        if p <= 0:
            continue
        sc = lerp(1.35, 1.0, out_back(p))
        w = f.getlength(word)
        layer = Image.new('RGBA', (round(w) + 40, 210), (0, 0, 0, 0))
        ImageDraw.Draw(layer).text((20, 0), word, font=f, fill=rgba(col, out_cubic(p)))
        layer = layer.resize((round(layer.width * sc), round(layer.height * sc)), Image.BICUBIC)
        img.alpha_composite(layer, (round(540 - layer.width / 2), round(y - (sc - 1) * 90)))
    return img


def camera_screen(t):
    """The live scan screen, t in scene time."""
    lit_on = out_cubic((t - 1.4) / 0.3)  # turns to face the light
    bg = Image.blend(vgradient((236, 229, 216), (205, 197, 184), SCREEN_W, SCREEN_H),
                     vgradient((92, 82, 72), (24, 22, 20), SCREEN_W, SCREEN_H), lit_on)
    scr = bg.convert('RGBA')
    d = ImageDraw.Draw(scr)
    # Face: a dark silhouette against the window, then the tracked mesh.
    ox, oy = OVAL_C
    left = round(ox - FACE_CX * SMALL_W)
    top = round(oy - FACE_CY * SMALL_H)
    track = out_cubic((t - 0.25) / 0.9)
    face = SMALL_DIM if lit_on < 0.5 else SMALL
    if track > 0:
        cut = face.crop((0, 0, face.width, max(1, round(face.height * track))))
        a = 0.55 + 0.45 * lit_on
        cut.putalpha(cut.getchannel('A').point(lambda v: v * a))
        scr.alpha_composite(cut, (left, top))
    # Oval guide, then the hold-still ring filling.
    box = (ox - OVAL_W / 2, oy - OVAL_H / 2, ox + OVAL_W / 2, oy + OVAL_H / 2)
    ready = t >= 2.35
    if ready:
        d.ellipse(box, outline=rgba((124, 196, 149), 0.55), width=6)
        prog = out_cubic((t - 2.35) / 0.75)
        d.arc(box, -90, -90 + 360 * prog, fill=(124, 196, 149, 255), width=9)
    else:
        for i in range(48):
            a0 = i / 48 * 360
            d.arc(box, a0, a0 + 4.5, fill=rgba((255, 255, 255), 0.9), width=4)
    # Hint pill and the three checks.
    msg = 'Perfect — hold it there' if ready else 'Light is behind you — turn to face it'
    # Larger than in the app: these have to read in a feed, at phone size.
    pf = font(700, 27) if not ready else font(700, 31)
    lines = ['Light is behind you', 'turn to face it'] if not ready else [msg]
    lh = 36
    ph = 26 + lh * len(lines)
    pw = max(pf.getlength(s) for s in lines) + 56
    d.rounded_rectangle((SCREEN_W / 2 - pw / 2, 70, SCREEN_W / 2 + pw / 2, 70 + ph), 30,
                        fill=(78, 154, 95, 255) if ready else (0, 0, 0, 170))
    for k, s in enumerate(lines):
        text_center(d, (SCREEN_W / 2, 82 + k * lh), s, pf, (255, 255, 255, 255))
    cf = font(700, 22)
    labels = ['LIGHT', 'POSITION', 'STILL']
    on_at = [1.65, 1.95, 2.25]
    widths = [cf.getlength(s) for s in labels]
    x = SCREEN_W / 2 - (sum(widths) + 2 * 34) / 2
    cy = 70 + ph + 26
    for s, w, at in zip(labels, widths, on_at):
        on = out_cubic((t - at) / 0.15)
        # Dark text on the bright window, light once facing the light.
        col = (255, 255, 255) if lit_on > 0.5 else (40, 36, 32)
        d.text((x, cy), s, font=cf, fill=rgba(col, 0.4 + 0.6 * on))
        x += w + 34
    # Shutter, unlocked once ready.
    sx, sy, sr = SCREEN_W / 2, SCREEN_H - 120, 46
    alpha = 1.0 if ready else 0.4
    d.ellipse((sx - sr, sy - sr, sx + sr, sy + sr), outline=rgba((255, 255, 255), alpha), width=6)
    d.ellipse((sx - sr + 12, sy - sr + 12, sx + sr - 12, sy + sr - 12), fill=rgba((255, 255, 255), alpha))
    flash = 1 - out_cubic((t - 3.15) / 0.35) if t >= 3.15 else 0
    if flash > 0:
        scr.alpha_composite(Image.new('RGBA', scr.size, rgba((255, 255, 255), flash)))
    return scr


def sage_bg():
    return vgradient((227, 236, 226), SAGE).convert('RGBA')


SAGE_BG = sage_bg()


def scene_scan(t):
    img = SAGE_BG.copy()
    words_layer(img, ['It won’t scan you', 'until the light is *right.*'], t, 0.1, 74, 800, INK, 190, accent=LEAF)
    rise = out_cubic(t / 0.55)
    paste_phone(img, camera_screen(t), 540, 520 + (1 - rise) * 500)
    return img


LENS_ORDER = [('radiance', 'your glow.'), ('redness', 'redness.'), ('tone', 'dark marks.'), ('texture', 'texture.')]
LENS_STEP = 1.15


def scene_measure(t):
    img = Image.new('RGBA', (W, H), (*CHARCOAL, 255))
    zoom = lerp(1.06, 1.0, out_cubic(t / 0.8))
    face = BIG if zoom == 1 else BIG.resize((round(BIG.width * zoom), round(BIG.height * zoom)), Image.BICUBIC)
    fl = round(540 - FACE_CX * face.width)
    ft = round(1010 - FACE_CY * face.height)
    img.alpha_composite(face, (fl, ft))
    i = min(len(LENS_ORDER) - 1, int(t // LENS_STEP))
    name, word = LENS_ORDER[i]
    lt = t - i * LENS_STEP
    # Scan line reveals each lens, as in the app.
    top_y, bot_y = BIG_TOP + FACE_CY * BIG_H - FACE_H * BIG_H * 0.62, BIG_TOP + FACE_CY * BIG_H + FACE_H * BIG_H * 0.62
    sweep = lerp(top_y, bot_y, in_out_cubic(lt / 0.5))
    if i > 0 and lt < 0.5:
        prev = LENS_LAYERS[LENS_ORDER[i - 1][0]]
        cut = prev.crop((0, max(0, round(sweep - BIG_TOP)), BIG_W, BIG_H))
        img.alpha_composite(cut, (BIG_LEFT, max(BIG_TOP, round(sweep))))
    layer = LENS_LAYERS[name]
    h = clamp(round(sweep - BIG_TOP), 1, BIG_H)
    img.alpha_composite(layer.crop((0, 0, BIG_W, h)), (BIG_LEFT, BIG_TOP))
    d = ImageDraw.Draw(img)
    if lt < 0.5:
        band = Image.new('RGBA', (W, 60), (0, 0, 0, 0))
        bd = ImageDraw.Draw(band)
        for k in range(60):
            bd.line((0, k, W, k), fill=rgba(CREAM, 0.16 * k / 60))
        img.alpha_composite(band, (0, round(sweep) - 60))
        d.line((0, sweep, W, sweep), fill=rgba(CREAM, 0.9), width=3)
    # Caption: "It measures" + the lens word flipping in its own colour.
    words_layer(img, ['It measures'], t, 0.05, 84, 800, CREAM, 200)
    wf = font(800, 120)
    p = out_cubic(lt / 0.3)
    text_center(d, (540, 300 + (1 - p) * 60), word, wf, rgba(LENS[name], p))
    # Lens tabs, like the app's.
    tf = font(500, 32)
    labels = [n.capitalize() for n, _ in LENS_ORDER]
    widths = [tf.getlength(s) for s in labels]
    x = 540 - (sum(widths) + 3 * 46) / 2
    for k, (s, w) in enumerate(zip(labels, widths)):
        on = k == i
        d.text((x, 1440), s, font=font(700 if on else 400, 32), fill=rgba((255, 255, 255), 1 if on else 0.5))
        x += w + 46
    return img


def scene_score(t):
    img = Image.new('RGBA', (W, H), (*CHARCOAL, 255))
    glow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((140, 560, 940, 1360), fill=rgba(CREAM, 0.07))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(90)))
    d = ImageDraw.Draw(img)
    words_layer(img, ['Your skin,', '*scored.*'], t, 0.05, 92, 800, CREAM, 190, accent=GOLD)
    cx, cy, r = 540, 960, 330
    v = out_cubic((t - 0.25) / 1.45)
    lit = round(72 * 0.76 * v)
    for i in range(72):
        a = -math.pi / 2 + i / 72 * math.tau
        major = i % 6 == 0
        ln = 40 if major else 26
        dx, dy = math.cos(a), math.sin(a)
        d.line((cx + dx * r, cy + dy * r, cx + dx * (r - ln), cy + dy * (r - ln)),
               fill=rgba(CREAM, 1 if i < lit else 0.16), width=6 if major else 4)
    text_center(d, (540, 820), 'SKIN SCORE', font(600, 30), rgba(CREAM, 0.6))
    text_center(d, (540, 850), f'{round(76 * v)}', font(200, 230), (*CREAM, 255))
    # Facts settle in under the dial.
    p = out_cubic((t - 1.9) / 0.4)
    if p > 0:
        y = 1380 + (1 - p) * 30
        d.line((180, y, 900, y), fill=rgba(CREAM, 0.16 * p), width=2)
        d.line((540, y + 30, 540, y + 130), fill=rgba(CREAM, 0.16 * p), width=2)
        for x, lab, val in ((360, 'SINCE LAST', '+3'), (720, 'RADIANCE', '75')):
            text_center(d, (x, y + 34), lab, font(600, 26), rgba(CREAM, 0.5 * p))
            text_center(d, (x, y + 72), val, font(400, 50), rgba(CREAM, p))
    return img


def scene_breakdown(t):
    img = SAGE_BG.copy()
    words_layer(img, ['And exactly what’s', '*holding it back.*'], t, 0.05, 74, 800, INK, 190, accent=LEAF)
    rise = out_cubic((t - 0.1) / 0.5)
    card_w, card_h = breakdown.width + 0, breakdown.height
    card = Image.new('RGBA', (card_w, card_h), (*SAGE, 255))
    reveal = out_cubic((t - 0.35) / 0.9)
    card.paste(breakdown.crop((0, 0, card_w, max(1, round(card_h * reveal)))), (0, 0))
    y = 640 + (1 - rise) * 160
    shadow = Image.new('RGBA', (card_w + 120, card_h + 120), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((60, 80, card_w + 60, card_h + 60), 40, fill=(20, 30, 24, 40))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(30)), (60 - 60, round(y) - 60))
    framed = Image.new('RGBA', (card_w, card_h), (0, 0, 0, 0))
    framed.paste(card, (0, 0), rounded_mask((card_w, card_h), 40))
    if rise < 1:
        framed.putalpha(framed.getchannel('A').point(lambda v: v * rise))
    img.alpha_composite(framed, (60, round(y)))
    return img


def phone_scene(caption, screen, accent=LEAF, from_side=False):
    def render(t):
        img = SAGE_BG.copy()
        words_layer(img, caption, t, 0.05, 74, 800, INK, 190, accent=accent)
        p = out_cubic(t / 0.5)
        drift = math.sin(t * 1.3) * 6
        if from_side:
            paste_phone(img, SCREENS[screen], 540 + (1 - p) * 700, 520 + drift)
        else:
            paste_phone(img, SCREENS[screen], 540, 520 + (1 - p) * 520 + drift)
        return img
    return render


def scene_end(t):
    img = Image.new('RGBA', (W, H), (*CHARCOAL, 255))
    d = ImageDraw.Draw(img)
    p = out_cubic(t / 0.6)
    lw = 620
    lg = logo.resize((lw, round(lw * logo.height / logo.width)), Image.LANCZOS)
    sc = lerp(0.92, 1, p)
    lg = lg.resize((round(lg.width * sc), round(lg.height * sc)), Image.LANCZOS)
    lg.putalpha(lg.getchannel('A').point(lambda v: v * p))
    img.alpha_composite(lg, (round(540 - lg.width / 2), round(640 - lg.height / 2)))
    words_layer(img, ['Your skin,', 'measured.'], t, 0.35, 110, 300, CREAM, 820, gap=0.18)
    q = (t - 1.2) / 0.4
    if q > 0:
        s = out_back(q)
        pf = font(700, 46)
        msg = 'Your first scan is free'
        pw, ph = pf.getlength(msg) + 110, 112
        pill = Image.new('RGBA', (round(pw), ph), (0, 0, 0, 0))
        pd = ImageDraw.Draw(pill)
        pd.rounded_rectangle((0, 0, pw - 1, ph - 1), ph // 2, fill=(*CREAM, 255))
        pd.text((55, 28), msg, font=pf, fill=(*CHARCOAL, 255))
        pill = pill.resize((max(1, round(pill.width * s)), max(1, round(pill.height * s))), Image.BICUBIC)
        img.alpha_composite(pill, (round(540 - pill.width / 2), round(1130 + ph / 2 - pill.height / 2)))
    f = out_cubic((t - 1.7) / 0.4)
    if f > 0:
        text_center(d, (540, 1300), 'Photos saved only on your phone', font(400, 34), rgba(CREAM, 0.65 * f))
        text_center(d, (540, 1352), 'On Google Play', font(600, 34), rgba(CREAM, 0.9 * f))
    return img


SCENES = [
    (0.0, 2.6, scene_hook),
    (2.6, 6.4, scene_scan),
    (6.4, 11.0, scene_measure),
    (11.0, 14.2, scene_score),
    (14.2, 16.6, scene_breakdown),
    (16.6, 19.6, phone_scene(['Then it builds your', '*12-week plan.*'], 'plan')),
    (19.6, 22.2, phone_scene(['It checks your shelf', 'for products that *clash.*'], 'shelf', from_side=True)),
    (22.2, 24.8, phone_scene(['Then watch it change,', '*week by week.*'], 'journey')),
    (24.8, DUR, scene_end),
]
WHIP = 0.26


def frame(t):
    idx = max(i for i, s in enumerate(SCENES) if t >= s[0])
    start, _, fn = SCENES[idx]
    cur = fn(t - start)
    if idx > 0 and t - start < WHIP:
        # Whip: the old scene flies up and away as the new one lands.
        e = in_out_cubic((t - start) / WHIP)
        pstart, _, pfn = SCENES[idx - 1]
        prev = pfn(t - pstart)
        # The gap the new scene leaves at the top takes its own background.
        out = Image.new('RGBA', (W, H), cur.getpixel((0, 0)))
        out.alpha_composite(cur, (0, round((1 - e) * 260)))
        prev.putalpha(round(255 * (1 - e)))
        out.alpha_composite(prev, (0, round(-e * 260)))
        cur = out
    return cur.convert('RGB')


# ── Sound design ───────────────────────────────────────────────────────

SR = 44100


def audio():
    n = int(DUR * SR)
    tt = np.arange(n) / SR
    mixl = np.zeros(n)
    rng = np.random.default_rng(7)

    def add(at, sig, gain=1.0):
        i = int(at * SR)
        j = min(n, i + len(sig))
        mixl[i:j] += sig[: j - i] * gain

    def env(length, attack=0.005, decay=6.0):
        x = np.arange(int(length * SR)) / SR
        return np.minimum(1, x / attack) * np.exp(-x * decay)

    def thump(at, gain=0.9):
        x = np.arange(int(0.45 * SR)) / SR
        f = 55 + 70 * np.exp(-x * 18)
        add(at, np.sin(2 * np.pi * np.cumsum(f) / SR) * env(0.45, 0.002, 7), gain)

    def tick(at, freq=2200, gain=0.25):
        x = np.arange(int(0.05 * SR)) / SR
        add(at, np.sin(2 * np.pi * freq * x) * env(0.05, 0.001, 90), gain)

    def whoosh(at, length=0.32, gain=0.22):
        m = int(length * SR)
        noise = rng.standard_normal(m)
        k = np.ones(18) / 18
        noise = np.convolve(noise, k, mode='same')
        shape = np.sin(np.linspace(0, np.pi, m)) ** 2
        add(at - length * 0.4, noise * shape, gain)

    def chime(at, gain=0.22):
        x = np.arange(int(1.6 * SR)) / SR
        sig = sum(np.sin(2 * np.pi * f * x) * a for f, a in ((880, 1), (1318.5, .55), (1760, .25)))
        add(at, sig * env(1.6, 0.004, 3.2), gain)

    def shutter(at):
        add(at, rng.standard_normal(int(0.06 * SR)) * env(0.06, 0.001, 70), 0.35)
        tick(at + 0.07, 1200, 0.25)

    # Pad: a warm, slow A-major bed under everything.
    pad = np.zeros(n)
    for f, a in ((110, .5), (164.81, .35), (220, .3), (277.18, .2), (329.63, .16)):
        pad += a * np.sin(2 * np.pi * f * tt + f) * (0.85 + 0.15 * np.sin(2 * np.pi * 0.2 * tt + f))
    fade = np.minimum(1, tt / 1.5) * np.minimum(1, (DUR - tt) / 2.0)
    mixl += pad * fade * 0.05

    for k in range(3):
        thump(0.1 + k * 0.3)
    for s, _, _ in SCENES[1:]:
        whoosh(s)
    for at in (1.65, 1.95, 2.25):
        tick(2.6 + at, 2400, 0.3)
    shutter(2.6 + 3.15)
    for k in range(1, 4):
        whoosh(6.4 + k * LENS_STEP, 0.4, 0.16)
    # Score ticks: one per lit tick, slowing as the dial settles.
    for i in range(1, 55):
        v = i / 55
        p = 1 - (1 - v) ** (1 / 3)
        tick(11.0 + 0.25 + p * 1.45, 1900 + 600 * v, 0.12)
    chime(11.0 + 1.75, 0.18)
    chime(24.8 + 1.2, 0.24)

    peak = np.max(np.abs(mixl)) or 1
    pcm = (mixl / peak * 0.89 * 32767).astype(np.int16)
    stereo = np.repeat(pcm[:, None], 2, axis=1)
    path = OUT.with_suffix('.wav')
    with wave.open(str(path), 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(stereo.tobytes())
    return path


# ── Output ─────────────────────────────────────────────────────────────

if STILLS:
    for s in STILLS:
        frame(s).save(OUT.parent / f'still_{s:05.2f}.png')
    print('stills written')
    sys.exit(0)

import imageio_ffmpeg  # noqa: E402

wav = audio()
ff = imageio_ffmpeg.get_ffmpeg_exe()
proc = subprocess.Popen(
    [ff, '-y', '-loglevel', 'error',
     '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}', '-r', str(FPS), '-i', '-',
     '-i', str(wav),
     '-c:v', 'libx264', '-preset', 'slow', '-crf', '21', '-pix_fmt', 'yuv420p',
     '-profile:v', 'high', '-c:a', 'aac', '-b:a', '160k', '-shortest',
     '-movflags', '+faststart', str(OUT)],
    stdin=subprocess.PIPE)
frames = int(DUR * FPS)
for k in range(frames):
    proc.stdin.write(frame(k / FPS).tobytes())
    if k % 60 == 0:
        print(f'{k}/{frames}', flush=True)
proc.stdin.close()
proc.wait()
wav.unlink()
print('done', OUT)
