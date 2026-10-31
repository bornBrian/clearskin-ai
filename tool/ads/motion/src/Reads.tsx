// Ad 13: "ClearSkin AI reads your skin." Voiced, 20 s, cut to the voice-over.
// Real footage open: the crowded shelf, the feed, layering cream, checking
// the mirror ("and hope"). Then a live scan: the app's contour mesh tracked
// onto a real face, frame by frame (track.py). The real app on a phone: the
// report's breakdown, the routine being ticked off (recorded), progress.
// Close on a real smile and the logo, "Available now on Google Play".
// Footage: Mixkit Video Free License. Sound effects: recorded (Mixkit SFX).

import type { ReactNode } from "react";
import { AbsoluteFill, Img, OffthreadVideo, Sequence, staticFile, useCurrentFrame } from "remotion";
import { C, Flash, FONT, Grain, H, inOut, type Manifest, prog, Rec, useJson, W } from "./kit";
import { Dust, Finale, MaskText, Phone3D, Range, Scene, Vignette } from "./premium";
import T from "./sound/Reads.timeline.json";

export const READS_FRAMES = T._end.at;

/** Frame of the scan clip the scene opens on: she's facing the camera, hands down. */
const SCAN_FROM = 45;

interface Track {
  aspect: number;
  tris: [number, number, number][];
  frames: ([number, number][] | null)[];
}

const GRADE = "contrast(1.06) saturate(1.05) brightness(0.98)";

/** A footage cut, full-bleed, from frame [from] to [to], starting [skip] frames into the clip. */
function Shot({ name, from, to, skip = 0, push = 0.05, blur = 0, dim = 0 }: { name: string; from: number; to: number; skip?: number; push?: number; blur?: number; dim?: number }) {
  const f = useCurrentFrame();
  const s = 1 + push * prog(f, from, to, (t) => t);
  return (
    <Sequence from={from} durationInFrames={to - from} layout="none">
      <AbsoluteFill style={{ overflow: "hidden", background: "#000" }}>
        <OffthreadVideo
          src={staticFile(`footage/${name}.mp4`)}
          trimBefore={skip}
          muted
          style={{ width: W, height: H, objectFit: "cover", transform: `scale(${s + blur / 400})`, filter: `${GRADE}${blur ? ` blur(${blur}px)` : ""}` }}
        />
        {dim ? <AbsoluteFill style={{ background: `rgba(12,12,11,${dim})` }} /> : null}
      </AbsoluteFill>
    </Sequence>
  );
}

/** Words over footage: low in the frame (inside the safe area), on a soft shade. */
function Caption({ lines, at, top = 1250 }: { lines: (string | { text: string; color?: string })[]; at: number; top?: number }) {
  return (
    <>
      <AbsoluteFill style={{ background: "linear-gradient(180deg, transparent 50%, rgba(0,0,0,.5) 82%)" }} />
      <div style={{ position: "absolute", top, width: "100%", textShadow: "0 4px 30px rgba(0,0,0,.35)" }}>
        <MaskText lines={lines} at={at} every={4} size={96} weight={600} color="#FFFFFF" />
      </div>
    </>
  );
}

// ── The live scan ────────────────────────────────────────────────────

