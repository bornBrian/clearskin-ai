"""Renders ClearSkin ad 03 — the premium cut. 23 seconds, 1080x1920.

Calm and editorial: licensed photography, slow push-ins, crossfades, light
type that fades in, film grain, and a piano track with every cut on its
beat. The scan is a demonstration on a model (labelled "Demo scan"); the
mesh and lens maps are the app engine's real readings of that photo. No
first-person claims and no results are attributed to her.

Inputs (marketing/ads/source):
  model/model.jpg + model/data   9:16 portrait and its engine export
  broll/*.jpg                     licensed Unsplash photography
  clean-soul.mp3                  "Clean Soul", Kevin MacLeod (incompetech.com), CC BY 4.0

  python tool/ads/render_premium_ad.py <out.mp4> [--stills 1,5]
"""

import json
import math
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / 'marketing/ads/source'
W, H, FPS, DUR = 1080, 1920, 30, 23.0
MUSIC_START = 87.0  # its piano pulses then land at 4.0, 12.5 and 22.0

CHARCOAL = (35, 35, 33)
CREAM = (243, 230, 202)
INK = (28, 26, 23)
WHITE = (255, 255, 255)
LENS = {'radiance': (255, 226, 174), 'redness': (255, 128, 108), 'tone': (233, 169, 85)}

OUT = Path(sys.argv[1])
STILLS = []
if '--stills' in sys.argv:
    STILLS = [float(x) for x in sys.argv[sys.argv.index('--stills') + 1].split(',')]

_fonts = {}


def font(weight, size):
    key = (weight, size)
    if key not in _fonts:
        name = {200: 'ExtraLight', 300: 'Light', 400: 'Regular', 500: 'Medium',
                600: 'SemiBold', 700: 'Bold'}[weight]
        _fonts[key] = ImageFont.truetype(str(ROOT / f'assets/fonts/PlusJakartaSans-{name}.ttf'), size)
    return _fonts[key]


def clamp(v, lo=0.0, hi=1.0):
    return max(lo, min(hi, v))


def ease(p):
    """Slow-in, slow-out: everything in this cut moves gently."""
    p = clamp(p)
    return p * p * (3 - 2 * p)


def out_quart(p):
    p = clamp(p)
    return 1 - (1 - p) ** 4


def lerp(a, b, t):
    return a + (b - a) * t


def rgba(c, a):
    return (*c, round(255 * clamp(a)))


# ── Type ───────────────────────────────────────────────────────────────


def tracked(d, xy, s, f, fill, spacing):
    """Letter-spaced uppercase, for the small labels."""
    x, y = xy
    for ch in s:
        d.text((x, y), ch, font=f, fill=fill)
        x += f.getlength(ch) + spacing


def tracked_width(s, f, spacing):
    return sum(f.getlength(ch) for ch in s) + spacing * (len(s) - 1)


def text_block(img, t, t0, lines, x, y, size, color, weight=300, eyebrow=None,
               align='left', shadow=False, line_h=1.16):
    """A short block that fades up as one, the way print type would
    arrive: no bouncing words."""
    p = out_quart((t - t0) / 0.9)
    if p <= 0:
        return
    layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    dy = (1 - p) * 26
    yy = y + dy
    if eyebrow:
        ef = font(600, 26)
        ew = tracked_width(eyebrow, ef, 5)
        ex = x if align == 'left' else (W - ew) / 2 if align == 'center' else x - ew
        tracked(d, (ex, yy), eyebrow, ef, rgba(color, 0.75 * p), 5)
        yy += 58
    f = font(weight, size)
    for k, line in enumerate(lines):
        lw = f.getlength(line)
        lx = x if align == 'left' else (W - lw) / 2 if align == 'center' else x - lw
        d.text((lx, yy + k * size * line_h), line, font=f, fill=rgba(color, p))
    if shadow:
        sh = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        sh.putalpha(layer.getchannel('A').point(lambda v: v * 0.55))
        img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(14)))
    img.alpha_composite(layer)


