// Ad 14: "In your hands." Voiced, 28 s, an app-first product spot: calm
// colour fields and real phones in real hands, one feature at a time.
// Every phone is stock footage with a keying screen; screen_comp.py tracks
// each screen frame by frame and puts the real app on it (flows recorded
// from the app's own widgets by tool/screenshots), fingers and notch in
// front. The scan screen is PhoneScan below: the app's capture view over
// real footage, with the app's contour mesh tracked onto the face.
// Footage and effects: Mixkit free licences.

import type { CSSProperties, ReactNode } from "react";
import { AbsoluteFill, Freeze, Img, OffthreadVideo, Sequence, staticFile, useCurrentFrame } from "remotion";
import { C, FONT, Grain, H, inOut, prog, useJson, W } from "./kit";
import { Dust, Finale, MaskText } from "./premium";
import T from "./sound/Hands.timeline.json";

export const HANDS_FRAMES = T._end.at;

const INK = "#1D1F1C";
const CHAR = "#1E1E1C";

/** Each plate's span on the timeline (frames); plates overlap by FADE for the dissolve. */
const FADE = 8;
const SHOTS = [
  { name: "couch", from: 0, to: T.scan.at },
  { name: "hero", from: T.scan.at, to: T.routine.at },
  { name: "routine", from: T.routine.at, to: T.alarm.at },
  { name: "alarm", from: T.alarm.at, to: T.guides.at },
  { name: "guides", from: T.guides.at, to: T.progress.at },
  { name: "progress", from: T.progress.at, to: T.brand.at },
] as const;

/** A composited plate, dissolving in over FADE frames, drifting slowly towards the camera. */
function Plate({ name, from, to, first }: { name: string; from: number; to: number; first: boolean }) {
  const f = useCurrentFrame();
  const len = to - from + FADE;
  const o = first ? 1 : prog(f, from, from + FADE, inOut);
  const s = 1.0 + 0.045 * prog(f, from, from + len, (t) => t);
  return (
    <Sequence from={from} durationInFrames={len} layout="none">
      <AbsoluteFill style={{ opacity: o }}>
        <OffthreadVideo src={staticFile(`plates/${name}.mp4`)} muted style={{ width: W, height: H, transform: `scale(${s})` }} />
      </AbsoluteFill>
    </Sequence>
  );
}

/** The feature line: a small numbered label and two lines that rise in, top of frame. */
function Line({ n, label, lines, at, to, dark, shade, low }: { n: string; label: string; lines: (string | { text: string; color?: string })[]; at: number; to: number; dark?: boolean; shade?: boolean; low?: boolean }) {
  const f = useCurrentFrame();
  if (f < at - 2 || f >= to) return null;
  const ink = dark ? "#FFFFFF" : INK;
  const out = prog(f, to - 8, to, inOut);
  // low: under the phone, for shots where the phone fills the top of the frame
  const style: CSSProperties = { position: "absolute", left: 90, right: 90, top: low ? 1240 : 200, opacity: 1 - out };
  return (
    <>
      {shade ? <AbsoluteFill style={{ background: low ? "linear-gradient(0deg, rgba(0,0,0,.6), transparent 50%)" : "linear-gradient(180deg, rgba(0,0,0,.55), transparent 34%)", opacity: prog(f, at - 2, at + 8) * (1 - out) }} /> : null}
      <div style={style}>
        <div style={{ fontFamily: FONT, fontSize: 26, fontWeight: 600, letterSpacing: "0.22em", color: ink, opacity: 0.6 * prog(f, at, at + 10) }}>
          {n}&nbsp;&nbsp;{label.toUpperCase()}
        </div>
        <div style={{ height: 18 }} />
        <MaskText lines={lines} at={at + 3} every={5} size={88} weight={500} color={ink} align="left" tracking={-0.035} />
      </div>
    </>
  );
}