function LiveScan({ track }: { track: Track }) {
  const f = useCurrentFrame();
  const a = T.reads.at;
  const pts = track.frames[Math.min(track.frames.length - 1, SCAN_FROM + f - a)];
  if (!pts) return null;
  const P = pts.map(([x, y]) => [x * W, y * H] as const);
  const ys = P.map((p) => p[1]);
  const xs = P.map((p) => p[0]);
  const [top, bottom, left, right] = [Math.min(...ys), Math.max(...ys), Math.min(...xs), Math.max(...xs)];
  // a line sweeps down the face; points light as it passes
  const t = prog(f, a + 8, a + 46, inOut);
  const line = top - 40 + t * (bottom - top + 80);
  const shown = (y: number) => Math.max(0, Math.min(1, (line - y) / 60));
  const captured = prog(f, a + 78, a + 86);
  const fade = 1 - 0.55 * captured;
  const edges = new Map<string, [number, number]>();
  for (const [p, q, r] of track.tris) for (const [u, v] of [[p, q], [q, r], [r, p]]) edges.set(u < v ? `${u}-${v}` : `${v}-${u}`, [u, v]);
  const pad = 70;
  const br = 54; // bracket arm
  const bx = [left - pad, right + pad];
  const by = [top - pad - 30, bottom + pad];
  const brk = prog(f, a, a + 10);
  return (
    <svg width={W} height={H} style={{ position: "absolute", inset: 0 }}>
      {[...edges.values()].map(([p, q]) => {
        const o = shown(Math.max(P[p][1], P[q][1]));
        return o > 0 ? <line key={`${p}-${q}`} x1={P[p][0]} y1={P[p][1]} x2={P[q][0]} y2={P[q][1]} stroke={C.cream} strokeWidth={2.2} strokeOpacity={0.62 * o * fade} /> : null;
      })}
      {P.map(([x, y], i) => {
        const o = shown(y);
        return o > 0 ? <circle key={i} cx={x} cy={y} r={3.6 + 6 * (1 - o)} fill={C.cream} opacity={0.95 * o * fade} /> : null;
      })}
      {t > 0 && t < 1 ? (
        <rect x={bx[0]} y={line - 2} width={bx[1] - bx[0]} height={4} rx={2} fill={C.mint} style={{ filter: "drop-shadow(0 0 16px rgba(124,196,149,.95))" }} />
      ) : null}
      {/* camera brackets around the face */}
      {[[0, 0], [1, 0], [0, 1], [1, 1]].map(([i, j]) => {
        const x = bx[i];
        const y = by[j];
        const dx = (i ? -1 : 1) * br * brk;
        const dy = (j ? -1 : 1) * br * brk;
        return <path key={`${i}${j}`} d={`M${x + dx},${y} L${x},${y} L${x},${y + dy}`} fill="none" stroke={captured > 0.5 ? C.mint : "#FFFFFF"} strokeWidth={5} strokeLinecap="round" opacity={0.9} />;
      })}
    </svg>
  );
}

function ScanScene({ track }: { track: Track }) {
  const f = useCurrentFrame();
  const a = T.reads.at;
  const done = f >= a + 80;
  return (
    <AbsoluteFill>
      <LiveScan track={track} />
      <div style={{ position: "absolute", top: 210, width: "100%", textAlign: "center", fontFamily: FONT, fontSize: 26, fontWeight: 600, letterSpacing: "0.22em", color: "#FFFFFF", opacity: 0.85 * prog(f, a, a + 8), textShadow: "0 2px 18px rgba(0,0,0,.35)" }}>
        {done ? "SCANNED" : "HOLD STILL"}
      </div>
      <Caption lines={["One scan."]} at={a + 10} top={1330} />
      <Flash at={a + 78} peak={0.45} />
    </AbsoluteFill>
  );
}

// ── The real app on a phone ──────────────────────────────────────────

/** A design render, filling the screen width from its top, scrolled [scroll] px (in 720-wide render pixels). */
function Screen({ src, scroll = 0 }: { src: string; scroll?: number }) {
  return <Img src={staticFile(`renders/${src}.png`)} style={{ position: "absolute", left: 0, top: 0, width: "100%", transform: `translateY(${-scroll * (100 / 720)}%)` }} />;
}

function AppScenes({ manifest }: { manifest: Manifest }) {
  const f = useCurrentFrame();
  const n = T.nine.at;
  const r = T.routine.at;
  const c = T.change.at;
  const rise = prog(f, n - 4, n + 14);
  const phoneW = 610;
  const toBreakdown = prog(f, n + 14, n + 26, inOut);
  // screens slide up into each other on the line
  const slide = (at: number) => prog(f, at - 3, at + 9, inOut);
  const toRoutine = slide(r);
  const toProgress = slide(c);
  const caption = (lines: (string | { text: string; color?: string })[], at: number, to: number) => (
    <Range from={at} to={to}>
      <div style={{ position: "absolute", top: 240, width: "100%" }}>
        <MaskText lines={lines} at={at + 1} every={4} size={84} weight={600} color={C.cream} />
      </div>
    </Range>
  );
  return (
    <AbsoluteFill>
      {caption(["Nine measurements."], n, r)}
      {caption(["A routine built", { text: "for what it finds.", color: C.mint }], r, c)}
      {caption(["See what's", { text: "really changing.", color: C.mint }], c, c + 40)}
      <AbsoluteFill style={{ perspective: 1800 }}>
        <div style={{ position: "absolute", left: 540 - phoneW / 2, top: 500 + (1 - rise) * 1300, transform: `rotate(${-3 + 3 * rise}deg)` }}>
          <Phone3D width={phoneW} rx={8 * (1 - rise) + 2 * Math.sin(f / 40)} ry={-10 + 10 * prog(f, n, c + 40, inOut)} glow="rgba(124,196,149,.25)">
            <AbsoluteFill style={{ background: C.paper }}>
              <div style={{ position: "absolute", inset: 0, transform: `translateY(${-100 * (toRoutine)}%)` }}>
                {/* report: score, then the breakdown of nine */}
                <AbsoluteFill style={{ overflow: "hidden" }}>
                  <AbsoluteFill style={{ transform: `translateY(${-100 * toBreakdown}%)` }}>
                    <Screen src="05-scan-report" />
                  </AbsoluteFill>
                  <AbsoluteFill style={{ transform: `translateY(${100 - 100 * toBreakdown}%)` }}>
                    <Screen src="05b-breakdown" />
                  </AbsoluteFill>
                </AbsoluteFill>
              </div>
              {/* the routine, recorded from the app as steps are ticked off; its
                  older nav bar is covered with the screen's own background */}
              <div style={{ position: "absolute", inset: 0, overflow: "hidden", transform: `translateY(${100 - 100 * toRoutine - 100 * toProgress}%)` }}>
                <Rec flow="routine" at={r} manifest={manifest} />
                <div style={{ position: "absolute", left: 0, right: 0, bottom: 0, height: "12.5%", background: "rgb(237,242,236)" }} />
              </div>
              <div style={{ position: "absolute", inset: 0, overflow: "hidden", transform: `translateY(${100 - 100 * toProgress}%)` }}>
                <Screen src="08-progress" scroll={60 * prog(f, c + 6, c + 40, inOut)} />
              </div>
            </AbsoluteFill>
          </Phone3D>
        </div>
      </AbsoluteFill>
      <div style={{ position: "absolute", top: 1640, width: "100%", textAlign: "center", fontFamily: FONT, fontSize: 24, fontWeight: 500, color: "rgba(243,230,202,.5)", opacity: rise }}>
        Example results
      </div>
    </AbsoluteFill>
  );
}

