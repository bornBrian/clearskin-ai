#!/usr/bin/env python3
"""Real-footage ads and a showcase video for ClearSkin AI.

Built the way the top-performing skin-app TikToks are built (broken down shot by
shot with rea-video, see marketing/reference ads/2026-11-top-performers/):

  * real people on camera, hard cuts, no motion graphics
  * one native-TikTok caption (TikTok Sans, white, thin black stroke)
  * the app on screen for a few seconds as the proof
  * no music or sound effects: the track is added in TikTok / Instagram

Every pixel is licensed material or the real app:
  * people: Mixkit stock (Mixkit Video Free License, ads allowed, no credit)
  * app: recorded from the real Flutter app (sample data), and composited onto
    real hands holding phones by tool/ads/motion/screen_comp.py

Usage (from anywhere):  python tool/ads/real/edit.py [name ...]
Writes marketing/ads/real/<name>.mp4 (captioned) and <name>-clean.mp4 (no text,
for adding TikTok's own text in the app).
"""
from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SRC = ROOT / "marketing/ads/source"
PLATES = ROOT / "tool/ads/motion/public/plates"
FLOWS = SRC / "rec2/phone"
BRAND = ROOT / "tool/ads/motion/public/brand"
OUT = ROOT / "marketing/ads/real"
CAPTION_FONT = SRC / "fonts/TikTokSans-SemiBold.ttf"
BRAND_FONT = ROOT / "tool/ads/motion/public/fonts/PlusJakartaSans-SemiBold.ttf"
BRAND_FONT_LIGHT = ROOT / "tool/ads/motion/public/fonts/PlusJakartaSans-Regular.ttf"
FPS = 30
NL = chr(10)

# Brand colours (lib/core/theme/tokens.dart premium system).
CHARCOAL = "0x232321"
CREAM = "0xF3E6CA"


# ----------------------------------------------------------------- sources

def stock(clip: str, ss: float, t: float, x: float) -> dict:
    """Mixkit clip, 4K 16:9, cropped to 9:16 at horizontal position x (0 left .. 1 right)."""
    return {"src": SRC / "footage" / f"{clip}.mp4", "ss": ss, "t": t, "x": x}


def plate(name: str, ss: float, t: float) -> dict:
    """Real hands holding a phone running the real app (already 1080x1920)."""
    return {"src": PLATES / f"{name}.mp4", "ss": ss, "t": t, "x": None}


def cap(start: float, end: float, text: str, y: float = 0.70, size: int = 66) -> dict:
    """Caption: y is where the centre of the text block sits (0 top .. 1 bottom).
    0.70 and 66 px match the 10.8M-view reference (rea-video measured the box at
    70% down, 4.3% of the frame tall). On app shots captions go above the phone (y=0.13)."""
    return {"start": start, "end": end, "text": text, "y": y, "size": size}


# --------------------------------------------------------------- the ads

