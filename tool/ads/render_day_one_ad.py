"""Renders ClearSkin ad 02, "Day 1" — a real person's real scan.

28 seconds, 1080x1920. The face, its tracking mesh, its lens maps and its
radiance reading all come from one real scan on a phone, measured by the
app's own engine (tool/ads/export_face_data_test.dart). The photo gets one
global brightness/contrast lift and nothing else: no smoothing, no
retouching. The "after" is a real week-12 scan, not an edit.

  OUT=<data> PHOTO=<scan.jpg> FACE=<face.json> flutter test tool/ads/export_face_data_test.dart
  python tool/ads/render_day_one_ad.py <scan.jpg> <data dir> <out.mp4> [--stills 1,5]
"""

import json
import math
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
W, H, FPS, DUR = 1080, 1920, 30, 28.0

CHARCOAL = (35, 35, 33)
CREAM = (243, 230, 202)
SAGE = (238, 242, 237)
INK = (21, 26, 23)
LEAF = (78, 154, 95)
GOLD = (255, 217, 154)
LENS = {
    'radiance': (255, 226, 174),
    'redness': (255, 122, 102),
    'tone': (233, 169, 85),
    'texture': (191, 230, 214),
}

PHOTO = Path(sys.argv[1])
DATA = Path(sys.argv[2])
OUT = Path(sys.argv[3])
STILLS = []
if '--stills' in sys.argv:
    STILLS = [float(x) for x in sys.argv[sys.argv.index('--stills') + 1].split(',')]

# ── Helpers ────────────────────────────────────────────────────────────

_fonts = {}


def font(weight, size):
    key = (weight, size)
    if key not in _fonts:
        name = {200: 'ExtraLight', 300: 'Light', 400: 'Regular', 500: 'Medium',
                600: 'SemiBold', 700: 'Bold', 800: 'ExtraBold'}[weight]
        _fonts[key] = ImageFont.truetype(str(ROOT / f'assets/fonts/PlusJakartaSans-{name}.ttf'), size)
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
    return 1 + 2.70158 * (p - 1) ** 3 + 1.70158 * (p - 1) ** 2


def lerp(a, b, t):
    return a + (b - a) * t


def rgba(c, a):
    return (*c, round(255 * clamp(a)))


def text_center(d, xy, s, f, fill):
    d.text((xy[0] - f.getlength(s) / 2, xy[1]), s, font=f, fill=fill)


def rounded_mask(size, radius):
    m = Image.new('L', size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius, fill=255)
    return m


def vgradient(top, bottom, w=W, h=H):
    g = np.linspace(0, 1, h)[:, None, None]
    arr = np.array(top)[None, None, :] * (1 - g) + np.array(bottom)[None, None, :] * g
    return Image.fromarray(np.repeat(arr, w, axis=1).astype(np.uint8), 'RGB')


def caption(img, lines, t, t0, size, color, y, accent=None, gap=0.12, shadow=False, weight=800):
    """Kinetic caption: each word rises in, one after another. *word* takes
    `accent`. Over photos, a soft shadow keeps it readable."""
    f = font(weight, size)
    layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    sh = Image.new('RGBA', (W, H), (0, 0, 0, 0)) if shadow else None
    sd = ImageDraw.Draw(sh) if shadow else None
    k = 0
    for li, line in enumerate(lines):
        words = line.split(' ')
        widths = [f.getlength(w.strip('*')) for w in words]
        space = f.getlength(' ')
        x = (W - sum(widths) - space * (len(words) - 1)) / 2
        yy = y + li * size * 1.12
        for w, ww in zip(words, widths):
            p = (t - (t0 + k * gap)) / 0.38
            if p > 0:
                e = out_cubic(p)
                c = accent if w.startswith('*') and accent else color
                pos = (x, yy + (1 - e) * 46)
                if sd:
                    sd.text((pos[0], pos[1] + 4), w.strip('*'), font=f, fill=(0, 0, 0, round(200 * e)))
                d.text(pos, w.strip('*'), font=f, fill=rgba(c, e))
            x += ww + space
            k += 1
    if sh:
        img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(10)))
    img.alpha_composite(layer)