# ── Photography ────────────────────────────────────────────────────────


class Plate:
    """A photo prepared for slow push-ins: cover-fitted at 1.2× the frame,
    then cropped and scaled per frame toward a focal point."""

    def __init__(self, path, focus=(0.5, 0.5), over=1.2):
        im = Image.open(path).convert('RGB')
        s = max(W * over / im.width, H * over / im.height)
        self.im = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
        self.focus = focus

    def frame(self, zoom):
        """zoom 1 = the whole frame's worth of photo; higher pushes in."""
        iw, ih = self.im.size
        # The largest frame-shaped window inside the photo's central 1/1.2.
        cw = min(iw, ih * W / H) / 1.2 / zoom
        ch = cw * H / W
        fx, fy = self.focus[0] * iw, self.focus[1] * ih
        x0 = clamp(fx - cw / 2, 0, iw - cw)
        y0 = clamp(fy - ch / 2, 0, ih - ch)
        return self.im.resize((W, H), Image.BICUBIC, box=(x0, y0, x0 + cw, y0 + ch)).convert('RGBA')


MACRO = Plate(SRC / 'broll/skin_macro.jpg', focus=(0.48, 0.42))
DROPPER = Plate(SRC / 'broll/dropper_amber.jpg', focus=(0.42, 0.62))
CREAM_BG = Plate(SRC / 'broll/cream_beige.jpg', focus=(0.45, 0.5))

# The model: the photo, its mesh and its lens maps share one frame space,
# so they push in together.
mesh = json.loads((SRC / 'model/data/mesh.json').read_text())
RAD = mesh['radiance']
PTS, TRIS, CONT = mesh['points'], mesh['tris'], mesh['contours']
fxs = [p[0] for p in CONT['face']]
fys = [p[1] for p in CONT['face']]
FACE = ((min(fxs) + max(fxs)) / 2, (min(fys) + max(fys)) / 2)
FACE_TOP, FACE_BOTTOM = min(fys), max(fys)

BIG = 1.12  # model layers are rendered this much larger than the frame
BW, BH = round(W * BIG), round(H * BIG)
MODEL = Image.open(SRC / 'model/model.jpg').convert('RGB').resize((BW, BH), Image.LANCZOS)


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
    s = 2
    img = Image.new('RGBA', (BW * s, BH * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def px(p):
        return (p[0] * BW * s, p[1] * BH * s)

    for a, b, c in TRIS:
        d.line([px(PTS[a]), px(PTS[b]), px(PTS[c]), px(PTS[a])], fill=(255, 255, 255, 55), width=2)
    for k in ('leftEye', 'rightEye'):
        d.line([px(p) for p in catmull(CONT[k])], fill=(255, 255, 255, 170), width=3)
    lips = CONT['upperLipTop'] + CONT['lowerLipBottom'][::-1]
    d.line([px(p) for p in catmull(lips)], fill=(255, 255, 255, 150), width=3)
    d.line([px(p) for p in catmull(CONT['face'])], fill=(255, 255, 255, 120), width=3)
    for p in PTS:
        x, y = px(p)
        d.ellipse((x - 2.5, y - 2.5, x + 2.5, y + 2.5), fill=(255, 255, 255, 200))
    return img.resize((BW, BH), Image.LANCZOS)


MESH = mesh_layer()
MESH_FAINT = MESH.copy()
MESH_FAINT.putalpha(MESH.getchannel('A').point(lambda v: v * 0.3))


def lens_plate(name):
    """The model with one lens on, as light (radiance) or colour."""
    m = Image.open(SRC / f'model/data/lens_{name}.png').convert('L').resize((BW, BH), Image.BICUBIC)
    gain = {'radiance': 1.1, 'redness': 3.0, 'tone': 2.6}[name]
    a = np.clip(np.asarray(m, dtype=np.float32) / 255 * gain, 0, 1)
    if name == 'radiance':
        a = a ** 2.2
    a = np.asarray(Image.fromarray((a * 255).astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(9 if name == 'radiance' else 5)), dtype=np.float32) / 255
    base = np.asarray(MODEL, dtype=np.float32) * 0.9
    col = np.array(LENS[name], dtype=np.float32)
    if name == 'radiance':
        glow = col * a[..., None] * 0.6
        out = 255 - (255 - base) * (255 - glow) / 255
    else:
        k = (a * 0.8)[..., None]
        out = base * (1 - k) + col * k
    im = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), 'RGB').convert('RGBA')
    im.alpha_composite(MESH_FAINT)
    return im