ADS: dict[str, dict] = {
    # Reference: kiki.13521 AcneTrack, 10.8M views. Same person, dismissive
    # advice quoted on screen, cut to the app, cut to a happy face. 3 beats.
    "clearskin-real-01-just-drink-water": {
        "shots": [
            stock("4573", 0.0, 5.4, 0.74),
            plate("hero", 0.0, 3.5),
            plate("hero", 3.55, 2.3),
            stock("4573", 9.2, 3.2, 0.74),
        ],
        "captions": [
            cap(0.0, 1.8, "“just drink more water”"),
            cap(1.8, 3.6, "“just stop touching your face”"),
            cap(3.6, 5.4, "“just wash it more”"),
            cap(5.4, 8.9, "so I finally let an app\nactually look at my skin", y=0.13),
        ],
    },
    # Reference: jskintea (Skan), 1.8M views. One long relatable shot with a
    # 2-3 line caption, then the app, then the payoff.
    "clearskin-real-02-every-product": {
        "shots": [
            stock("51177", 0.5, 6.5, 0.62),
            plate("routine", 0.0, 3.1),
            stock("51171", 2.0, 3.0, 0.42),
        ],
        "captions": [
            cap(0.0, 6.5, "me after buying every product\nTikTok told me to buy"),
            cap(6.5, 9.6, "when all I needed was one\nroutine made for MY skin", y=0.13),
        ],
    },
    # Every gender: the same structure for men.
    "clearskin-real-03-guys": {
        "shots": [
            stock("50756", 0.0, 1.6, 0.74),
            stock("50756", 3.2, 1.8, 0.74),
            plate("hero", 0.0, 3.5),
            plate("routine", 0.0, 3.1),
        ],
        "captions": [
            cap(0.0, 3.4, "guys: skincare is not\n“whatever soap is in the shower”"),
            cap(3.4, 6.9, "one scan and it tells you\nwhat your skin actually needs", y=0.13),
            cap(6.9, 10.0, "then a routine that\nworks around shaving", y=0.13),
        ],
    },
    # Reference: jskintea (1.8M) and nicoleskincorner (1.7M). rea-video: one
    # fixed shot, zero cuts, soft frontal light, one 2-3 line caption, no app
    # on screen at all: the app is named in the post text. Curiosity, no claim.
    "clearskin-real-05-one-shot": {
        "shots": [
            stock("51177", 6.8, 7.2, 0.62),
        ],
        "captions": [
            cap(0.0, 7.2, "I'll never forget the day I stopped\nguessing what my skin needed", y=0.62),
        ],
    },
    # Reference: acneproneprincess (57 cuts/min) and baldheadbrudda (2.6M,
    # beat-synced). 1.0 s cuts = every 2 beats at 120 BPM, so a trending
    # sound at ~120 BPM lands on the cuts. Then the app's real scores.
    "clearskin-real-06-every-light": {
        "shots": [
            stock("50426", 1.0, 1.0, 0.62),
            stock("4573", 3.0, 1.0, 0.74),
            stock("51171", 4.6, 1.0, 0.42),
            stock("50756", 0.2, 1.0, 0.74),
            stock("51185", 2.0, 1.0, 0.5),
            stock("41181", 4.8, 1.0, 0.62),
            plate("hero", 3.6, 3.0),
        ],
        "captions": [
            cap(0.0, 6.0, "skin in every light,\nevery tone, every face", y=0.70),
            cap(6.0, 9.0, "one scan. nine measurements.", y=0.13),
        ],
    },
    # Reference: taliameals, 10.5M views. Creator on camera with "I'm JUST
    # finding this??", then a fast real walk through the app, labels only.
    "clearskin-real-04-just-finding-this": {
        "shots": [
            stock("50417", 3.6, 2.8, 0.36),
            plate("hero", 0.2, 2.6),
            plate("hero", 3.6, 2.4),
            plate("couch", 0.2, 2.4),
            plate("routine", 0.2, 2.4),
            plate("progress", 0.2, 2.4),
            plate("alarm", 0.5, 2.0),
            stock("51171", 2.0, 2.0, 0.42),
        ],
        "captions": [
            cap(0.0, 2.8, "been doing skincare for years\nand I'm JUST finding this??"),
            cap(2.8, 5.4, "scans your skin", y=0.16, size=52),
            cap(5.4, 7.8, "tells you what it found", y=0.16, size=52),
            cap(7.8, 10.2, "your plan for today", y=0.16, size=52),
            cap(10.2, 12.6, "a routine for YOUR skin", y=0.16, size=52),
            cap(12.6, 15.0, "see if it's working", y=0.16, size=52),
            cap(15.0, 17.0, "reminds you so you stick to it", y=0.16, size=52),
        ],
    },
}

# Showcase: the real app, flow by flow, hard cuts, one label per screen.
SHOWCASE = [
    # (flow folder, frame pattern, seconds, label, sub-label)
    ("scan", "element-%03d.png", 3.5, "Scan", "Front and both sides, checked for light and blur"),
    ("report", "f_%05d.png", 2.6, "Your report", "Nine measurements from one scan"),
    ("breakdown", "f_%05d.png@14", 2.9, "Every result explained", "What it saw, and what to do about it"),
    ("routine", "f_%05d.png", 3.8, "Your routine", "AM and PM, built from your scan"),
    ("today", "f_%05d.png", 4.0, "Today", "Your plan, your streak, your week"),
    ("progress", "f_%05d.png", 2.4, "Progress", "Scores and photos over time"),
    ("guides", "f_%05d.png", 3.4, "Guides", "Short, practical reads on skin"),
    ("reminders", "f_%05d.png", 2.4, "Reminders", "So the routine actually happens"),
]


# ---------------------------------------------------------------- ffmpeg

def ff(*args: str, cwd: Path | None = None) -> None:
    cmd = ["ffmpeg", "-v", "error", "-y", *args]
    r = subprocess.run(cmd, cwd=cwd)
    if r.returncode:
        sys.exit(f"ffmpeg failed: {' '.join(cmd)}")


