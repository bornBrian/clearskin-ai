"""Renders ClearSkin ad 04 — problem → app → proof, TikTok-native.

The format the top app ads use (Cal AI, Fastic): a familiar problem in the
first two seconds, then the app solving it on screen, in plain captions,
cut on the beat. The app footage is the real app, recorded frame by frame
by tool/screenshots/render_screens_test.dart (RECORD=<dir>). The scan is a
labelled demo on a model; her readings are the engine's real measurements.

Inputs (marketing/ads/source):
  rec/<flow>/f_*.png + taps.json   recorded app flows
  model/                           the demo-scan portrait and its landmarks
  broll/*.jpg                      licensed Unsplash product photography
  Funkorama.mp3                    "Funkorama", Kevin MacLeod (incompetech.com), CC BY 4.0

  python tool/ads/render_ugc_ad.py <out.mp4> [--bpm 97.5] [--no-music] [--stills 1,5]
"""

import json
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / 'marketing/ads/source'
W, H, FPS = 1080, 1920, 30
def _arg(name, default=None):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default


# Every cut lands on a beat. --bpm re-times the whole edit for another song;
# --no-music exports a silent track to add that song on the platform (the
# way a licensed trending sound gets added).
BPM = float(_arg('--bpm', 99.4))  # 99.4 = Funkorama
BEAT = 60 / BPM
MUSIC = '--no-music' not in sys.argv
MUSIC_START = 7.0  # where Funkorama's groove kicks in

OUT = Path(sys.argv[1])
STILLS = []
if '--stills' in sys.argv:
    STILLS = [float(x) for x in sys.argv[sys.argv.index('--stills') + 1].split(',')]

INK = (16, 16, 16)
WHITE = (255, 255, 255)
SAGE = (238, 242, 237)
LEAF = (78, 154, 95)

_fonts = {}


def font(weight, size):
    key = (weight, size)
    if key not in _fonts:
        name = {400: 'Regular', 600: 'SemiBold', 700: 'Bold', 800: 'ExtraBold'}[weight]
        _fonts[key] = ImageFont.truetype(str(ROOT / f'assets/fonts/PlusJakartaSans-{name}.ttf'), size)
    return _fonts[key]


def clamp(v, lo=0.0, hi=1.0):
    return max(lo, min(hi, v))


def out_cubic(p):
    p = clamp(p)
    return 1 - (1 - p) ** 3


def lerp(a, b, t):
    return a + (b - a) * t


# ── TikTok-style caption: black text on white rounded boxes, line by line ──


def caption(img, lines, y=250, size=58, pop=1.0):
    """Each line on its own white box, centred, the way TikTok's text tool
    draws it. `pop` (0..1) is the entrance: a quick scale from 0.9."""
    f = font(800, size)
    pad_x, pad_y, gap = 30, 16, 6
    s = lerp(0.9, 1.0, out_cubic(pop / 1.0)) if pop < 1 else 1.0
    layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    yy = y
    line_h = size + 2 * pad_y
    for line in lines:
        tw = f.getlength(line)
        x0 = (W - tw) / 2 - pad_x
        d.rounded_rectangle((x0, yy, x0 + tw + 2 * pad_x, yy + line_h), 20, fill=(255, 255, 255, 255))
        d.text(((W - tw) / 2, yy + pad_y - size * 0.08), line, font=f, fill=(*INK, 255))
        yy += line_h + gap
    if s != 1.0:
        box = layer.getbbox()
        if box:
            crop = layer.crop(box)
            crop = crop.resize((max(1, round(crop.width * s)), max(1, round(crop.height * s))), Image.BICUBIC)
            layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
            cx, cy = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
            layer.alpha_composite(crop, (round(cx - crop.width / 2), round(cy - crop.height / 2)))
        layer.putalpha(layer.getchannel('A').point(lambda v: v * out_cubic(pop / 0.6)))
    img.alpha_composite(layer)


def big_word(img, word, size=150):
    """The montage words: huge, white, with a soft shadow."""
    f = font(800, size)
    layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    tw = f.getlength(word)
    d.text(((W - tw) / 2, 1020), word, font=f, fill=(*WHITE, 255))
    sh = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    sh.putalpha(layer.getchannel('A').point(lambda v: v * 0.6))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(16)))
    img.alpha_composite(layer)


# ── Footage ────────────────────────────────────────────────────────────


