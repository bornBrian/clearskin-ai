"""Generates every ClearSkin AI brand asset from one definition.

    python scripts/brand/generate_brand.py

Mark: an open "C" that holds the word "skin" — read together as "C·skin"
(ClearSkin). The C is a calligraphic stroke, not a uniform ring: hairline at
both tips, swelling to its fullest at the lower left, like light catching a
curve. That contrast is what makes it ours. Cream on charcoal; no dots,
glows or gradients.

Outputs:
  assets/brand/        SVG masters + PNGs used inside the app
  android mipmaps      legacy + adaptive (foreground/monochrome) launcher icons
  ios AppIcon          every size listed in Contents.json
  ios LaunchImage      the cream mark for the charcoal launch screen
  docs/store/          Play Store icon (512) + feature graphic (1024x500)
"""

from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
FONT = ROOT / "assets/fonts/PlusJakartaSans-Regular.ttf"
FONT_LIGHT = ROOT / "assets/fonts/PlusJakartaSans-Light.ttf"

CHARCOAL = (35, 35, 33)     # #232321
CREAM = (243, 230, 202)     # #F3E6CA
INK = (21, 26, 23)          # #151A17 (in-app ink)

# Geometry (fractions of the mark's box). Must match LogoMark/BrandMark in
# lib/core/widgets/widgets.dart.
RING_RADIUS = 0.40           # centre-line radius
STROKE_MAX = 0.062           # fullest weight, at the lower left
STROKE_MIN = 0.010           # hairline at the tips
HEAVY_DEG = 155              # where the stroke is fullest (0 = right, 90 = down)
GAP_DEG = 78                 # opening on the right; "skin" breathes out of it
TEXT_SIZE = 0.30             # cap-to-descender height of "skin"
TEXT_SHIFT = 0.07            # text centre sits right of the ring centre

SS = 4  # supersampling factor for smooth edges


def _stroke_at(deg: float, scale: float = 1.0) -> float:
    """Stroke width (fraction of box) at an angle: cosine swell to HEAVY_DEG."""
    t = (1 + math.cos(math.radians(deg - HEAVY_DEG))) / 2
    return (STROKE_MIN + (STROKE_MAX - STROKE_MIN) * t ** 1.6) * scale


def _c_polygon(cx: float, cy: float, size: float, weight: float = 1.0):
    r = RING_RADIUS * size
    start, end = GAP_DEG / 2, 360 - GAP_DEG / 2
    steps = 240
    outer, inner = [], []
    for i in range(steps + 1):
        deg = start + (end - start) * i / steps
        w = _stroke_at(deg, weight) * size / 2
        a = math.radians(deg)
        outer.append((cx + (r + w) * math.cos(a), cy + (r + w) * math.sin(a)))
        inner.append((cx + (r - w) * math.cos(a), cy + (r - w) * math.sin(a)))
    return outer + inner[::-1]


def _ring(draw: ImageDraw.ImageDraw, cx: float, cy: float, size: float,
          color: tuple, stroke: float = 1.0) -> None:
    """The calligraphic C. [stroke] scales the weight (heavier for tiny sizes)."""
    draw.polygon(_c_polygon(cx, cy, size, stroke), fill=color)


def _skin(draw: ImageDraw.ImageDraw, cx: float, cy: float, size: float,
          color: tuple) -> None:
    font = ImageFont.truetype(str(FONT), int(size * TEXT_SIZE))
    x0, y0, x1, y1 = draw.textbbox((0, 0), "skin", font=font)
    tw, th = x1 - x0, y1 - y0
    draw.text((cx + TEXT_SHIFT * size - tw / 2 - x0, cy - th / 2 - y0), "skin",
              font=font, fill=color)


def mark_png(px: int, *, bg: tuple | None, fg: tuple, scale: float = 1.0,
             word: bool = True) -> Image.Image:
    big = px * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0) if bg is None else bg + (255,))
    d = ImageDraw.Draw(img)
    size = big * scale
    _ring(d, big / 2, big / 2, size, fg + (255,))
    if word:
        _skin(d, big / 2, big / 2, size, fg + (255,))
    return img.resize((px, px), Image.LANCZOS)


