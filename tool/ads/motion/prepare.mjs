// Copies the ad inputs into public/ at the sizes the compositions use.
// Everything here comes from marketing/ads/source (licensed photos, the
// engine's export of the demo scan, recorded app flows) and the repo's
// brand assets and design renders; public/ is git-ignored like marketing/.
//
//   node prepare.mjs

import { execFileSync } from "node:child_process";
import { copyFileSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";

const ROOT = resolve(import.meta.dirname, "../../..");
const SRC = join(ROOT, "marketing/ads/source");
const OUT = join(import.meta.dirname, "public");

const ff = (...args) => execFileSync("ffmpeg", ["-v", "error", "-y", ...args], { stdio: "inherit" });
const dir = (...p) => {
  const d = join(OUT, ...p);
  mkdirSync(d, { recursive: true });
  return d;
};

// Everything but what later steps make (voice.py, track.py, screen_comp.py),
// which isn't copied from source/.
const MADE = new Set(["vo", "track", "plates"]);
mkdirSync(OUT, { recursive: true });
for (const f of readdirSync(OUT)) if (!MADE.has(f)) rmSync(join(OUT, f), { recursive: true, force: true });

// The demo scan: a licensed 9:16 portrait, its 134-point mesh and the lens
// maps, all in the same normalised coordinates.
ff("-i", join(SRC, "model/model.jpg"), "-vf", "scale=1080:1920", "-q:v", "2", join(dir(), "model.jpg"));
copyFileSync(join(SRC, "model/data/mesh.json"), join(OUT, "mesh.json"));
for (const f of readdirSync(join(SRC, "model/data")).filter((f) => f.startsWith("lens_"))) {
  // Lens maps are faint grey heat; lift them so they read as light.
  ff("-i", join(SRC, "model/data", f), "-vf", "format=gray,scale=1080:1920,curves=all='0/0 0.08/0.45 0.3/0.9 1/1'",
    join(dir("lens"), f));
}

for (const f of readdirSync(join(SRC, "broll"))) {
  ff("-i", join(SRC, "broll", f), "-vf", "scale=-2:2200", "-q:v", "3", join(dir("broll"), f));
}

// Recorded app flows (frame-by-frame renders of the real app).
const manifest = {};
for (const flow of readdirSync(join(SRC, "rec"))) {
  const frames = readdirSync(join(SRC, "rec", flow)).filter((f) => f.endsWith(".png")).length;
  if (!frames) continue;
  ff("-framerate", "30", "-start_number", "0", "-i", join(SRC, "rec", flow, "f_%05d.png"),
    "-vf", "scale=720:1280", "-q:v", "2", "-start_number", "0", join(dir("rec", flow), "%05d.jpg"));
  manifest[flow] = frames;
}
writeFileSync(join(OUT, "manifest.json"), JSON.stringify({ rec: manifest }, null, 2));

for (const f of ["02-today", "04-routine", "05-scan-report", "08-progress", "12-face-map", "26-today-streak",
  "28-streak-extended", "29-streak-week"]) {
  ff("-i", join(ROOT, "design/renders", `${f}.png`), "-vf", "scale=720:-2", join(dir("renders"), `${f}.png`));
}
// The full report's breakdown grid, one screen tall (the face map above it
// shows the render fixture's face, which has no model release).
ff("-i", join(ROOT, "design/renders/05b-scan-report-full.png"), "-vf", "crop=1170:2532:0:4750,scale=720:-2",
  join(dir("renders"), "05b-breakdown.png"));

// Live footage for ad 13: Mixkit stock (Mixkit Video Free License: commercial
// use and ads, no attribution), 4K cut to 9:16 at 30 fps. Each cut: source
// clip id, start and length in seconds, horizontal crop position (0 left .. 1 right).
const CUTS = {
  shelf: ["50406", 0.6, 2.0, 0.58],
  feed: ["50417", 3.8, 2.4, 0.36],
  layer: ["50426", 1.2, 1.6, 0.62],
  man: ["50756", 0.6, 1.0, 0.74],
  woman: ["4573", 2.4, 1.0, 0.62],
  scan: ["51185", 17.4, 4.6, 0.5],
  glow: ["51171", 1.6, 7.0, 0.42],
  end: ["41181", 0.3, 5.5, 0.62],
};
for (const [name, [id, ss, t, x]] of Object.entries(CUTS)) {
  ff("-ss", String(ss), "-t", String(t), "-i", join(SRC, "footage", `${id}.mp4`), "-an",
    // timestamps from zero and a keyframe every half second, so Remotion finds every frame
    "-vf", `crop='min(iw,ih*9/16)':ih:'(iw-min(iw,ih*9/16))*${x}':0,scale=1080:1920,fps=30,setpts=N/30/TB`,
    "-c:v", "libx264", "-crf", "15", "-preset", "slow", "-g", "15", "-pix_fmt", "yuv420p", join(dir("footage"), `${name}.mp4`));
}
// The phone scenes' backdrop, blurred here at half size: blurring 1080p
// footage live under motion blur runs the compositor out of memory.
ff("-i", join(dir("footage"), "end.mp4"), "-vf", "scale=540:960,gblur=sigma=16",
  "-c:v", "libx264", "-crf", "20", "-g", "15", "-pix_fmt", "yuv420p", join(dir("footage"), "end-soft.mp4"));

// Recorded sound effects: Mixkit (Mixkit Sound Effects Free License), as
// 48 kHz stereo WAV for sound.py.
for (const f of readdirSync(join(SRC, "sfx"))) {
  ff("-i", join(SRC, "sfx", f), "-ar", "48000", "-ac", "2", "-c:a", "pcm_s16le", join(dir("sfx"), f.replace(/\.\w+$/, ".wav")));
}

// Google's official "Get it on Google Play" badge, unaltered.
copyFileSync(join(SRC, "badges/google-play-en.png"), join(dir("brand"), "google-play-badge.png"));

// The crescent from the mark, without the "skin" inside it.
const mark = readFileSync(join(ROOT, "assets/brand/mark.svg"), "utf8");
const d = mark.match(/<path d="([^"]+)"/)[1];
for (const [name, fill] of [["crescent-cream", "#F3E6CA"], ["crescent-ink", "#151A17"]]) {
  writeFileSync(join(dir("brand"), `${name}.svg`),
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024"><path d="${d}" fill="${fill}"/></svg>`);
}
for (const f of readdirSync(join(ROOT, "assets/fonts"))) copyFileSync(join(ROOT, "assets/fonts", f), join(dir("fonts"), f));

console.log("public/ ready:", JSON.stringify(manifest));