# ── The real scan ─────────────────────────────────────────────────────

mesh = json.loads((DATA / 'mesh.json').read_text())
RAD = mesh['radiance']
PTS = mesh['points']
TRIS = mesh['tris']
CONTOURS = mesh['contours']

# One global lift for a dim bedroom photo. Nothing local, nothing on skin.
photo = Image.open(PHOTO).convert('RGB')
photo = ImageEnhance.Brightness(photo).enhance(1.10)
photo = ImageEnhance.Contrast(photo).enhance(1.06)
BASE = photo.resize((W, H), Image.LANCZOS)

fx = [p[0] for p in CONTOURS['face']]
fy = [p[1] for p in CONTOURS['face']]
FACE_BOX = (min(fx) * W, min(fy) * H, max(fx) * W, max(fy) * H)
FACE_C = ((FACE_BOX[0] + FACE_BOX[2]) / 2, (FACE_BOX[1] + FACE_BOX[3]) / 2)

# Top shade so captions read over the photo.
_shade = np.zeros((H, W, 4), dtype=np.uint8)
_a = np.clip(1 - np.linspace(0, 1, H) / 0.36, 0, 1) ** 1.6
_shade[..., 3] = (_a * 190)[:, None].astype(np.uint8)
TOP_SHADE = Image.fromarray(_shade, 'RGBA')


def catmull(pts, closed=True, steps=8):
    out = []
    n = len(pts)
    for i in (range(n) if closed else range(n - 1)):
        p0 = pts[(i - 1) % n] if closed else pts[max(i - 1, 0)]
        p1, p2 = pts[i], pts[(i + 1) % n]
        p3 = pts[(i + 2) % n] if closed else pts[min(i + 2, n - 1)]
        for s in range(steps):
            t = s / steps
            out.append(tuple(0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * t
                                    + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t * t
                                    + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t ** 3) for j in range(2)))
    if closed:
        out.append(out[0])
    return out


def mesh_layer():
    """The tracking mesh on the face, as the app draws it, with a glow."""
    s = 2
    img = Image.new('RGBA', (W * s, H * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def px(p):
        return (p[0] * W * s, p[1] * H * s)

    for a, b, c in TRIS:
        d.line([px(PTS[a]), px(PTS[b]), px(PTS[c]), px(PTS[a])], fill=(255, 255, 255, 70), width=2)
    for key in ('leftEye', 'rightEye'):
        d.line([px(p) for p in catmull(CONTOURS[key])], fill=(255, 255, 255, 220), width=4)
    lips = CONTOURS['upperLipTop'] + CONTOURS['lowerLipBottom'][::-1]
    d.line([px(p) for p in catmull(lips)], fill=(255, 255, 255, 200), width=4)
    for key in ('leftEyebrowTop', 'rightEyebrowTop'):
        d.line([px(p) for p in catmull(CONTOURS[key], closed=False)], fill=(255, 255, 255, 190), width=4)
    d.line([px(p) for p in catmull(CONTOURS['face'])], fill=(255, 255, 255, 150), width=3)
    for p in PTS:
        x, y = px(p)
        d.ellipse((x - 3, y - 3, x + 3, y + 3), fill=(255, 255, 255, 230))
    img = img.resize((W, H), Image.LANCZOS)
    out = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    out.alpha_composite(img.filter(ImageFilter.GaussianBlur(5)))
    out.alpha_composite(img)
    return out


MESH = mesh_layer()
MESH_QUIET = MESH.copy()
MESH_QUIET.putalpha(MESH.getchannel('A').point(lambda v: v * 0.35))


def lens_frame(name):
    """The whole photo with one lens on it, as the app shows it: the photo
    dimmed a touch, the measurement as light (radiance) or colour."""
    m = Image.open(DATA / f'lens_{name}.png').convert('L').resize((W, H), Image.BICUBIC)
    gain = {'radiance': 1.1, 'redness': 3.2, 'tone': 2.8, 'texture': 2.2}[name]
    a = np.clip(np.asarray(m, dtype=np.float32) / 255 * gain, 0, 1)
    if name == 'radiance':
        a = a ** 2.4
    blur = 10 if name == 'radiance' else 4
    a = np.asarray(Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(blur)),
                   dtype=np.float32) / 255
    base = np.asarray(BASE, dtype=np.float32) * 0.82
    col = np.array(LENS[name], dtype=np.float32)
    if name == 'radiance':
        # Light, not paint: screen the glow onto the skin.
        glow = col * a[..., None] * 0.55
        out = 255 - (255 - base) * (255 - glow) / 255
    else:
        k = (a * 0.85)[..., None]
        out = base * (1 - k) + col * k
    frame = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), 'RGB').convert('RGBA')
    frame.alpha_composite(MESH_QUIET)
    return frame