def cut(shot: dict, out: Path, w: int = 1080, h: int = 1920) -> None:
    vf = []
    if shot["x"] is not None:
        vf.append(f"crop='min(iw,ih*{w}/{h})':ih:'(iw-min(iw,ih*{w}/{h}))*{shot['x']}':0")
    vf += [f"scale={w}:{h}:flags=lanczos", f"fps={FPS}", "setsar=1", "format=yuv420p"]
    ff("-ss", f"{shot['ss']}", "-t", f"{shot['t']}", "-i", str(shot["src"]), "-an",
       "-vf", ",".join(vf), "-c:v", "libx264", "-crf", "14", "-preset", "medium", str(out))


def concat(parts: list[Path], out: Path, work: Path) -> None:
    lst = work / "list.txt"
    lst.write_text("".join(f"file '{p.name}'\n" for p in parts), encoding="utf-8")
    ff("-f", "concat", "-safe", "0", "-i", lst.name, "-c", "copy", out.name, cwd=work)


def draw_lines(text: str, font: str, size: int, color: str, x: str, top: str,
               work: Path, key: str, extra: str = "") -> list[str]:
    """One drawtext per line (ffmpeg 8's shaper draws a box for a newline glyph).
    y_align=font keeps every line on the same baseline grid."""
    lines = text.split(NL)
    lh = round(size * 1.3)
    out = []
    for j, line in enumerate(lines):
        f = work / f"{key}_{j}.txt"
        f.write_text(line, encoding="utf-8", newline="")
        out.append(
            f"drawtext=fontfile={font}:textfile={f.name}:fontsize={size}:fontcolor={color}"
            f":y_align=font:x={x}:y={top}+{j * lh}{extra}"
        )
    return out


def block_height(text: str, size: int) -> int:
    return len(text.split(NL)) * round(size * 1.3)


def caption_filters(caps: list[dict], work: Path, font_name: str) -> str:
    chains = []
    for i, c in enumerate(caps):
        top = f"h*{c['y']}-{block_height(c['text'], c['size']) // 2}"
        chains += draw_lines(
            c["text"], font_name, c["size"], "white", "(w-text_w)/2", top, work, f"cap{i}",
            f":borderw=4:bordercolor=black@0.85:enable='between(t,{c['start']},{c['end'] - 0.001})'",
        )
    return ",".join(chains) if chains else "null"


def finish(base: Path, vf: str, out: Path, work: Path) -> None:
    """Final encode with a silent stereo track (some ad managers reject video-only files)."""
    ff("-i", base.name, "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo",
       "-vf", vf, "-map", "0:v", "-map", "1:a", "-shortest",
       "-c:v", "libx264", "-crf", "17", "-preset", "slow", "-profile:v", "high",
       "-pix_fmt", "yuv420p", "-r", str(FPS), "-c:a", "aac", "-b:a", "128k",
       "-movflags", "+faststart", str(out), cwd=work)


def build_ad(name: str, spec: dict) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        shutil.copy(CAPTION_FONT, work / "caption.ttf")
        parts = []
        for i, shot in enumerate(spec["shots"]):
            p = work / f"s{i:02d}.mp4"
            cut(shot, p)
            parts.append(p)
        base = work / "base.mp4"
        concat(parts, base, work)
        finish(base, caption_filters(spec["captions"], work, "caption.ttf"), OUT / f"{name}.mp4", work)
        finish(base, "null", OUT / f"{name}-clean.mp4", work)
    print("wrote", OUT / f"{name}.mp4")


# --------------------------------------------------------------- showcase

def flow_clip(folder: str, pattern: str, seconds: float, out: Path, screen_h: int,
              canvas: tuple[int, int], screen_x: int, screen_y: int, labels: list[dict], work: Path) -> None:
    """One flow at real speed: the app screen on the brand background, labels static."""
    cw, ch = canvas
    pattern, _, start = pattern.partition("@")  # "f_%05d.png@14" = start at frame 14
    src = FLOWS / folder / pattern
    text = []
    for i, l in enumerate(labels):
        text += draw_lines(l["text"], l["font"], l["size"], l["color"], str(l["x"]), str(l["y"]),
                           work, f"{out.stem}_l{i}")
    graph = (
        f"color=c={CHARCOAL}:s={cw}x{ch}:r={FPS}:d={seconds}[bg];"
        f"[0:v]fps={FPS},scale=-2:{screen_h}:flags=lanczos,format=rgba[ui];"
        f"[bg][ui]overlay={screen_x}:{screen_y}:shortest=1:format=auto"
        + ("," + ",".join(text) if text else "")
        + ",format=yuv420p[v]"
    )
    ff("-framerate", str(FPS), "-start_number", start or "0", "-i", str(src), "-filter_complex", graph, "-map", "[v]",
       "-t", str(seconds), "-c:v", "libx264", "-crf", "14", "-preset", "medium", out.name, cwd=work)


