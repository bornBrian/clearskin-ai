"""Play Store phone screenshots, 1080x1920: eyebrow + headline over the real app render."""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root = Path(sys.argv[1])
out = root / "docs/store/screenshots"
out.mkdir(parents=True, exist_ok=True)
fonts = root / "assets/fonts"

W, H = 1080, 1920
CHARCOAL = (35, 35, 33)
CREAM = (243, 230, 202)
GUTTER = 100
SCREEN_TOP = 540
RADIUS = 44

eyebrow_font = ImageFont.truetype(str(fonts / "PlusJakartaSans-SemiBold.ttf"), 30)
head_font = ImageFont.truetype(str(fonts / "PlusJakartaSans-Light.ttf"), 84)

shots = [
    ("05-scan-report", "SKIN SCAN", ["Your skin score,", "in ten seconds."]),
    ("04-routine", "ROUTINE", ["Built around", "your skin."]),
    ("24-step-guide", "STEP GUIDE", ["Every step,", "explained."]),
    ("08-progress", "PROGRESS", ["See what's", "really changing."]),
    ("14-journey", "12-WEEK PLAN", ["A plan with", "a finish line."]),
    ("32-checkin", "CHECK-IN", ["Find what sets", "off breakouts."]),
    ("31-coach", "SKIN COACH", ["Ask anything", "about your skin."]),
    ("10-plan-reveal", "YOUR PLAN", ["Your plan,", "ready on day one."]),
]


def tracked(d, xy, text, font, fill, spacing):
    x, y = xy
    for ch in text:
        d.text((x, y), ch, font=font, fill=fill)
        x += font.getlength(ch) + spacing


for i, (name, eyebrow, lines) in enumerate(shots, 1):
    canvas = Image.new("RGB", (W, H), CHARCOAL)
    d = ImageDraw.Draw(canvas)
    tracked(d, (GUTTER, 170), eyebrow, eyebrow_font, CREAM + (0,), 5)
    d.text((GUTTER, 170), "", font=eyebrow_font)
    # Eyebrow at reduced contrast: redraw blended.
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    tracked(ld, (GUTTER, 170), eyebrow, eyebrow_font, CREAM + (150,), 5)
    for j, line in enumerate(lines):
        ld.text((GUTTER, 230 + j * 104), line, font=head_font, fill=CREAM + (255,))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), layer)

    screen = Image.open(root / f"design/renders/{name}.png").convert("RGB")
    if name == "04-routine":
        # The render's sample sunscreen carries a real brand; keep stores brand-free.
        sd = ImageDraw.Draw(screen)
        sd.rectangle((210, 1452, 700, 1502), fill=(255, 255, 255))
        sub = ImageFont.truetype(str(fonts / "PlusJakartaSans-Regular.ttf"), 40)
        text = "Broad-spectrum UVA/UVB"
        b = sub.getbbox(text)
        sd.text((217 - b[0], 1459 - b[1]), text, font=sub, fill=(104, 112, 106))
    sw = W - 2 * GUTTER
    screen = screen.resize((sw, round(screen.height * sw / screen.width)), Image.LANCZOS)
    screen = screen.crop((0, 0, sw, H - SCREEN_TOP))
    mask = Image.new("L", screen.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw - 1, screen.height + RADIUS), RADIUS, fill=255)
    canvas.paste(screen, (GUTTER, SCREEN_TOP), mask)
    edge = ImageDraw.Draw(canvas)
    edge.rounded_rectangle(
        (GUTTER - 1, SCREEN_TOP - 1, GUTTER + sw, H + RADIUS), RADIUS + 1, outline=CREAM + (40,), width=2
    )
    canvas.convert("RGB").save(out / f"{i:02d}-{name}.png", optimize=True)
    print(out / f"{i:02d}-{name}.png")

# Contact sheet for review.
files = sorted(out.glob("*.png"))
tw, th = 270, 480
sheet = Image.new("RGB", (tw * 4 + 50, th * 2 + 30), (255, 255, 255))
for k, f in enumerate(files):
    im = Image.open(f).resize((tw, th), Image.LANCZOS)
    sheet.paste(im, (10 + (k % 4) * (tw + 10), 10 + (k // 4) * (th + 10)))
sheet.save(Path(sys.argv[2]))
