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

rmSync(OUT, { recursive: true, force: true });

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

for (const f of ["02-today", "05-scan-report", "08-progress", "12-face-map", "26-today-streak", "28-streak-extended",
  "29-streak-week"]) {
  ff("-i", join(ROOT, "design/renders", `${f}.png`), "-vf", "scale=720:-2", join(dir("renders"), `${f}.png`));
}

// The crescent from the mark, without the "skin" inside it.
const mark = readFileSync(join(ROOT, "assets/brand/mark.svg"), "utf8");
const d = mark.match(/<path d="([^"]+)"/)[1];
for (const [name, fill] of [["crescent-cream", "#F3E6CA"], ["crescent-ink", "#151A17"]]) {
  writeFileSync(join(dir("brand"), `${name}.svg`),
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024"><path d="${d}" fill="${fill}"/></svg>`);
}
for (const f of readdirSync(join(ROOT, "assets/fonts"))) copyFileSync(join(ROOT, "assets/fonts", f), join(dir("fonts"), f));

console.log("public/ ready:", JSON.stringify(manifest));