def card(seconds: float, out: Path, canvas: tuple[int, int], lines: list[dict], work: Path,
         badge: tuple[int, int, int] | None = None) -> None:
    """Static title / end card on charcoal (logo text + lines, optional official Play badge)."""
    cw, ch = canvas
    text = []
    for i, l in enumerate(lines):
        text += draw_lines(l["text"], l["font"], l["size"], l["color"], "(w-text_w)/2", str(l["y"]),
                           work, f"{out.stem}_l{i}")
    inputs = ["-f", "lavfi", "-i", f"color=c={CHARCOAL}:s={cw}x{ch}:r={FPS}:d={seconds}"]
    if badge:
        shutil.copy(BRAND / "google-play-badge.png", work / "badge.png")
        bw, bx, by = badge
        inputs += ["-i", "badge.png"]
        graph = f"[1:v]scale={bw}:-1[b];[0:v][b]overlay={bx}:{by}," + ",".join(text) + ",format=yuv420p[v]"
    else:
        graph = "[0:v]" + ",".join(text) + ",format=yuv420p[v]"
    ff(*inputs, "-filter_complex", graph, "-map", "[v]", "-t", str(seconds),
       "-c:v", "libx264", "-crf", "14", "-preset", "medium", out.name, cwd=work)


def build_showcase(landscape: bool) -> None:
    name = "clearskin-showcase-16x9" if landscape else "clearskin-showcase-9x16"
    canvas = (1920, 1080) if landscape else (1080, 1920)
    cw, ch = canvas
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        for f, n in ((BRAND_FONT, "brand.ttf"), (BRAND_FONT_LIGHT, "brandlight.ttf")):
            shutil.copy(f, work / n)
        parts = []
        title = work / "title.mp4"
        card(2.6, title, canvas, [
            {"text": "ClearSkin AI", "font": "brand.ttf", "size": 96 if landscape else 104, "color": CREAM,
             "y": ch // 2 - 110},
            {"text": "Your AI skin coach.\nEvery skin tone. Every gender.", "font": "brandlight.ttf",
             "size": 44, "color": CREAM, "y": ch // 2 + 20},
        ], work)
        parts.append(title)
        for i, (folder, pattern, secs, label, sub) in enumerate(SHOWCASE):
            out = work / f"f{i:02d}.mp4"
            if landscape:
                screen_h = 980
                sw = round(screen_h * 1080 / 2338)
                sx, sy = 420, (ch - screen_h) // 2
                tx = sx + sw + 140
                labels = [
                    {"text": label, "font": "brand.ttf", "size": 76, "color": CREAM, "x": tx, "y": 420},
                    {"text": sub, "font": "brandlight.ttf", "size": 38, "color": CREAM, "x": tx, "y": 530},
                ]
            else:
                screen_h = 1500
                sw = round(screen_h * 1080 / 2338)
                sx, sy = (cw - sw) // 2, 330
                labels = [
                    {"text": label, "font": "brand.ttf", "size": 72, "color": CREAM,
                     "x": "(w-text_w)/2", "y": 120},
                    {"text": sub, "font": "brandlight.ttf", "size": 36, "color": CREAM,
                     "x": "(w-text_w)/2", "y": 220},
                ]
            flow_clip(folder, pattern, secs, out, screen_h, canvas, sx, sy, labels, work)
            parts.append(out)
        end = work / "end.mp4"
        bw = 520 if landscape else 600
        card(3.2, end, canvas, [
            {"text": "ClearSkin AI", "font": "brand.ttf", "size": 96, "color": CREAM, "y": ch // 2 - 200},
            {"text": "Available now on Google Play", "font": "brandlight.ttf", "size": 42, "color": CREAM,
             "y": ch // 2 - 60},
        ], work, badge=(bw, (cw - bw) // 2, ch // 2 + 40))
        parts.append(end)
        base = work / "base.mp4"
        concat(parts, base, work)
        finish(base, "null", OUT / f"{name}.mp4", work)
    print("wrote", OUT / f"{name}.mp4")


def main(names: list[str]) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    todo = names or [*ADS, "showcase"]
    for n in todo:
        if n == "showcase":
            build_showcase(landscape=True)
            build_showcase(landscape=False)
        elif n in ADS:
            build_ad(n, ADS[n])
        else:
            sys.exit(f"unknown: {n}; choose from {', '.join([*ADS, 'showcase'])}")


if __name__ == "__main__":
    main(sys.argv[1:])