// ── The ad ───────────────────────────────────────────────────────────

export function Reads() {
  const track = useJson<Track>("track/scan.json");
  const manifest = useJson<Manifest>("manifest.json");
  if (!track || !manifest) return null;
  const glowAt = T.change.at + 40;
  return (
    <AbsoluteFill style={{ background: "#000" }}>
      {/* 1. the problem, in real life */}
      <Shot name="shelf" from={0} to={T.feed.at} skip={6} />
      <Shot name="feed" from={T.feed.at} to={T.layer.at} />
      <Shot name="layer" from={T.layer.at} to={T.hope.at} push={0.07} />
      <Shot name="man" from={T.hope.at} to={T.hope.at + 19} />
      <Shot name="woman" from={T.hope.at + 19} to={T.reads.at} />
      <Range from={0} to={T.feed.at}>
        <Caption lines={["Your shelf", "is full."]} at={T.shelf.at} />
      </Range>
      <Range from={T.feed.at} to={T.layer.at}>
        <Caption lines={["Your feed says", "buy one more."]} at={T.feed.at} />
      </Range>
      <Range from={T.layer.at} to={T.hope.at}>
        <Caption lines={["So you layer it on,"]} at={T.layer.at} />
      </Range>
      <Range from={T.hope.at} to={T.reads.at}>
        <Caption lines={["and hope."]} at={T.hope.at} />
      </Range>

      {/* 2. a live scan on a real face */}
      <Shot name="scan" from={T.reads.at} to={T.nine.at} skip={SCAN_FROM} push={0.03} />
      <Range from={T.reads.at} to={T.nine.at}>
        <ScanScene track={track} />
      </Range>

      {/* 3. the real app */}
      <Scene from={T.nine.at - 4} to={glowAt} enter="zoom" exit="cut" push={0.02} blur={false}>
        <Shot name="end-soft" from={T.nine.at - 4} to={glowAt} dim={0.5} push={0.04} />
        <Dust count={18} seed="app" color="243,230,202" />
        <AppScenes manifest={manifest} />
      </Scene>

      {/* 4. the result: a real smile, then the logo over it */}
      <Shot name="glow" from={glowAt} to={READS_FRAMES} push={0.06} />
      <Range from={T.brand.at} to={READS_FRAMES}>
        <BrandOver />
      </Range>
      <Vignette strength={0.35} />
      <Grain opacity={0.04} />
    </AbsoluteFill>
  );
}

function BrandOver(): ReactNode {
  const f = useCurrentFrame();
  const a = T.brand.at;
  const k = prog(f, a - 2, a + 10, inOut);
  return (
    <AbsoluteFill>
      <AbsoluteFill style={{ backdropFilter: `blur(${k * 26}px)`, WebkitBackdropFilter: `blur(${k * 26}px)`, background: `rgba(14,14,13,${k * 0.62})` }} />
      <Dust count={22} seed="end" />
      <Finale at={a + 2} tagline="Know your skin." theme="dark" footer="Available now on Google Play" badge />
    </AbsoluteFill>
  );
}