def cover(path, w=W, h=H):
    im = Image.open(path).convert('RGB')
    s = max(w / im.width, h / im.height)
    im = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
    x0, y0 = (im.width - w) // 2, (im.height - h) // 2
    return im.crop((x0, y0, x0 + w, y0 + h)).convert('RGBA')


BROLL = {k: cover(SRC / f'broll/{k}.jpg') for k in
         ('dropper_amber', 'serum_pour', 'gel_swirl', 'cream_beige', 'textures', 'skin_macro')}


class Recording:
    """A recorded app flow: frames on demand, plus tap ripples."""

    def __init__(self, name):
        self.dir = SRC / f'rec/{name}'
        self.count = len(list(self.dir.glob('f_*.png')))
        self.taps = json.loads((self.dir / 'taps.json').read_text())
        self._cache = {}

    def frame(self, i):
        i = int(clamp(i, 0, self.count - 1))
        if i not in self._cache:
            if len(self._cache) > 8:
                self._cache.clear()
            self._cache[i] = Image.open(self.dir / f'f_{i:05d}.png').convert('RGBA')
        img = self._cache[i].copy()
        # A finger's touch: a soft circle that lands and fades.
        d = ImageDraw.Draw(img)
        for tap in self.taps:
            k = i - tap['frame']
            if -2 <= k <= 12:
                p = clamp((k + 2) / 14)
                r = lerp(30, 58, out_cubic(p))
                a = (1 - p) * 0.55
                x, y = tap['x'] * W, tap['y'] * H
                d.ellipse((x - r, y - r, x + r, y + r), fill=(255, 255, 255, round(255 * a)),
                          outline=(0, 0, 0, round(80 * a)), width=2)
        return img


REC = {k: Recording(k) for k in ('report', 'plan', 'routine', 'progress')}

# Demo scan on the model, styled exactly as the app's live guide.
MODEL = Image.open(SRC / 'model/model.jpg').convert('RGB')
MODEL = ImageEnhance.Brightness(MODEL).enhance(1.02).resize((round(W * 1.2), round(H * 1.2)), Image.LANCZOS)
_mesh = json.loads((SRC / 'model/data/mesh.json').read_text())
_fx = [p[0] for p in _mesh['contours']['face']]
_fy = [p[1] for p in _mesh['contours']['face']]
FACE_C = ((min(_fx) + max(_fx)) / 2, (min(_fy) + max(_fy)) / 2)
FACE_W, FACE_H = max(_fx) - min(_fx), max(_fy) - min(_fy)


def model_view(zoom):
    """zoom 1 shows the whole portrait; more pushes in on the face."""
    bw, bh = MODEL.size
    cw, ch = bw / 1.2 / zoom, bh / 1.2 / zoom
    x0 = clamp(FACE_C[0] * bw - cw / 2, 0, bw - cw)
    y0 = clamp(FACE_C[1] * bh - ch / 2, 0, bh - ch)
    return MODEL.resize((W, H), Image.BICUBIC, box=(x0, y0, x0 + cw, y0 + ch)).convert('RGBA'), (x0, y0, cw, ch)


def demo_label(img):
    d = ImageDraw.Draw(img)
    f = font(700, 24)
    s = 'DEMO SCAN'
    tw = f.getlength(s)
    d.rounded_rectangle((W - 70 - tw - 24, 1560, W - 70, 1604), 22, fill=(0, 0, 0, 120))
    d.text((W - 70 - tw - 12, 1569), s, font=f, fill=(255, 255, 255, 230))


# ── Scenes (durations in beats) ────────────────────────────────────────


def s_hook(t):
    words = ['Serum.', 'Toner.', 'Retinol.', 'Acids.', 'SPF.', 'Masks.']
    shots = ['dropper_amber', 'serum_pour', 'gel_swirl', 'textures', 'cream_beige', 'skin_macro']
    i = min(len(words) - 1, int(t / BEAT))
    lt = t - i * BEAT
    img = BROLL[shots[i]].copy()
    z = lerp(1.08, 1.0, out_cubic(lt / 0.2))  # punch-in on every beat
    if z != 1:
        img = img.resize((round(W * z), round(H * z)), Image.BICUBIC).crop(
            (round((W * z - W) / 2), round((H * z - H) / 2), round((W * z - W) / 2) + W, round((H * z - H) / 2) + H))
    img = Image.blend(img, Image.new('RGBA', (W, H), (0, 0, 0, 255)), 0.18)
    big_word(img, words[i])
    # On screen from the very first frame: it's the thumbnail and the hook.
    caption(img, ['Still buying skincare', 'by guessing?'])
    return img