MODEL_RGBA = MODEL.convert('RGBA')
LENSES = [('radiance', 'RADIANCE', f'{RAD["score"]}'), ('redness', 'REDNESS', ''), ('tone', 'DARK MARKS', '')]
LENS_PLATES = {k: lens_plate(k) for k, _, _ in LENSES}


def model_view(layer, zoom):
    """Crop the big model layer to the frame, pushed in toward the face."""
    cw, ch = BW / zoom / BIG, BH / zoom / BIG
    fx, fy = FACE[0] * BW, FACE[1] * BH * 0.98
    x0 = clamp(fx - cw / 2, 0, BW - cw)
    y0 = clamp(fy - ch / 2, 0, BH - ch)
    return layer.resize((W, H), Image.BICUBIC, box=(x0, y0, x0 + cw, y0 + ch))


# Gentle top and bottom shade, so type reads on photos.
_g = np.linspace(0, 1, H)
_shade = np.zeros((H, W, 4), dtype=np.uint8)
_shade[..., 3] = ((np.clip(1 - _g / 0.3, 0, 1) ** 1.8 * 150) + (np.clip((_g - 0.62) / 0.38, 0, 1) ** 1.6 * 170)
                  ).clip(0, 255)[:, None].astype(np.uint8)
SHADE = Image.fromarray(_shade, 'RGBA')

# ── Scenes ─────────────────────────────────────────────────────────────


def s_macro(t):
    img = MACRO.frame(lerp(1.0, 1.1, ease(t / 4.4)))
    img.alpha_composite(SHADE)
    text_block(img, t, 0.5, ['Look closer.'], 90, 1300, 128, WHITE, weight=200,
               eyebrow='CLEARSKIN', shadow=True)
    return img


def s_scan(t):
    zoom = lerp(1.0, 1.07, ease(t / 4.5))
    img = model_view(MODEL_RGBA, zoom)
    # One slow pass of the scan line leaves the tracking on the face.
    p = ease((t - 0.35) / 1.6)
    if p > 0:
        top, bottom = (FACE_TOP - 0.06) * H, (FACE_BOTTOM + 0.05) * H
        y = lerp(top, bottom, p)
        m = model_view(MESH, zoom)
        img.alpha_composite(m.crop((0, 0, W, max(1, round(y)))))
        if p < 1:
            band = Image.new('RGBA', (W, 90), (0, 0, 0, 0))
            bd = ImageDraw.Draw(band)
            for k in range(90):
                bd.line((0, k, W, k), fill=(255, 255, 255, round(40 * (k / 90) ** 2)))
            img.alpha_composite(band, (0, round(y) - 90))
            ImageDraw.Draw(img).line((0, y, W, y), fill=(255, 255, 255, 150), width=2)
    img.alpha_composite(SHADE)
    text_block(img, t, 0.6, ['It maps 134 points', 'of your face.'], 90, 170, 76, WHITE,
               eyebrow='A TEN-SECOND SCAN', shadow=True)
    demo(img, t)
    return img


def demo(img, t):
    d = ImageDraw.Draw(img)
    f = font(600, 22)
    s = 'DEMO SCAN'
    tracked(d, (W - 80 - tracked_width(s, f, 4), 1620), s, f, rgba(WHITE, 0.7 * ease(t / 0.6)), 4)


LENS_STEP = 1.5