LENS_ORDER = [('radiance', 'my glow.'), ('redness', 'redness.'), ('tone', 'dark marks.'), ('texture', 'texture.')]
LENS_FRAMES = {k: lens_frame(k) for k, _ in LENS_ORDER}
BASE_RGBA = BASE.convert('RGBA')
DIM = Image.blend(BASE, Image.new('RGB', (W, H), (0, 0, 0)), 0.18).convert('RGBA')
BLUR_BG = Image.blend(BASE.filter(ImageFilter.GaussianBlur(40)), Image.new('RGB', (W, H), CHARCOAL), 0.72).convert('RGBA')

# ── App screens for the plan and shelf beats ───────────────────────────

R = ROOT / 'design/renders'
SCREEN_W = 600
SCREEN_H = round(SCREEN_W * 2532 / 1170)
BEZEL = 16
PHONE_SIZE = (SCREEN_W + 2 * BEZEL, SCREEN_H + 2 * BEZEL)
PHONE_MASK = rounded_mask(PHONE_SIZE, 82)
SCREEN_MASK = rounded_mask((SCREEN_W, SCREEN_H), 66)
_ps = Image.new('L', (PHONE_SIZE[0] + 160, PHONE_SIZE[1] + 160), 0)
ImageDraw.Draw(_ps).rounded_rectangle((80, 110, PHONE_SIZE[0] + 80, PHONE_SIZE[1] + 90), 82, fill=110)
PHONE_SHADOW = _ps.filter(ImageFilter.GaussianBlur(36))
SCREENS = {k: Image.open(R / f).convert('RGB').resize((SCREEN_W, SCREEN_H), Image.LANCZOS)
           for k, f in (('plan', '10-plan-reveal.png'), ('shelf', '07-shelf.png'))}
SAGE_BG = vgradient((227, 236, 226), SAGE).convert('RGBA')
logo = Image.open(ROOT / 'assets/brand/logo-lockup-inverse.png').convert('RGBA')


def paste_phone(base, screen, cx, top):
    phone = Image.new('RGBA', PHONE_SIZE, (0, 0, 0, 0))
    phone.paste(Image.new('RGBA', PHONE_SIZE, (16, 17, 16, 255)), (0, 0), PHONE_MASK)
    phone.paste(screen, (BEZEL, BEZEL), SCREEN_MASK)
    shadow = Image.new('RGBA', PHONE_SHADOW.size, (20, 30, 24, 0))
    shadow.putalpha(PHONE_SHADOW)
    x = round(cx - PHONE_SIZE[0] / 2)
    base.alpha_composite(shadow, (x - 80, round(top) - 80))
    base.alpha_composite(phone, (x, round(top)))


# ── Scenes ─────────────────────────────────────────────────────────────


