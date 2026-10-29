// Renders the motion ads to marketing/ads/. Ads 05-07 use a licensed track
// (cut so every edit lands on a beat) plus a silent copy; ads 08+ are scored
// by sound.py from src/sound/<Id>.json (music written to the cuts, plus
// sound design), with a copy that keeps only the sound effects, for adding
// a trending sound inside TikTok or Instagram.
//
//   node prepare.mjs                    # once, or after the sources change
//   node render.mjs [Decoded Products Streak]
//
// Music: Kevin MacLeod (incompetech.com), CC BY 4.0. The credit line for
// each post's caption is printed after rendering.

import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const ROOT = resolve(import.meta.dirname, "../../..");
const SRC = join(ROOT, "marketing/ads/source");
const OUT = join(ROOT, "marketing/ads");

// start: a beat of the track (first beat + a whole number of bars) where
// the music lifts; the composition's beat 0 lands on it.
const ADS = {
  Decoded: { file: "clearskin-ad-05-decoded", track: "Wallpaper.mp3", title: "Wallpaper", start: 36.713 },
  Products: { file: "clearskin-ad-06-start-with-your-skin", track: "Carefree.mp3", title: "Carefree", start: 138.092 },
  Streak: { file: "clearskin-ad-07-streak", track: "Life_of_Riley.mp3", title: "Life of Riley", start: 17.026 },
  Guessing: { file: "clearskin-ad-08-stop-guessing", score: true },
  Clash: { file: "clearskin-ad-09-products-fighting", score: true },
  Working: { file: "clearskin-ad-10-is-it-working", score: true },
  Explained: { file: "clearskin-ad-11-skin-explained", score: true },
};

// Remotion's own headless browser, else Edge (always on Windows).
const EDGE = "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe";
const browser = process.env.BROWSER ?? (existsSync(EDGE) ? EDGE : undefined);

const CLI = join(import.meta.dirname, "node_modules/@remotion/cli/remotion-cli.js");
const ids = process.argv.slice(2).length ? process.argv.slice(2) : Object.keys(ADS);
mkdirSync(OUT, { recursive: true });
for (const id of ids) {
  const ad = ADS[id];
  const silent = join(OUT, `${ad.file}-no-music.mp4`);
  execFileSync(
    process.execPath,
    [CLI, "render", "src/index.ts", id, silent, "--codec=h264", "--crf=16", "--muted", "--concurrency=4", "--timeout=180000",
      ...(browser ? [`--browser-executable=${browser}`] : [])],
    { stdio: "inherit", cwd: import.meta.dirname },
  );
  const dur = Number(
    execFileSync("ffprobe", ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", silent]).toString(),
  );
  const mux = (audio, out, extra = [], lufs = -14) => {
    rmSync(out, { force: true });
    execFileSync("ffmpeg", [
      "-v", "error", "-y", "-i", silent, ...extra, "-i", audio,
      "-map", "0:v", "-map", "1:a", "-c:v", "copy", "-c:a", "aac", "-b:a", "256k", "-shortest",
      "-af", `afade=t=out:st=${(dur - 0.5).toFixed(2)}:d=0.5,loudnorm=I=${lufs}:TP=-1.5:LRA=11`,
      "-movflags", "+faststart", out,
    ], { stdio: "inherit" });
  };
  if (ad.score) {
    const spec = join(import.meta.dirname, "src/sound", `${id}.json`);
    const tmp = join(tmpdir(), `clearskin-${id}`);
    execFileSync("python", ["sound.py", spec, `${tmp}-score.wav`], { stdio: "inherit", cwd: import.meta.dirname });
    execFileSync("python", ["sound.py", spec, `${tmp}-sfx.wav`, "--sfx-only"], { stdio: "inherit", cwd: import.meta.dirname });
    mux(`${tmp}-score.wav`, join(OUT, `${ad.file}.mp4`));
    // quieter, so a sound added in the app sits on top
    mux(`${tmp}-sfx.wav`, join(OUT, `${ad.file}-sfx-only.mp4`), [], -20);
    rmSync(silent, { force: true });
    console.log(`
${join(OUT, `${ad.file}.mp4`)}
Original score and sound design (sound.py): no credit needed.
`);
    continue;
  }
  mux(join(SRC, ad.track), join(OUT, `${ad.file}.mp4`), ["-ss", String(ad.start), "-t", String(dur)]);
  console.log(`
${join(OUT, `${ad.file}.mp4`)}
Caption credit: Music: "${ad.title}" by Kevin MacLeod (incompetech.com), CC BY 4.0
`);
}