def s_lenses(t):
    zoom = 1.07 + 0.03 * ease(t / 4.5)
    i = min(len(LENSES) - 1, int(t // LENS_STEP))
    lt = t - i * LENS_STEP
    cur = model_view(LENS_PLATES[LENSES[i][0]], zoom)
    if lt < 0.45:
        prev = model_view(LENS_PLATES[LENSES[i - 1][0]] if i else MODEL_RGBA.copy(), zoom)
        if not i:
            prev.alpha_composite(model_view(MESH_FAINT, zoom))
        img = Image.blend(prev, cur, ease(lt / 0.45))
    else:
        img = cur
    img.alpha_composite(SHADE)
    text_block(img, t, 0.3, ['And measures what', 'the eye can miss.'], 90, 170, 76, WHITE, shadow=True)
    # The lens name and reading, low on the frame.
    _, label, val = LENSES[i]
    a = ease(lt / 0.35)
    layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    tracked(d, (90, 1450), label, font(600, 28), rgba(WHITE, a), 6)
    if val:
        d.text((90, 1490), val, font=font(200, 120), fill=rgba(WHITE, a))
    sh = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    sh.putalpha(layer.getchannel('A').point(lambda v: v * 0.6))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(12)))
    img.alpha_composite(layer)
    demo(img, 1)
    return img


def s_plan(t):
    img = DROPPER.frame(lerp(1.0, 1.08, ease(t / 4.0)))
    text_block(img, t, 0.45, ['Then it builds a', '12-week plan', 'around your skin.'], 90, 190, 80, INK,
               eyebrow='YOUR PLAN')
    return img


REPORT = Image.open(ROOT / 'design/renders/05-scan-report.png').convert('RGB').crop((0, 0, 1170, 1520))
REPORT = REPORT.resize((720, round(720 * REPORT.height / REPORT.width)), Image.LANCZOS)
REPORT_MASK = Image.new('L', REPORT.size, 0)
ImageDraw.Draw(REPORT_MASK).rounded_rectangle((0, 0, REPORT.width - 1, REPORT.height - 1), 44, fill=255)


def s_track(t):
    img = CREAM_BG.frame(1.15).filter(ImageFilter.GaussianBlur(18))
    img = Image.blend(img, Image.new('RGBA', (W, H), (*CREAM, 255)), 0.35)
    p = out_quart((t - 0.15) / 1.1)
    y = 620 + (1 - p) * 80
    sh = Image.new('RGBA', (REPORT.width + 200, REPORT.height + 200), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((100, 140, REPORT.width + 100, REPORT.height + 110), 44,
                                         fill=(40, 30, 20, round(70 * p)))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(40)), (round(540 - REPORT.width / 2) - 100, round(y) - 100))
    card = Image.new('RGBA', REPORT.size, (0, 0, 0, 0))
    card.paste(REPORT, (0, 0), REPORT_MASK)
    card.putalpha(card.getchannel('A').point(lambda v: v * p))
    img.alpha_composite(card, (round(540 - REPORT.width / 2), round(y)))
    text_block(img, t, 0.3, ['Week by week,', 'see what’s working.'], 90, 190, 80, INK)
    return img


LOGO = Image.open(ROOT / 'assets/brand/logo-lockup.png').convert('RGBA')


def s_end(t):
    img = CREAM_BG.frame(lerp(1.12, 1.18, ease(t / 4)))
    img = Image.blend(img, Image.new('RGBA', (W, H), (*CREAM, 255)), 0.55)
    p = out_quart((t - 0.2) / 1.0)
    lg = LOGO.resize((560, round(560 * LOGO.height / LOGO.width)), Image.LANCZOS)
    lg.putalpha(lg.getchannel('A').point(lambda v: v * p))
    img.alpha_composite(lg, (round(540 - lg.width / 2), 560 + round((1 - p) * 20)))
    text_block(img, t, 0.7, ['Your skin,', 'measured.'], 0, 860, 116, INK, weight=200, align='center')
    q = out_quart((t - 1.5) / 0.9)
    if q > 0:
        d = ImageDraw.Draw(img)
        f = font(600, 40)
        s = 'Your first scan is free'
        pw = f.getlength(s) + 96
        d.rounded_rectangle((540 - pw / 2, 1220, 540 + pw / 2, 1316), 48, fill=rgba(INK, q))
        d.text((540 - f.getlength(s) / 2, 1243), s, font=f, fill=rgba(CREAM, q))
        sf = font(400, 30)
        for k, line in enumerate(('On Google Play', 'Photos saved only on your phone')):
            d.text((540 - sf.getlength(line) / 2, 1370 + k * 46), line, font=sf, fill=rgba(INK, q * (0.85 - k * 0.3)))
    return img