def scene_scan(t):
    """His face in the real scan screen: guided closer, checks, capture."""
    # "Move a little closer": the camera pushes in on the face.
    zoom = lerp(1.0, 1.16, in_out_cubic((t - 0.35) / 0.7))
    img = Image.new('RGBA', (W, H), (0, 0, 0, 255))
    fr = BASE_RGBA if zoom == 1 else BASE_RGBA.resize((round(W * zoom), round(H * zoom)), Image.BICUBIC)
    img.alpha_composite(fr, (round(FACE_C[0] * (1 - zoom)), round(FACE_C[1] * (1 - zoom))))
    img.alpha_composite(TOP_SHADE)
    d = ImageDraw.Draw(img)
    # Oval around the face, sized as the app's.
    # The oval is where the face should end up, so it's sized for the
    # final push-in: the face grows into it.
    fw, fh = (FACE_BOX[2] - FACE_BOX[0]) * 1.16, (FACE_BOX[3] - FACE_BOX[1]) * 1.16
    cx = FACE_C[0]
    cy = FACE_C[1]
    box = (cx - fw * 0.53, cy - fh * 0.57, cx + fw * 0.53, cy + fh * 0.55)
    ready = t >= 1.55
    if ready:
        d.ellipse(box, outline=rgba((124, 196, 149), 0.5), width=7)
        d.arc(box, -90, -90 + 360 * out_cubic((t - 1.55) / 0.8), fill=(124, 196, 149, 255), width=10)
    else:
        for i in range(56):
            a0 = i / 56 * 360
            d.arc(box, a0, a0 + 3.6, fill=(255, 255, 255, 220), width=5)
    # One hint at a time, then the three checks.
    hint = ('Perfect — hold it there' if ready else
            'Hold still' if t >= 0.95 else 'Move a little closer')
    pf = font(700, 40)
    pw = pf.getlength(hint) + 76
    y0 = 400
    d.rounded_rectangle((540 - pw / 2, y0, 540 + pw / 2, y0 + 84), 42,
                        fill=(78, 154, 95, 255) if ready else (0, 0, 0, 165))
    text_center(d, (540, y0 + 18), hint, pf, (255, 255, 255, 255))
    cf = font(700, 30)
    labels = ['LIGHT', 'POSITION', 'STILL']
    widths = [cf.getlength(s) for s in labels]
    x = 540 - (sum(widths) + 2 * 46) / 2
    cy_checks = box[3] + 40
    for s, w, at in zip(labels, widths, (1.0, 1.22, 1.44)):
        on = out_cubic((t - at) / 0.15)
        d.text((x + 2, cy_checks + 2), s, font=cf, fill=(0, 0, 0, 120))
        d.text((x, cy_checks), s, font=cf, fill=rgba((255, 255, 255), 0.45 + 0.55 * on))
        x += w + 46
    caption(img, ['I let an app', '*scan* my face.'], t, 0.05, 104, CREAM, 150, accent=GOLD, shadow=True)
    flash = 1 - out_cubic((t - 2.45) / 0.35) if t >= 2.45 else 0
    if flash > 0:
        img.alpha_composite(Image.new('RGBA', (W, H), rgba((255, 255, 255), flash)))
    return img


def sweep_y(p):
    top, bottom = FACE_BOX[1] - 60, FACE_BOX[3] + 60
    return lerp(top, bottom, in_out_cubic(p))


def scan_line(img, y):
    band = Image.new('RGBA', (W, 70), (0, 0, 0, 0))
    bd = ImageDraw.Draw(band)
    for k in range(70):
        bd.line((0, k, W, k), fill=(255, 255, 255, round(55 * k / 70)))
    img.alpha_composite(band, (0, round(y) - 70))
    ImageDraw.Draw(img).line((0, y, W, y), fill=(255, 255, 255, 230), width=3)


def scene_map(t):
    img = DIM.copy()
    p = t / 1.3
    y = sweep_y(p)
    h = clamp(round(y), 1, H)
    img.alpha_composite(MESH.crop((0, 0, W, h)), (0, 0))
    if p < 1:
        scan_line(img, y)
    img.alpha_composite(TOP_SHADE)
    caption(img, ['It mapped', f'*{len(PTS)} points* of my face.'], t, 0.1, 92, CREAM, 150,
            accent=GOLD, shadow=True)
    return img


LENS_STEP = 1.2