def lockup_png(height: int, *, fg: tuple, bg: tuple | None) -> Image.Image:
    """Horizontal logo: ring + 'clearskin' wordmark, for headers and docs."""
    h = height * SS
    font = ImageFont.truetype(str(FONT), int(h * 0.50))
    text = "clearskin"
    tw = font.getbbox(text)[2]
    gap = int(h * 0.14)
    w = h + gap + tw + int(h * 0.1)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0) if bg is None else bg + (255,))
    d = ImageDraw.Draw(img)
    _ring(d, h / 2, h / 2, h * 1.1, fg + (255,), stroke=1.8)
    asc, desc = font.getmetrics()
    d.text((h + gap, (h - (asc + desc)) / 2 + h * 0.02), text, font=font,
           fill=fg + (255,))
    return img.resize((w // SS, height), Image.LANCZOS)


def svg_mark(fg: str, bg: str | None = None, word: bool = True) -> str:
    s = 1024
    pts = _c_polygon(s / 2, s / 2, s)
    path = "M " + " L ".join(f"{x:.1f} {y:.1f}" for x, y in pts) + " Z"
    bg_rect = f'<rect width="{s}" height="{s}" rx="230" fill="{bg}"/>' if bg else ""
    text = (
        f'<text x="{s / 2 + TEXT_SHIFT * s:.1f}" y="{s / 2:.1f}" fill="{fg}" '
        f'font-family="Plus Jakarta Sans" font-size="{TEXT_SIZE * s * 1.12:.0f}" '
        f'text-anchor="middle" dominant-baseline="central">skin</text>'
        if word else ""
    )
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {s} {s}">{bg_rect}'
        f'<path d="{path}" fill="{fg}"/>{text}</svg>'
    )


def hexc(c: tuple) -> str:
    return "#%02X%02X%02X" % c


def write_notification_icon(res: Path) -> None:
    """Status-bar icon: the C alone, heavier, as a white vector. Android
    draws small icons from the alpha channel only, which is why the full
    launcher icon showed up as a white square."""
    s = 24
    pts = _c_polygon(s / 2, s / 2, s * 1.05, weight=2.4)
    path = "M" + " L".join(f"{x:.2f},{y:.2f}" for x, y in pts) + " Z"
    (res / "drawable").mkdir(exist_ok=True)
    (res / "drawable/ic_stat_clearskin.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<!-- Generated by scripts/brand/generate_brand.py -->\n'
        '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
        f'    android:width="24dp" android:height="24dp"\n'
        f'    android:viewportWidth="{s}" android:viewportHeight="{s}">\n'
        f'    <path android:fillColor="#FFFFFFFF" android:pathData="{path}" />\n'
        '</vector>\n')


def write_ios_launch(root: Path) -> None:
    """Launch screen mark, matching Android's: cream C·skin, transparent,
    drawn at 120pt on the storyboard's charcoal background."""
    out = root / "ios/Runner/Assets.xcassets/LaunchImage.imageset"
    for scale, name in ((1, "LaunchImage.png"), (2, "LaunchImage@2x.png"),
                        (3, "LaunchImage@3x.png")):
        mark_png(120 * scale, bg=None, fg=CREAM).save(out / name)


def main() -> None:
    brand = ROOT / "assets/brand"
    brand.mkdir(parents=True, exist_ok=True)
    for stale in ("mark-inverse.svg",):
        (brand / stale).unlink(missing_ok=True)

    # SVG masters for designers.
    (brand / "mark.svg").write_text(svg_mark(hexc(INK)))
    (brand / "mark-cream.svg").write_text(svg_mark(hexc(CREAM)))
    (brand / "app-icon.svg").write_text(svg_mark(hexc(CREAM), hexc(CHARCOAL)))

    # In-app PNGs.
    lockup_png(160, fg=INK, bg=None).save(brand / "logo-lockup.png")
    lockup_png(160, fg=CREAM, bg=None).save(brand / "logo-lockup-inverse.png")

    # Android legacy launcher icons (full-bleed square; launchers mask them).
    res = ROOT / "android/app/src/main/res"
    legacy = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for density, px in legacy.items():
        mark_png(px, bg=CHARCOAL, fg=CREAM, scale=0.86).save(
            res / f"mipmap-{density}/ic_launcher.png")

    # Android adaptive icon: 108dp canvas, mark kept inside the 66dp safe zone.
    adaptive = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
    for density, px in adaptive.items():
        d = res / f"mipmap-{density}"
        mark_png(px, bg=None, fg=CREAM, scale=0.60).save(d / "ic_launcher_foreground.png")
        mark_png(px, bg=None, fg=(255, 255, 255), scale=0.60).save(
            d / "ic_launcher_monochrome.png")
    anydpi = res / "mipmap-anydpi-v26"
    anydpi.mkdir(exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n'
        '</adaptive-icon>\n')
    (res / "values/ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        f'    <color name="ic_launcher_background">{hexc(CHARCOAL)}</color>\n</resources>\n')
    write_notification_icon(res)

    # iOS: regenerate every file listed in the AppIcon set (no alpha allowed).
    icon_set = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    contents = json.loads((icon_set / "Contents.json").read_text())
    for entry in contents["images"]:
        fname = entry.get("filename")
        if not fname:
            continue
        pt = float(entry["size"].split("x")[0])
        px = int(round(pt * int(entry["scale"].rstrip("x"))))
        mark_png(px, bg=CHARCOAL, fg=CREAM, scale=0.86).convert("RGB").save(icon_set / fname)
    write_ios_launch(ROOT)

    # Store assets.
    store = ROOT / "docs/store"
    store.mkdir(parents=True, exist_ok=True)
    mark_png(512, bg=CHARCOAL, fg=CREAM, scale=0.86).save(store / "play-icon-512.png")

    W, H = 1024 * SS // 2, 500 * SS // 2
    fg = Image.new("RGBA", (W, H), CHARCOAL + (255,))
    d = ImageDraw.Draw(fg)
    size = H * 0.78
    _ring(d, W * 0.24, H / 2, size, CREAM + (255,))
    _skin(d, W * 0.24, H / 2, size, CREAM + (255,))
    tag = ImageFont.truetype(str(FONT_LIGHT), int(H * 0.11))
    d.text((int(W * 0.50), int(H * 0.36)), "Your skin,", font=tag, fill=CREAM + (255,))
    d.text((int(W * 0.50), int(H * 0.50)), "understood.", font=tag, fill=CREAM + (255,))
    fg.resize((1024, 500), Image.LANCZOS).convert("RGB").save(store / "feature-graphic-1024x500.png")

    print("Brand assets generated.")


if __name__ == "__main__":
    main()