def s_problem(t):
    img = BROLL['gel_swirl'].copy()
    z = lerp(1.0, 1.06, t / (4 * BEAT))
    img = img.resize((round(W * z), round(H * z)), Image.BICUBIC).crop(
        (round((W * z - W) / 2), round((H * z - H) / 2), round((W * z - W) / 2) + W, round((H * z - H) / 2) + H))
    img = Image.blend(img, Image.new('RGBA', (W, H), (0, 0, 0, 255)), 0.25)
    caption(img, ['Some of it might even', 'cancel each other out.'], y=760, pop=t / 0.35)
    return img


def s_scan(t):
    zoom = lerp(1.0, 1.18, out_cubic((t - 0.2) / 0.8))
    img, (x0, y0, cw, ch) = model_view(zoom)
    d = ImageDraw.Draw(img)
    bw, bh = MODEL.size

    def to_screen(nx, ny):
        return ((nx * bw - x0) / cw * W, (ny * bh - y0) / ch * H)

    cx, cy = to_screen(*FACE_C)
    fw = FACE_W * bw / cw * W * (1.18 / zoom)
    fh = FACE_H * bh / ch * H * (1.18 / zoom)
    box = (cx - fw * 0.6, cy - fh * 0.62, cx + fw * 0.6, cy + fh * 0.58)
    ready = t >= 1.55
    if ready:
        d.ellipse(box, outline=(124, 196, 149, 140), width=7)
        d.arc(box, -90, -90 + 360 * out_cubic((t - 1.55) / 0.7), fill=(124, 196, 149, 255), width=10)
    else:
        for k in range(56):
            a0 = k / 56 * 360
            d.arc(box, a0, a0 + 3.6, fill=(255, 255, 255, 220), width=5)
    hint = 'Perfect — hold it there' if ready else ('Hold still' if t >= 0.95 else 'Move a little closer')
    pf = font(700, 38)
    pw = pf.getlength(hint) + 72
    hy = 1440
    d.rounded_rectangle((540 - pw / 2, hy, 540 + pw / 2, hy + 80), 40,
                        fill=(78, 154, 95, 255) if ready else (0, 0, 0, 170))
    d.text((540 - pf.getlength(hint) / 2, hy + 16), hint, font=pf, fill=(255, 255, 255, 255))
    cf = font(700, 28)
    labels = ['LIGHT', 'POSITION', 'STILL']
    widths = [cf.getlength(s) for s in labels]
    x = 540 - (sum(widths) + 2 * 44) / 2
    for s, w, at in zip(labels, widths, (1.0, 1.2, 1.4)):
        on = out_cubic((t - at) / 0.12)
        d.text((x + 2, hy + 104), s, font=cf, fill=(0, 0, 0, 110))
        d.text((x, hy + 102), s, font=cf, fill=(255, 255, 255, round(255 * (0.45 + 0.55 * on))))
        x += w + 44
    demo_label(img)
    caption(img, ['ClearSkin scans your face', 'in 10 seconds'], pop=t / 0.35)
    flash = 1 - out_cubic((t - 2.55) / 0.3) if t >= 2.55 else 0
    if flash > 0:
        img.alpha_composite(Image.new('RGBA', (W, H), (255, 255, 255, round(255 * flash))))
    return img


def rec_scene(name, start_frame, lines, y=250):
    def render(t):
        img = REC[name].frame(start_frame + t * FPS)
        caption(img, lines, y=y, pop=t / 0.35)
        return img
    return render


CHARCOAL = (35, 35, 33)
CREAM = (243, 230, 202)