def scene_lenses(t):
    i = min(len(LENS_ORDER) - 1, int(t // LENS_STEP))
    name, word = LENS_ORDER[i]
    lt = t - i * LENS_STEP
    prev = LENS_FRAMES[LENS_ORDER[i - 1][0]] if i > 0 else DIM
    img = prev.copy()
    y = sweep_y(lt / 0.5)
    h = clamp(round(y), 1, H)
    img.alpha_composite(LENS_FRAMES[name].crop((0, 0, W, h)), (0, 0))
    if lt < 0.5:
        scan_line(img, y)
    img.alpha_composite(TOP_SHADE)
    d = ImageDraw.Draw(img)
    caption(img, ['It measured'], t, 0.05, 84, CREAM, 150, shadow=True)
    p = out_cubic(lt / 0.3)
    wf = font(800, 124)
    sh = Image.new('RGBA', (W, 220), (0, 0, 0, 0))
    text_center(ImageDraw.Draw(sh), (540, 30), word, wf, (0, 0, 0, round(200 * p)))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(10)), (0, 230 + round((1 - p) * 60)))
    text_center(d, (540, 256 + (1 - p) * 60), word, wf, rgba(LENS[name], p))
    # Lens names along the bottom, like the app's.
    tf = font(500, 36)
    labels = [n.capitalize() for n, _ in LENS_ORDER]
    widths = [tf.getlength(s) for s in labels]
    x = 540 - (sum(widths) + 3 * 50) / 2
    for k, (s, w) in enumerate(zip(labels, widths)):
        on = k == i
        f = font(700 if on else 400, 36)
        d.text((x + 2, 1452), s, font=f, fill=(0, 0, 0, 140))
        d.text((x, 1450), s, font=f, fill=rgba((255, 255, 255), 1 if on else 0.6))
        x += w + 50
    return img


def scene_score(t):
    img = BLUR_BG.copy()
    d = ImageDraw.Draw(img)
    caption(img, ['My glow,', '*measured.*'], t, 0.05, 96, CREAM, 170, accent=GOLD)
    cx, cy, r = 540, 930, 320
    v = out_cubic((t - 0.25) / 1.45)
    lit = round(72 * RAD['score'] / 100 * v)
    for i in range(72):
        a = -math.pi / 2 + i / 72 * math.tau
        major = i % 6 == 0
        ln = 40 if major else 26
        dx, dy = math.cos(a), math.sin(a)
        d.line((cx + dx * r, cy + dy * r, cx + dx * (r - ln), cy + dy * (r - ln)),
               fill=rgba(CREAM, 1 if i < lit else 0.16), width=6 if major else 4)
    text_center(d, (540, 790), 'RADIANCE', font(600, 30), rgba(CREAM, 0.6))
    text_center(d, (540, 820), f'{round(RAD["score"] * v)}', font(200, 230), (*CREAM, 255))
    p = out_cubic((t - 1.9) / 0.4)
    if p > 0:
        y = 1340 + (1 - p) * 30
        d.line((150, y, 930, y), fill=rgba(CREAM, 0.18 * p), width=2)
        parts = (('EVENNESS', RAD['evenness']), ('CLARITY', RAD['clarity']), ('SHEEN', RAD['sheen']))
        for k, (lab, val) in enumerate(parts):
            x = 280 + k * 260
            if k:
                d.line((x - 130, y + 30, x - 130, y + 140), fill=rgba(CREAM, 0.18 * p), width=2)
            text_center(d, (x, y + 34), lab, font(600, 26), rgba(CREAM, 0.55 * p))
            text_center(d, (x, y + 70), str(val), font(300, 64), rgba(CREAM, p))
    return img


def glow_tip():
    """The app's own tip for this reading: aimed at its weakest part."""
    weakest = min(('evenness', 'clarity', 'sheen'), key=lambda k: RAD[k])
    return {
        'clarity': ['Calm active spots first.', 'They cost the most', '*glow.*'],
        'sheen': ['For more glow:', 'a hydrating serum', 'under a light', '*moisturiser.*'],
        'evenness': ['To even it out:', 'daily SPF, with', 'vitamin C or', '*niacinamide.*'],
    }[weakest]


def scene_tip(t):
    img = BLUR_BG.copy()
    d = ImageDraw.Draw(img)
    p = out_cubic(t / 0.4)
    text_center(d, (540, 520), 'ITS ADVICE FOR MY SKIN', font(600, 34), rgba(CREAM, 0.6 * p))
    caption(img, glow_tip(), t, 0.15, 104, CREAM, 640, accent=GOLD, gap=0.1)
    return img