export function Hands() {
  const f = useCurrentFrame();
  const sage = C.leaf;
  return (
    <AbsoluteFill style={{ background: CHAR }}>
      {SHOTS.map((s, i) => (
        <Plate key={s.name} name={s.name} from={s.from} to={s.to} first={i === 0} />
      ))}

      {/* 1. on the couch: the app, on someone's phone */}
      <Opening />

      {/* 2–6. one feature at a time */}
      <Line n="01" label="Scan" lines={["One scan.", { text: "Every side.", color: sage }]} at={T.scan.at + 4} to={T.nine.at} />
      <Line n="02" label="Measure" lines={["Nine measurements,", { text: "in plain words.", color: sage }]} at={T.nine.at} to={T.routine.at} />
      <Line n="03" label="Routine" lines={["Built from", { text: "what it sees.", color: "#9A7B3C" }]} at={T.routine.at + 4} to={T.alarm.at} />
      <Line n="04" label="Reminders" lines={["Rings like", "an alarm."]} at={T.alarm.at + 4} to={T.guides.at} dark shade low />
      <Line n="05" label="Guides" lines={["Food, water,", "weather, sleep."]} at={T.guides.at + 4} to={T.progress.at} dark shade />
      <Line n="06" label="Progress" lines={["See it change,", { text: "week by week.", color: C.mint }]} at={T.progress.at + 4} to={T.brand.at} dark />

      {/* 7. the close */}
      {f >= T.brand.at - 6 ? (
        <AbsoluteFill style={{ background: CHAR, opacity: prog(f, T.brand.at - 6, T.brand.at + 4, inOut) }}>
          <Dust count={22} seed="hands" />
          <Finale at={T.brand.at + 2} tagline="Know your skin." theme="dark" footer="Available now on Google Play" badge />
        </AbsoluteFill>
      ) : null}
      <Grain opacity={0.035} />
    </AbsoluteFill>
  );
}

/** The wordmark settling in over the couch shot. */
function Opening() {
  const f = useCurrentFrame();
  const a = T.meet.at;
  const end = T.scan.at;
  if (f >= end) return null;
  const o = prog(f, a, a + 14) * (1 - prog(f, end - 8, end, inOut));
  return (
    <>
      <AbsoluteFill style={{ background: "linear-gradient(180deg, rgba(0,0,0,.45), transparent 30%)", opacity: o }} />
      <div style={{ position: "absolute", top: 210, width: "100%", display: "flex", justifyContent: "center", alignItems: "center", gap: 20, opacity: o, transform: `translateY(${(1 - prog(f, a, a + 18)) * 20}px)` }}>
        <Img src={staticFile("brand/crescent-cream.svg")} style={{ width: 84, height: 84 }} />
        <div style={{ fontFamily: FONT, fontSize: 72, fontWeight: 300, color: C.cream, letterSpacing: "-0.03em" }}>clearskin</div>
      </div>
    </>
  );
}

// ── The app's scan screen, phone-shaped, for the hero plate ─────────────

export const PHONE_W = 1080;
export const PHONE_H = 2338;
export const PHONE_SCAN_FRAMES = 107;
const SCAN_FROM = 40; // frame of the scan clip it opens on
const SNAP = 72; // shutter

interface Track {
  tris: [number, number, number][];
  frames: ([number, number][] | null)[];
}

const CHECKS = ["Mapping skin zones", "Checking texture and pores"];

/** Front camera view, the app's top label and shutter, the contour mesh drawing
 * down the face, the shutter, then the analysis lines over the still. */
