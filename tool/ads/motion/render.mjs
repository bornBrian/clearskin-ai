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
import { existsSync, mkdirSync, readFileSync, rmSync } from "node:fs";
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
  Measured: { file: "clearskin-ad-12-measured", score: true, vo: true },
};

/**
 * Lays each voice line (src/sound/<Id>.timeline.json, made by voice.py) on
 * its frame, then mixes it over [bed] with the bed ducking under the voice.
 */
function withVoice(id, bed, out) {
  const timeline = JSON.parse(readFileSync(join(import.meta.dirname, "src/sound", `${id}.timeline.json`), "utf-8"));
  const lines = Object.entries(timeline).filter(([k]) => !k.startsWith("_"));
  const inputs = lines.flatMap(([, l]) => ["-i", join(import.meta.dirname, "public", l.file)]);
  const placed = lines.map(([, l], i) => `[${i + 1}:a]aresample=48000,pan=stereo|c0=c0|c1=c0,adelay=${Math.round((l.at / 30) * 1000)}:all=1[v${i}]`);
  const filter = [
    ...placed,
    `${lines.map((_, i) => `[v${i}]`).join("")}amix=inputs=${lines.length}:normalize=0,volume=2.2,highpass=f=80,acompressor=threshold=0.1:ratio=3:attack=5:release=120,apad=whole_dur=60[vo]`, // padded: filters stop at the shortest input
    "[vo]asplit=2[vo1][vo2]",
    "[0:a]volume=0.55[bed]",
    "[bed][vo1]sidechaincompress=threshold=0.02:ratio=8:attack=15:release=350[duck]",
    "[duck][vo2]amix=inputs=2:normalize=0:duration=first[mix]",
  ].join(";");
  execFileSync("ffmpeg", ["-v", "error", "-y", "-i", bed, ...inputs, "-filter_complex", filter, "-map", "[mix]", "-ar", "48000", out], { stdio: "inherit" });
}

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
    [CLI, "render", "src/index.ts", id, silent, "--codec=h264", "--crf=16", "--muted", "--concurrency=4", "--timeout=180000", "--gl=angle",
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
    if (ad.vo) {
      withVoice(id, `${tmp}-score.wav`, `${tmp}-score-vo.wav`);
      withVoice(id, `${tmp}-sfx.wav`, `${tmp}-sfx-vo.wav`);
      mux(`${tmp}-score-vo.wav`, join(OUT, `${ad.file}.mp4`));
      mux(`${tmp}-sfx-vo.wav`, join(OUT, `${ad.file}-sfx-only.mp4`), [], -16);
      rmSync(silent, { force: true });
      console.log(`\n${join(OUT, `${ad.file}.mp4`)}\nOriginal score, sound design and voice (Kokoro, Apache 2.0): no credit needed.\n`);
      continue;
    }
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