def phone_scene(lines, screen):
    def render(t):
        img = SAGE_BG.copy()
        caption(img, lines, t, 0.05, 80, INK, 170, accent=LEAF)
        p = out_cubic(t / 0.5)
        paste_phone(img, SCREENS[screen], 540, 540 + (1 - p) * 520 + math.sin(t * 1.3) * 6)
        return img
    return render


def scene_day_one(t):
    img = DIM.copy()
    img.alpha_composite(MESH_QUIET)
    img.alpha_composite(TOP_SHADE)
    bottom = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ba = np.clip((np.linspace(0, 1, H) - 0.55) / 0.45, 0, 1) ** 1.4
    arr = np.zeros((H, W, 4), dtype=np.uint8)
    arr[..., 3] = (ba * 200)[:, None].astype(np.uint8)
    img.alpha_composite(Image.fromarray(arr, 'RGBA'))
    d = ImageDraw.Draw(img)
    # Stamp: the date-card look of a progress series.
    p = out_back((t - 0.1) / 0.45)
    if t > 0.1:
        stamp = Image.new('RGBA', (520, 250), (0, 0, 0, 0))
        sd = ImageDraw.Draw(stamp)
        sd.rounded_rectangle((0, 0, 519, 249), 36, fill=(*CHARCOAL, 225))
        text_center(sd, (260, 26), 'DAY 1', font(800, 104), (*CREAM, 255))
        text_center(sd, (260, 160), f'Radiance {RAD["score"]}', font(400, 46), (*GOLD, 255))
        sc = max(0.01, lerp(1.4, 1.0, p))
        stamp = stamp.resize((round(520 * sc), round(250 * sc)), Image.BICUBIC)
        stamp.putalpha(stamp.getchannel('A').point(lambda v: v * clamp(p)))
        img.alpha_composite(stamp, (round(540 - stamp.width / 2), round(1290 - stamp.height / 2)))
    caption(img, ['Week 12 scan:', 'same light,', '*no filters.*'], t, 0.7, 92, CREAM, 150,
            accent=GOLD, shadow=True)
    q = out_cubic((t - 1.9) / 0.4)
    if q > 0:
        text_center(d, (540, 1480), 'Follow along', font(700, 48), rgba(CREAM, q))
    return img


def scene_end(t):
    img = Image.new('RGBA', (W, H), (*CHARCOAL, 255))
    d = ImageDraw.Draw(img)
    p = out_cubic(t / 0.6)
    lg = logo.resize((620, round(620 * logo.height / logo.width)), Image.LANCZOS)
    sc = lerp(0.92, 1, p)
    lg = lg.resize((round(lg.width * sc), round(lg.height * sc)), Image.LANCZOS)
    lg.putalpha(lg.getchannel('A').point(lambda v: v * p))
    img.alpha_composite(lg, (round(540 - lg.width / 2), round(640 - lg.height / 2)))
    caption(img, ['Your skin,', 'measured.'], t, 0.35, 110, CREAM, 820, gap=0.18, weight=300)
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
    (0.0, 3.2, scene_scan),
    (3.2, 5.2, scene_map),
    (5.2, 10.0, scene_lenses),
    (10.0, 13.2, scene_score),
    (13.2, 15.8, scene_tip),
    (15.8, 18.6, phone_scene(['Then it built my', '*12-week plan.*'], 'plan')),
    (18.6, 21.2, phone_scene(['and checked my shelf', 'for *clashes.*'], 'shelf')),
    (21.2, 24.8, scene_day_one),
    (24.8, DUR, scene_end),
]
# Cuts inside the scan (scan → map → lenses) are hard cuts on the flash
# and sweep; the rest whip.
WHIP = 0.26
HARD = {1, 2}