def s_cta(t):
    img = Image.new('RGBA', (W, H), (*CHARCOAL, 255))
    d = ImageDraw.Draw(img)
    logo = Image.open(ROOT / 'assets/brand/logo-lockup-inverse.png').convert('RGBA')
    logo = logo.resize((640, round(640 * logo.height / logo.width)), Image.LANCZOS)
    p = out_cubic(t / 0.4)
    logo.putalpha(logo.getchannel('A').point(lambda v: v * p))
    img.alpha_composite(logo, (round(540 - logo.width / 2), 560))
    # Pre-launch: nothing to download yet, so the ask is to follow.
    caption(img, ['Coming soon'], y=860, size=92, pop=(t - 0.2) / 0.35)
    q = out_cubic((t - 0.7) / 0.35)
    if q > 0:
        sf = font(600, 40)
        line = 'to Google Play'
        d.text((540 - sf.getlength(line) / 2, 1030), line, font=sf, fill=(*CREAM, round(255 * q * 0.85)))
        bf = font(800, 46)
        s = 'Follow for launch day'
        sc = lerp(0.9, 1, q)
        bw, bh = (bf.getlength(s) + 120) * sc, 116 * sc
        d.rounded_rectangle((540 - bw / 2, 1180, 540 + bw / 2, 1180 + bh), bh / 2, fill=(*CREAM, round(255 * q)))
        d.text((540 - bf.getlength(s) / 2, 1180 + bh / 2 - 30), s, font=bf, fill=(*CHARCOAL, round(255 * q)))
    return img


# ── Opening the app: a home screen, one tap, the launch ────────────────

ICON = Image.open(ROOT / 'docs/store/play-icon-512.png').convert('RGBA')
ICON_SIZE = 196
GRID_X = [72 + c * 250 for c in range(4)]
GRID_Y = [520 + r * 300 for r in range(4)]
ICON_AT = (GRID_X[1], GRID_Y[2])  # where ClearSkin sits on the home screen


def _squircle(size, radius):
    m = Image.new('L', (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size - 1, size - 1), radius, fill=255)
    return m


def _home_screen():
    """A calm, out-of-focus home screen; only ClearSkin is sharp."""
    # Wallpaper: a warm product photo, soft as a phone renders it.
    bg = BROLL['cream_beige'].filter(ImageFilter.GaussianBlur(30))
    bg = Image.blend(bg, Image.new('RGBA', (W, H), (238, 234, 224, 255)), 0.25)
    # Tiles go straight onto the wallpaper, then the whole screen is blurred:
    # blurring a transparent layer leaves dark halos at every edge.
    tiles = bg.copy()
    td = ImageDraw.Draw(tiles)
    palette = [(250, 250, 248), (60, 64, 62), (196, 214, 200), (232, 200, 170), (180, 196, 214),
               (246, 236, 214), (90, 110, 98), (220, 222, 226)]
    k = 0
    for y in GRID_Y:
        for x in GRID_X:
            if (x, y) != ICON_AT:
                td.rounded_rectangle((x, y, x + ICON_SIZE, y + ICON_SIZE), 50, fill=(*palette[k % 8], 235))
                td.rounded_rectangle((x + 40, y + ICON_SIZE + 22, x + ICON_SIZE - 40, y + ICON_SIZE + 40), 9,
                                     fill=(40, 36, 32, 90))
            k += 1
    return tiles.filter(ImageFilter.GaussianBlur(16))


HOME = _home_screen()
ICON_TILE = ICON.resize((ICON_SIZE, ICON_SIZE), Image.LANCZOS)
ICON_TILE.putalpha(_squircle(ICON_SIZE, 50))