SCENES = [
    (0.0, 4.0, s_macro),
    (4.0, 8.0, s_scan),
    (8.0, 12.5, s_lenses),
    (12.5, 16.0, s_plan),
    (16.0, 19.0, s_track),
    (19.0, DUR, s_end),
]
FADE = 0.5

# Film finish: a soft vignette and fine grain, the same on every frame.
_yy, _xx = np.mgrid[0:H, 0:W]
_r = np.sqrt(((_xx - W / 2) / (W / 2)) ** 2 + ((_yy - H / 2) / (H / 2)) ** 2)
VIGNETTE = (1 - 0.16 * np.clip((_r - 0.55) / 0.85, 0, 1) ** 1.5)[..., None].astype(np.float32)
_rng = np.random.default_rng(3)
# Fresh grain every other frame: reads as film, and keeps the file a sane
# size (grain that changes every frame is the costliest thing to encode).
_GRAIN = [np.repeat(np.repeat(_rng.normal(0, 2.6, (H // 2, W // 2, 1)).astype(np.float32), 2, axis=0), 2, axis=1)
          for _ in range(12)]
_frame_no = [0]


def finish(img):
    a = np.asarray(img.convert('RGB'), dtype=np.float32) * VIGNETTE
    a += _GRAIN[(_frame_no[0] // 2) % len(_GRAIN)]
    _frame_no[0] += 1
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), 'RGB')


def frame(t):
    idx = max(i for i, s in enumerate(SCENES) if t >= s[0])
    start, _, fn = SCENES[idx]
    cur = fn(t - start)
    if idx > 0 and t - start < FADE:
        pstart, _, pfn = SCENES[idx - 1]
        cur = Image.blend(pfn(t - pstart).convert('RGBA'), cur.convert('RGBA'), ease((t - start) / FADE))
    return finish(cur)


if STILLS:
    for s in STILLS:
        frame(s).save(OUT.parent / f'still_{s:05.2f}.png')
    print('stills written')
    sys.exit(0)

import imageio_ffmpeg  # noqa: E402

ff = imageio_ffmpeg.get_ffmpeg_exe()
proc = subprocess.Popen(
    [ff, '-y', '-loglevel', 'error',
     '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}', '-r', str(FPS), '-i', '-',
     '-ss', str(MUSIC_START), '-t', str(DUR), '-i', str(SRC / 'clean-soul.mp3'),
     '-filter:a', f'afade=t=in:st=0:d=0.8,afade=t=out:st={DUR - 1.6}:d=1.6,loudnorm=I=-15:TP=-1.5',
     '-c:v', 'libx264', '-preset', 'slow', '-crf', '21', '-tune', 'film', '-maxrate', '12M', '-bufsize', '24M',
     '-pix_fmt', 'yuv420p', '-profile:v', 'high',
     '-c:a', 'aac', '-b:a', '192k', '-ar', '48000', '-shortest', '-movflags', '+faststart', str(OUT)],
    stdin=subprocess.PIPE)
for k in range(int(DUR * FPS)):
    proc.stdin.write(frame(k / FPS).tobytes())
    if k % 120 == 0:
        print(f'{k}/{int(DUR * FPS)}', flush=True)
proc.stdin.close()
proc.wait()
print('done', OUT)