def frame(t):
    idx = max(i for i, s in enumerate(SCENES) if t >= s[0])
    start, _, fn = SCENES[idx]
    cur = fn(t - start)
    if idx > 0 and idx not in HARD and t - start < WHIP:
        e = in_out_cubic((t - start) / WHIP)
        pstart, _, pfn = SCENES[idx - 1]
        prev = pfn(t - pstart)
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
        if i < n:
            mixl[i:j] += sig[: j - i] * gain

    def env(length, attack=0.005, decay=6.0):
        x = np.arange(int(length * SR)) / SR
        return np.minimum(1, x / attack) * np.exp(-x * decay)

    def thump(at, gain=0.8):
        x = np.arange(int(0.45 * SR)) / SR
        f = 55 + 70 * np.exp(-x * 18)
        add(at, np.sin(2 * np.pi * np.cumsum(f) / SR) * env(0.45, 0.002, 7), gain)

    def tick(at, freq=2200, gain=0.25):
        x = np.arange(int(0.05 * SR)) / SR
        add(at, np.sin(2 * np.pi * freq * x) * env(0.05, 0.001, 90), gain)

    def whoosh(at, length=0.32, gain=0.2):
        m = int(length * SR)
        noise = np.convolve(rng.standard_normal(m), np.ones(18) / 18, mode='same')
        add(at - length * 0.4, noise * np.sin(np.linspace(0, np.pi, m)) ** 2, gain)

    def sweep(at, length=1.2, gain=0.08):
        x = np.arange(int(length * SR)) / SR
        f = 300 + 900 * x / length
        add(at, np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * x / length) ** 2, gain)

    def chime(at, gain=0.22):
        x = np.arange(int(1.6 * SR)) / SR
        sig = sum(np.sin(2 * np.pi * f * x) * a for f, a in ((880, 1), (1318.5, .55), (1760, .25)))
        add(at, sig * env(1.6, 0.004, 3.2), gain)

    def shutter(at):
        add(at, rng.standard_normal(int(0.06 * SR)) * env(0.06, 0.001, 70), 0.35)
        tick(at + 0.07, 1200, 0.25)

    pad = np.zeros(n)
    for f, a in ((110, .5), (164.81, .35), (220, .3), (277.18, .2), (329.63, .16)):
        pad += a * np.sin(2 * np.pi * f * tt + f) * (0.85 + 0.15 * np.sin(2 * np.pi * 0.2 * tt + f))
    mixl += pad * np.minimum(1, tt / 1.5) * np.minimum(1, (DUR - tt) / 2.0) * 0.05

    thump(0.05, 0.7)
    for at in (1.0, 1.22, 1.44):
        tick(at, 2400, 0.3)
    shutter(2.45)
    sweep(3.2, 1.3)
    for k in range(4):
        whoosh(5.2 + k * LENS_STEP, 0.4, 0.15)
    for s, _, _ in SCENES[3:]:
        whoosh(s)
    for i in range(1, round(55 * RAD['score'] / 76)):
        v = i / 55
        tick(10.0 + 0.25 + (1 - (1 - v) ** (1 / 3)) * 1.45, 1900 + 600 * v, 0.12)
    chime(10.0 + 1.75, 0.18)
    thump(21.3, 0.6)
    chime(24.8 + 1.2, 0.24)

    peak = np.max(np.abs(mixl)) or 1
    pcm = (mixl / peak * 0.89 * 32767).astype(np.int16)
    path = OUT.with_suffix('.wav')
    with wave.open(str(path), 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(np.repeat(pcm[:, None], 2, axis=1).tobytes())
    return path


# ── Output ─────────────────────────────────────────────────────────────

if STILLS:
    for s in STILLS:
        frame(s).save(OUT.parent / f'still_{s:05.2f}.png')
    print('stills written')
    sys.exit(0)

import imageio_ffmpeg  # noqa: E402

wav = audio()
proc = subprocess.Popen(
    [imageio_ffmpeg.get_ffmpeg_exe(), '-y', '-loglevel', 'error',
     '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}', '-r', str(FPS), '-i', '-',
     '-i', str(wav),
     '-c:v', 'libx264', '-preset', 'slow', '-crf', '20', '-pix_fmt', 'yuv420p', '-profile:v', 'high',
     '-c:a', 'aac', '-b:a', '160k', '-shortest', '-movflags', '+faststart', str(OUT)],
    stdin=subprocess.PIPE)
frames = int(DUR * FPS)
for k in range(frames):
    proc.stdin.write(frame(k / FPS).tobytes())
    if k % 120 == 0:
        print(f'{k}/{frames}', flush=True)
proc.stdin.close()
proc.wait()
wav.unlink()
print('done', OUT)