def s_open(t):
    """One beat on the home screen, a tap, and the icon opens into the app."""
    tap_at, launch_at, launch_len = 0.5, 0.72, 0.6
    # The camera eases in on the icon.
    z = lerp(1.0, 1.08, out_cubic(t / 0.7))
    cx, cy = ICON_AT[0] + ICON_SIZE / 2, ICON_AT[1] + ICON_SIZE / 2
    img = HOME.resize((round(W * z), round(H * z)), Image.BICUBIC)
    ox, oy = cx * z - cx, cy * z - cy
    img = img.crop((round(ox), round(oy), round(ox) + W, round(oy) + H))
    d = ImageDraw.Draw(img)
    if t < launch_at:
        press = 1.0
        if tap_at <= t:
            k = (t - tap_at) / (launch_at - tap_at)
            press = 1 - 0.08 * (1 - abs(2 * k - 1))
        s = round(ICON_SIZE * press)
        tile = ICON_TILE.resize((s, s), Image.LANCZOS)
        img.alpha_composite(tile, (round(cx - s / 2), round(cy - s / 2)))
        f = font(600, 30)
        lw = f.getlength('ClearSkin')
        d.text((cx - lw / 2, ICON_AT[1] + ICON_SIZE + 16), 'ClearSkin', font=f, fill=(*INK, 235))
        if t >= tap_at - 0.05:
            # A soft press: a translucent ring that spreads and fades.
            p = clamp((t - tap_at + 0.05) / 0.4)
            r = lerp(40, 92, out_cubic(p))
            a = (1 - p) * 0.4
            ring = Image.new('RGBA', (W, H), (0, 0, 0, 0))
            ImageDraw.Draw(ring).ellipse((cx - r, cy - r, cx + r, cy + r), fill=(255, 255, 255, round(110 * a)),
                                         outline=(255, 255, 255, round(255 * a)), width=4)
            img.alpha_composite(ring)
        return img
    # Launch: the icon grows into the full screen, the mark settling in the
    # middle, like the phone's own app-open animation.
    p = out_cubic((t - launch_at) / launch_len)
    x0, y0 = lerp(cx - ICON_SIZE / 2, 0, p), lerp(cy - ICON_SIZE / 2, 0, p)
    x1, y1 = lerp(cx + ICON_SIZE / 2, W, p), lerp(cy + ICON_SIZE / 2, H, p)
    d.rounded_rectangle((x0, y0, x1, y1), lerp(50, 0, p), fill=(*CHARCOAL, 255))
    mark = round(lerp(ICON_SIZE, 460, p))
    art = ICON.resize((mark, mark), Image.LANCZOS)
    mcx, mcy = (x0 + x1) / 2, (y0 + y1) / 2
    img.alpha_composite(art, (round(mcx - mark / 2), round(mcy - mark / 2)))
    return img


SCENES = [
    (6, s_hook),
    (4, s_problem),
    (3, s_open),
    (5, s_scan),
    (4, rec_scene('report', 0, ['It scores your skin'])),
    (8, rec_scene('report', 84, ['and shows exactly', 'what’s going on'], y=1100)),
    (4, rec_scene('plan', 40, ['builds your routine'], y=1500)),
    (4, rec_scene('routine', 6, ['keeps you on track'], y=1500)),
    (4, rec_scene('progress', 0, ['and shows it working'], y=1500)),
    (6, s_cta),
]
TIMES = []
_t = 0.0
for beats, fn in SCENES:
    TIMES.append((_t, _t + beats * BEAT, fn))
    _t += beats * BEAT
DUR = _t


def frame(t):
    for start, end, fn in TIMES:
        if t < end or fn is TIMES[-1][2]:
            img = fn(t - start)
            # A small punch-in on every cut, like a phone edit.
            lt = t - start
            if lt < 0.15:
                z = lerp(1.05, 1.0, out_cubic(lt / 0.15))
                img = img.resize((round(W * z), round(H * z)), Image.BICUBIC).crop(
                    (round((W * z - W) / 2), round((H * z - H) / 2),
                     round((W * z - W) / 2) + W, round((H * z - H) / 2) + H))
            return img.convert('RGB')
    raise ValueError(t)


if STILLS:
    for s in STILLS:
        frame(s).save(OUT.parent / f'still_{s:05.2f}.png')
    print('stills written, duration', round(DUR, 2))
    sys.exit(0)

import imageio_ffmpeg  # noqa: E402

audio = (['-ss', str(MUSIC_START), '-t', str(DUR), '-i', str(SRC / 'Funkorama.mp3'),
          '-filter:a', f'afade=t=out:st={DUR - 1.2}:d=1.2,loudnorm=I=-14:TP=-1.5']
         if MUSIC else
         ['-f', 'lavfi', '-t', str(DUR), '-i', 'anullsrc=channel_layout=stereo:sample_rate=48000'])
proc = subprocess.Popen(
    [imageio_ffmpeg.get_ffmpeg_exe(), '-y', '-loglevel', 'error',
     '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}', '-r', str(FPS), '-i', '-',
     *audio,
     '-c:v', 'libx264', '-preset', 'slow', '-crf', '20', '-maxrate', '10M', '-bufsize', '20M',
     '-pix_fmt', 'yuv420p', '-profile:v', 'high',
     '-c:a', 'aac', '-b:a', '192k', '-ar', '48000', '-shortest', '-movflags', '+faststart', str(OUT)],
    stdin=subprocess.PIPE)
n = int(DUR * FPS)
for k in range(n):
    proc.stdin.write(frame(k / FPS).tobytes())
    if k % 120 == 0:
        print(f'{k}/{n}', flush=True)
proc.stdin.close()
proc.wait()
print('done', OUT, round(DUR, 2), 's')