export function PhoneScan() {
  const f = useCurrentFrame();
  const track = useJson<Track>("track/scan.json");
  if (!track) return null;
  const live = Math.min(f, SNAP);
  const k = PHONE_H / 1920; // cover: scale the 1080×1920 clip to the screen height
  const vw = 1080 * k;
  const dx = (vw - PHONE_W) / 2;
  const pts = track.frames[Math.min(track.frames.length - 1, SCAN_FROM + live)];
  const P = (pts ?? []).map(([x, y]) => [x * vw - dx, y * PHONE_H] as const);
  const ys = P.map((p) => p[1]);
  const [top, bottom] = [Math.min(...ys), Math.max(...ys)];
  const t = prog(f, 6, 52, inOut);
  const line = top - 40 + t * (bottom - top + 80);
  const shown = (y: number) => Math.max(0, Math.min(1, (line - y) / 70));
  const edges = new Map<string, [number, number]>();
  for (const [p, q, r] of track.tris) for (const [u, v] of [[p, q], [q, r], [r, p]]) edges.set(u < v ? `${u}-${v}` : `${v}-${u}`, [u, v]);
  const thinking = prog(f, SNAP + 4, SNAP + 12);
  const flash = Math.exp(-Math.max(0, f - SNAP) / 3) * (f >= SNAP ? 1 : 0);
  const check = CHECKS[f < SNAP + 22 ? 0 : 1];
  return (
    <AbsoluteFill style={{ background: "#000", overflow: "hidden" }}>
      <Freeze frame={SNAP} active={f >= SNAP}>
        <OffthreadVideo src={staticFile("footage/scan.mp4")} trimBefore={SCAN_FROM} muted style={{ position: "absolute", left: -dx, top: 0, width: vw, height: PHONE_H }} />
      </Freeze>
      <svg width={PHONE_W} height={PHONE_H} style={{ position: "absolute", inset: 0, opacity: 1 - 0.6 * thinking }}>
        {[...edges.values()].map(([p, q]) => {
          const o = shown(Math.max(P[p][1], P[q][1]));
          return o > 0 ? <line key={`${p}-${q}`} x1={P[p][0]} y1={P[p][1]} x2={P[q][0]} y2={P[q][1]} stroke={C.cream} strokeWidth={2.4} strokeOpacity={0.6 * o} /> : null;
        })}
        {P.map(([x, y], i) => {
          const o = shown(y);
          return o > 0 ? <circle key={i} cx={x} cy={y} r={4 + 6 * (1 - o)} fill={C.cream} opacity={0.95 * o} /> : null;
        })}
        {t > 0 && t < 1 ? <rect x={0} y={line - 3} width={PHONE_W} height={6} fill={C.mint} style={{ filter: "drop-shadow(0 0 18px rgba(124,196,149,.95))" }} /> : null}
      </svg>
      {/* app chrome: close, pose label, shutter */}
      <div style={{ position: "absolute", top: 150, left: 60, right: 60, display: "flex", alignItems: "center" }}>
        <svg width={56} height={56} viewBox="0 0 24 24"><path d="M6 6l12 12M18 6L6 18" stroke="#fff" strokeWidth={2.2} strokeLinecap="round" /></svg>
      </div>
      <div style={{ position: "absolute", top: 1990, width: "100%", textAlign: "center", fontFamily: FONT, fontSize: 38, fontWeight: 500, letterSpacing: "0.04em", color: "rgba(255,255,255,.85)", opacity: 1 - thinking }}>
        1 of 3 · Front
      </div>
      <div style={{ position: "absolute", top: 2070, left: PHONE_W / 2 - 80, width: 160, height: 160, borderRadius: 80, border: "8px solid #fff", display: "flex", alignItems: "center", justifyContent: "center", opacity: 1 - thinking }}>
        <div style={{ width: 120, height: 120, borderRadius: 60, background: "#fff", transform: `scale(${f >= SNAP - 3 && f < SNAP + 3 ? 0.86 : 1})` }} />
      </div>
      <AbsoluteFill style={{ background: "#fff", opacity: flash * 0.8 }} />
      {/* analysing */}
      <AbsoluteFill style={{ background: `rgba(20,20,19,${0.62 * thinking})` }} />
      {thinking > 0 ? (
        <div style={{ position: "absolute", top: PHONE_H / 2 - 40, width: "100%", textAlign: "center", fontFamily: FONT, fontSize: 52, fontWeight: 400, color: C.cream, opacity: thinking }}>
          <ArcSpinner f={f} />
          <div style={{ height: 50 }} />
          {check}
        </div>
      ) : null}
    </AbsoluteFill>
  );
}

function ArcSpinner({ f }: { f: number }): ReactNode {
  return (
    <svg width={120} height={120} viewBox="0 0 120 120" style={{ transform: `rotate(${f * 9}deg)` }}>
      <circle cx={60} cy={60} r={48} fill="none" stroke="rgba(243,230,202,.18)" strokeWidth={6} />
      <path d="M60 12 A48 48 0 0 1 108 60" fill="none" stroke={C.cream} strokeWidth={6} strokeLinecap="round" />
    </svg>
  );
}
