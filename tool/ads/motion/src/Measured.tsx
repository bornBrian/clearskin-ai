// Ad 12: "Your skin, measured." Voiced, 22 s, cut to the voice-over.
// Dark open: the products you've tried fly in, then spiral away ("Still
// guessing?"). Light middle: meet ClearSkin, one scan draws the real
// 134-point mesh, nine measurements burst out, a routine ticks itself off,
// the score rolls up. Dark close: "Every scan. Every step. Every week."
// and the logo on a hard cut to silence.
// No people, no photos: the props are 3D (props3d.tsx), the mesh is the
// engine's own, the numbers are an example scan and say so.

import { ThreeCanvas } from "@remotion/three";
import type { ReactNode } from "react";
import { AbsoluteFill, Img, spring, staticFile, useCurrentFrame } from "remotion";
import { C, FONT, FPS, Grain, H, inOut, type Mesh, prog, useJson, W } from "./kit";
import { Dust, Finale, MaskText, Odometer, Phone3D, Range, Scene, Shake, Slam, Vignette } from "./premium";
import { Dropper, Drop, Jar, Leaf, Pump, Serum, Sparkle, Studio, Sun, Tube } from "./props3d";
import T from "./sound/Measured.timeline.json";

export const MEASURED_FRAMES = T._end.at;

const DARK = "#141413";
const PAPER = "#F6F2EA";
const INK = "#1D1F1C";
const SAGE = "#6E9A78";

/** px per scene unit for a camera at z=17, fov 38, on a 1920px-tall frame. */
const U = 164;
const ux = (x: number) => (x - W / 2) / U;
const uy = (y: number) => (H / 2 - y) / U;
const CAM = { position: [0, 0, 17] as [number, number, number], fov: 38 };

const pop = (f: number, at: number, cfg = { damping: 12, stiffness: 160, mass: 0.8 }) => spring({ frame: f - at, fps: FPS, config: cfg });

function Stage({ children, warm }: { children: ReactNode; warm?: number }) {
  return (
    <ThreeCanvas width={W} height={H} camera={CAM} gl={{ antialias: true }} style={{ position: "absolute", inset: 0 }}>
      <Studio warm={warm} />
      {children}
    </ThreeCanvas>
  );
}

export function Measured() {
  const mesh = useJson<Mesh>("mesh.json");
  if (!mesh) return null;
  return (
    <AbsoluteFill style={{ background: DARK }}>
      <Range from={0} to={T.meet.at}>
        <Tried />
      </Range>
      <Range from={T.meet.at - 2} to={T.scan.at}>
        <Meet />
      </Range>
      <Range from={T.scan.at} to={T.routine.at}>
        <ScanAndNine mesh={mesh} />
      </Range>
      <Scene from={T.routine.at} to={T.change.at} enter="rise" bg={PAPER} blur={false} push={0.03}>
        <Routine />
      </Scene>
      <Scene from={T.change.at} to={T.every1.at} enter="right" bg={PAPER} push={0.03}>
        <Change />
      </Scene>
      <Scene from={T.every1.at} to={T.brand.at} enter="cut" exit="cut" bg={DARK} push={0.06}>
        <Every />
      </Scene>
      <Scene from={T.brand.at} to={MEASURED_FRAMES} enter="cut" exit="cut" bg={DARK} push={0.03}>
        <Dust count={20} seed="end" />
        <Finale at={T.brand.at + 2} tagline="Your skin, measured." theme="dark" />
      </Scene>
      <Grain opacity={0.05} />
    </AbsoluteFill>
  );
}

// ── 1. "You've tried the serum. The toner. The ten-step routine. Still guessing?"

const BURST: { at: number; x: number; y: number; s: number; el: (p: { position: [number, number, number]; rotation: [number, number, number]; scale: number }) => ReactNode }[] = [
  { at: 0, x: 540, y: 900, s: 1.35, el: (p) => <Serum {...p} /> },
  { at: 2, x: 190, y: 1060, s: 1.15, el: (p) => <Jar {...p} /> },
  { at: 3, x: 900, y: 1040, s: 1.2, el: (p) => <Tube {...p} /> },
  { at: 4, x: 880, y: 360, s: 1.05, el: (p) => <Sun {...p} /> },
  { at: 5, x: 170, y: 400, s: 1.2, el: (p) => <Drop {...p} /> },
  { at: 6, x: 560, y: 330, s: 0.95, el: (p) => <Leaf {...p} /> },
  { at: 7, x: 400, y: 1190, s: 0.6, el: (p) => <Sparkle {...p} /> },
];

function Tried() {
  const f = useCurrentFrame();
  const g = T.guessing.at;
  const end = T.meet.at;
  // the vortex: everything spirals into the centre and vanishes
  const v = prog(f, g, end - 2, (t) => t * t);
  const swirl = (x: number, y: number, s: number, spin: number) => {
    const dx = ux(x);
    const dy = uy(y) - uy(860);
    const r = Math.hypot(dx, dy) * (1 - v);
    const a = Math.atan2(dy, dx) + v * v * 7;
    return { position: [Math.cos(a) * r, uy(860) + Math.sin(a) * r, 0] as [number, number, number], scale: s * (1 - v * 0.9), rotation: [0.2, spin + v * 9, 0.1] as [number, number, number] };
  };
  const enter = (at: number, x0: number, y0: number, x: number, y: number) => {
    const s = pop(f, at, { damping: 15, stiffness: 120, mass: 1 });
    return [x0 + (x - x0) * s, y0 + (y - y0) * s] as const;
  };
  const [dx, dy] = enter(T.serum.at - 6, -300, 1500, 330, 700);
  const [px, py] = enter(T.toner.at - 6, 1400, 300, 770, 760);
  const lift = prog(f, T.tenstep.at - 4, T.tenstep.at + 10);
  return (
    <AbsoluteFill style={{ background: `radial-gradient(ellipse at 50% 42%, #2C2C29, ${DARK} 70%)` }}>
      <Stage warm={0.9}>
        <group>
          {(() => {
            const d = swirl(dx, dy - lift * 150, 1.75, f / 30);
            return <Dropper {...d} rotation={[0.18, d.rotation[1], -0.18 + 0.1 * Math.sin(f / 20)]} />;
          })()}
          {(() => {
            const p = swirl(px, py - lift * 170, 1.45, 0.6 + f / 40);
            return <Pump {...p} rotation={[0.1, p.rotation[1], 0.12]} />;
          })()}
          {BURST.map((b, i) => {
            const s = pop(f, T.tenstep.at + b.at);
            if (s <= 0.001) return null;
            const x = 540 + (b.x - 540) * s;
            const y = 860 + (b.y - 860) * s;
            const w = swirl(x, y, b.s * s, i + f / (26 + i * 3));
            return <group key={i}>{b.el(w)}</group>;
          })}
        </group>
      </Stage>
      <Vignette strength={0.55} />
      <div style={{ position: "absolute", top: 1330, width: "100%" }}>
        <Range from={T.serum.at} to={T.toner.at}>
          <MaskText lines={[{ text: "You've tried", color: "rgba(243,230,202,.55)" }, "the serum."]} at={T.serum.at} every={4} size={112} weight={600} />
        </Range>
        <Range from={T.toner.at} to={T.tenstep.at}>
          <MaskText lines={["The toner."]} at={T.toner.at} size={112} weight={600} />
        </Range>
        <Range from={T.tenstep.at} to={T.guessing.at}>
          <MaskText lines={["The ten-step", "routine."]} at={T.tenstep.at} every={4} size={112} weight={600} />
        </Range>
      </div>
      <Range from={T.guessing.at} to={T.meet.at}>
        <Slam text="Still guessing?" at={T.guessing.at} size={124} split={false} style={{ position: "absolute", top: 1390, width: "100%" }} />
      </Range>
      {/* white-out into the light half */}
      <AbsoluteFill style={{ background: PAPER, opacity: prog(f, end - 5, end, inOut) }} />
    </AbsoluteFill>
  );
}

// ── 2. "Meet ClearSkin AI."

function Meet() {
  const f = useCurrentFrame();
  const at = T.meet.at;
  const meetUp = prog(f, at + 14, at + 26, inOut);
  const sweep = prog(f, at + 8, at + 24, inOut);
  const floatY = (i: number) => Math.sin(f / 18 + i * 1.7) * 0.12;
  const out = prog(f, T.scan.at - 8, T.scan.at, (t) => t * t * t);
  return (
    <AbsoluteFill style={{ background: `radial-gradient(ellipse at 50% 45%, #FFFDF8, ${PAPER} 60%, #ECE3D2)`, transform: `scale(${1 + out * 0.6})`, opacity: 1 - out, filter: out ? `blur(${out * 20}px)` : undefined }}>
      <Stage>
        {[
          { at: 10, x: 230, y: 560, s: 0.55, el: (p: object) => <Sparkle {...p} /> },
          { at: 13, x: 860, y: 1290, s: 0.7, el: (p: object) => <Leaf {...p} /> },
          { at: 16, x: 870, y: 600, s: 0.55, el: (p: object) => <Drop {...p} /> },
          { at: 19, x: 220, y: 1320, s: 0.35, el: (p: object) => <Sparkle {...p} /> },
        ].map((d, i) => {
          const s = pop(f, at + d.at);
          return s > 0.001 ? (
            <group key={i}>{d.el({ position: [ux(d.x), uy(d.y) + floatY(i), 0], rotation: [0.25, f / 35 + i, 0.3], scale: d.s * s })}</group>
          ) : null;
        })}
      </Stage>
      <div style={{ position: "absolute", top: 760 - meetUp * 90, width: "100%", textAlign: "center", fontFamily: FONT, fontSize: 92, fontWeight: 500, color: INK, letterSpacing: "-0.03em", opacity: prog(f, at, at + 8) * (1 - meetUp * 0.55) }}>
        Meet
      </div>
      <div style={{ position: "absolute", top: 860, width: "100%", display: "flex", justifyContent: "center", alignItems: "center", gap: 30 }}>
        <Img
          src={staticFile("brand/crescent-ink.svg")}
          style={{
            width: 150,
            height: 150,
            WebkitMaskImage: `conic-gradient(from 210deg, #000 ${sweep * 360}deg, transparent ${sweep * 360 + 0.5}deg)`,
            maskImage: `conic-gradient(from 210deg, #000 ${sweep * 360}deg, transparent ${sweep * 360 + 0.5}deg)`,
          }}
        />
        <div style={{ display: "flex", fontFamily: FONT, fontSize: 118, fontWeight: 300, color: INK, letterSpacing: "-0.035em", overflow: "hidden", padding: "6px 4px 16px" }}>
          {"clearskin".split("").map((ch, i) => {
            const s = spring({ frame: f - at - 10 - i * 1.5, fps: FPS, config: { damping: 200, stiffness: 120 } });
            return (
              <span key={i} style={{ display: "inline-block", transform: `translateY(${(1 - s) * 120}%)` }}>
                {ch}
              </span>
            );
          })}
          <span style={{ display: "inline-block", marginLeft: 22, fontWeight: 600, color: SAGE, transform: `translateY(${(1 - spring({ frame: f - at - 26, fps: FPS, config: { damping: 14, stiffness: 160 } })) * 120}%)` }}>AI</span>
        </div>
      </div>
    </AbsoluteFill>
  );
}

// ── 3. "One scan of your face, nine measurements of your skin."

/** The engine's 134-point mesh, drawn top to bottom inside a [w]×[h] box. */
function MeshDraw({ mesh, w, h, t, color }: { mesh: Mesh; w: number; h: number; t: number; color: string }) {
  const pts = mesh.points.map(([x, y]) => [((x - 0.13) / 0.74) * w, ((y - 0.27) / 0.5) * h * 0.92 + h * 0.04] as const);
  const edges = new Map<string, [number, number]>();
  for (const [a, b, c] of mesh.tris) for (const [p, q] of [[a, b], [b, c], [c, a]]) edges.set(p < q ? `${p}-${q}` : `${q}-${p}`, [p, q]);
  const line = t * (h + 60) - 30;
  const shown = (y: number) => Math.max(0, Math.min(1, (line - y) / 50));
  return (
    <svg width={w} height={h} style={{ position: "absolute", inset: 0 }}>
      {[...edges.values()].map(([p, q]) => {
        const o = shown(Math.max(pts[p][1], pts[q][1]));
        return o > 0 ? <line key={`${p}-${q}`} x1={pts[p][0]} y1={pts[p][1]} x2={pts[q][0]} y2={pts[q][1]} stroke={color} strokeWidth={1.3} strokeOpacity={0.42 * o} /> : null;
      })}
      {pts.map(([x, y], i) => {
        const o = shown(y);
        return o > 0 ? <circle key={i} cx={x} cy={y} r={2.2 + 5 * (1 - o)} fill={color} opacity={0.95 * o} /> : null;
      })}
      {t > 0 && t < 1 ? <rect x={0} y={line - 2} width={w} height={4} fill={C.mint} style={{ filter: "drop-shadow(0 0 14px rgba(124,196,149,.9))" }} /> : null}
    </svg>
  );
}

const NINE = [
  ["Blemishes", 64], ["Texture", 71], ["Pores", 61],
  ["Redness", 58], ["Even tone", 67], ["Hydration", 80],
  ["Oil balance", 66], ["Smoothness", 74], ["Under-eyes", 70],
] as const;

function ScanAndNine({ mesh }: { mesh: Mesh }) {
  const f = useCurrentFrame();
  const a = T.scan.at;
  const n = T.nine.at;
  const rise = spring({ frame: f - a, fps: FPS, config: { damping: 16, stiffness: 110, mass: 1 } });
  const scanT = prog(f, a + 10, n - 2, inOut);
  const done = prog(f, n - 4, n + 4);
  const away = prog(f, n - 2, n + 7, inOut);
  const gridIn = prog(f, n + 8, n + 24, inOut);
  const out = prog(f, T.routine.at - 7, T.routine.at, (t) => t * t * t);
  const phoneW = 470;
  return (
    <AbsoluteFill style={{ background: `radial-gradient(ellipse at 50% 50%, #FFFDF8, ${PAPER} 62%, #ECE3D2)`, transform: `scale(${1 + out * 1.4})`, opacity: 1 - out * 0.9, filter: out ? `blur(${out * 24}px)` : undefined }}>
      <div style={{ position: "absolute", top: 250, width: "100%" }}>
        <Range from={a} to={n}>
          <MaskText lines={["One scan."]} at={a + 2} size={112} color={INK} weight={600} out={n - 6} />
        </Range>
        <Range from={n} to={T.routine.at}>
          <MaskText lines={["Nine measurements."]} at={n + 2} size={96} color={INK} weight={600} />
        </Range>
      </div>

      {/* the phone: rises, scans, then shrinks into the burst */}
      {away < 1 ? (
        <AbsoluteFill style={{ perspective: 1800 }}>
          <div style={{ position: "absolute", left: 540 - phoneW / 2, top: 470 + (1 - rise) * 1300, transform: `scale(${1 - away * 0.7})`, opacity: 1 - away, transformOrigin: "50% 45%" }}>
            <Phone3D width={phoneW} rx={10 - 10 * rise} ry={-14 + 14 * prog(f, a, n, inOut)} glow="rgba(124,196,149,.35)">
              <AbsoluteFill style={{ background: "radial-gradient(ellipse at 50% 45%, #1E211F, #0B0C0B)" }}>
                <div style={{ position: "absolute", top: 70, width: "100%", textAlign: "center", fontFamily: FONT, fontSize: 22, fontWeight: 600, letterSpacing: "0.2em", color: "rgba(243,230,202,.6)" }}>
                  {done > 0.5 ? "DONE" : "HOLD STILL"}
                </div>
                <div style={{ position: "absolute", left: 20, top: 150, width: phoneW - 68, height: 560 }}>
                  <MeshDraw mesh={mesh} w={phoneW - 68} h={560} t={scanT} color={C.cream} />
                </div>
                <div style={{ position: "absolute", bottom: 60, left: "50%", width: 74, height: 74, marginLeft: -37, borderRadius: 37, background: C.mint, transform: `scale(${done})`, display: "flex", alignItems: "center", justifyContent: "center" }}>
                  <svg width={36} height={36} viewBox="0 0 24 24"><path d="M5 12.5l4.5 4.5L19 7.5" fill="none" stroke="#0B0C0B" strokeWidth={2.8} strokeLinecap="round" strokeLinejoin="round" /></svg>
                </div>
              </AbsoluteFill>
            </Phone3D>
          </div>
        </AbsoluteFill>
      ) : null}

      {/* nine numbers fly out of the phone into a hairline grid */}
      <div style={{ position: "absolute", left: 90, top: 560, width: 900, height: 900 }}>
        {[1, 2].map((k) => (
          <div key={`v${k}`} style={{ position: "absolute", left: k * 300, top: 0, width: 1.5, height: 900, background: "rgba(29,31,28,.16)", transform: `scaleY(${gridIn})` }} />
        ))}
        {[1, 2].map((k) => (
          <div key={`h${k}`} style={{ position: "absolute", top: k * 300, left: 0, height: 1.5, width: 900, background: "rgba(29,31,28,.16)", transform: `scaleX(${gridIn})` }} />
        ))}
        {NINE.map(([label, value], i) => {
          const order = [4, 1, 3, 5, 7, 0, 2, 6, 8].indexOf(i); // centre first, corners last
          const s = spring({ frame: f - n - 6 - order * 2, fps: FPS, config: { damping: 13, stiffness: 150, mass: 0.7 } });
          if (s <= 0.001) return null;
          const cx = (i % 3) * 300 + 150;
          const cy = Math.floor(i / 3) * 300 + 150;
          const x = 450 + (cx - 450) * s;
          const y = 360 + (cy - 360) * s;
          return (
            <div key={label} style={{ position: "absolute", left: x - 150, top: y - 150, width: 300, height: 300, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", transform: `scale(${0.4 + 0.6 * s})`, opacity: Math.min(1, s * 1.5) }}>
              <Odometer from={0} to={value} a={n + 8 + order * 2} b={n + 30 + order * 2} size={124} color={INK} weight={200} />
              <div style={{ marginTop: 14, fontFamily: FONT, fontSize: 25, fontWeight: 600, letterSpacing: "0.14em", color: "rgba(29,31,28,.55)" }}>{label.toUpperCase()}</div>
            </div>
          );
        })}
      </div>
      <div style={{ position: "absolute", top: 1500, width: "100%", textAlign: "center", fontFamily: FONT, fontSize: 24, fontWeight: 500, color: "rgba(29,31,28,.4)", opacity: gridIn }}>Example scan</div>
    </AbsoluteFill>
  );
}

// ── 4. "A routine built around it."

const STEPS = [
  { n: "01", name: "Gentle cleanser", sub: "Low-foam, fragrance-free" },
  { n: "02", name: "Vitamin C serum", sub: "L-ascorbic acid 10–15%" },
  { n: "03", name: "Moisturiser", sub: "Glycerin, ceramides" },
  { n: "04", name: "Sunscreen SPF 30+", sub: "Broad-spectrum UVA/UVB" },
];

function Routine() {
  const f = useCurrentFrame();
  const at = T.routine.at;
  const card = spring({ frame: f - at, fps: FPS, config: { damping: 18, stiffness: 120, mass: 1 } });
  const rowY = (i: number) => 700 + i * 168;
  const tick = (i: number) => at + 12 + i * 7;
  const PROPS = [
    (p: object) => <Pump {...p} />,
    (p: object) => <Dropper {...p} />,
    (p: object) => <Jar {...p} />,
    (p: object) => <Sun {...p} />,
  ];
  const scales = [0.42, 0.5, 0.62, 0.42];
  const yOff = [100, 100, 68, 30]; // rows centre at rowY + 30; bottles sit on their base, the sun is centred
  return (
    <AbsoluteFill style={{ background: `radial-gradient(ellipse at 50% 40%, #FFFDF8, ${PAPER} 60%, #E9E0CF)` }}>
      <div style={{ position: "absolute", top: 250, width: "100%" }}>
        <MaskText lines={["A routine,", { text: "built around it.", color: SAGE }]} at={at + 2} every={4} size={96} color={INK} weight={600} />
      </div>
      <div style={{ position: "absolute", inset: 0, perspective: 1600 }}>
        <div
          style={{
            position: "absolute",
            left: 250,
            top: 560,
            width: 750,
            height: 760,
            borderRadius: 40,
            background: "#FFFFFF",
            boxShadow: "0 50px 90px -40px rgba(40,34,20,.35), 0 0 0 1px rgba(29,31,28,.05)",
            transform: `translateY(${(1 - card) * 500}px) rotateX(${(1 - card) * 24}deg)`,
            transformOrigin: "50% 100%",
            opacity: Math.min(1, card * 2),
            fontFamily: FONT,
          }}
        >
          <div style={{ position: "absolute", left: 56, top: 50, fontSize: 24, fontWeight: 600, letterSpacing: "0.2em", color: "rgba(29,31,28,.5)" }}>MORNING</div>
          {STEPS.map((s, i) => {
            const k = spring({ frame: f - tick(i), fps: FPS, config: { damping: 11, stiffness: 220, mass: 0.6 } });
            const on = f >= tick(i);
            return (
              <div key={s.n} style={{ position: "absolute", left: 56, right: 56, top: rowY(i) - 560 - 40, height: 140, borderTop: i ? "1.5px solid rgba(29,31,28,.08)" : undefined, display: "flex", alignItems: "center" }}>
                <div style={{ width: 70, fontSize: 30, fontWeight: 300, color: "rgba(29,31,28,.4)" }}>{s.n}</div>
                <div style={{ flex: 1 }}>
                  <div style={{ fontSize: 38, fontWeight: 600, color: INK, letterSpacing: "-0.02em" }}>{s.name}</div>
                  <div style={{ fontSize: 26, fontWeight: 400, color: "rgba(29,31,28,.5)", marginTop: 4 }}>{s.sub}</div>
                </div>
                <div style={{ width: 64, height: 64, borderRadius: 32, border: `3px solid ${on ? INK : "rgba(29,31,28,.2)"}`, background: on ? INK : "transparent", display: "flex", alignItems: "center", justifyContent: "center", transform: `scale(${on ? 0.7 + 0.3 * k : 1})` }}>
                  {on ? (
                    <svg width={34} height={34} viewBox="0 0 24 24"><path d="M5 12.5l4.5 4.5L19 7.5" fill="none" stroke="#FFFFFF" strokeWidth={2.8} strokeLinecap="round" strokeLinejoin="round" strokeDasharray={24} strokeDashoffset={24 * (1 - Math.min(1, k * 1.4))} /></svg>
                  ) : null}
                </div>
              </div>
            );
          })}
        </div>
      </div>
      {/* a 3D object beside each step, popping in as it's ticked */}
      <Stage>
        {PROPS.map((el, i) => {
          const s = pop(f, tick(i) - 4);
          return s > 0.001 ? (
            <group key={i}>{el({ position: [ux(132), uy(rowY(i) + yOff[i]) + Math.sin(f / 16 + i) * 0.06, 0.5], rotation: i === 3 ? [0, 0, f / 40] : [0.2, f / 30 + i * 0.8, 0.08], scale: scales[i] * s })}</group>
          ) : null;
        })}
      </Stage>
    </AbsoluteFill>
  );
}

// ── 5. "Then see what's actually changing."

function Change() {
  const f = useCurrentFrame();
  const at = T.change.at;
  const draw = prog(f, at + 8, at + 38, inOut);
  const pts = [64, 63, 66, 67, 66, 70, 72, 71, 74, 76];
  const cw = 760;
  const ch = 300;
  const path = pts
    .map((v, i) => {
      const x = (i / (pts.length - 1)) * cw;
      const y = ch - ((v - 58) / 22) * ch;
      return `${i ? "L" : "M"}${x.toFixed(1)},${y.toFixed(1)}`;
    })
    .join(" ");
  const len = 1100;
  return (
    <AbsoluteFill style={{ background: `radial-gradient(ellipse at 50% 40%, #FFFDF8, ${PAPER} 60%, #E9E0CF)`, fontFamily: FONT }}>
      <div style={{ position: "absolute", top: 250, width: "100%" }}>
        <MaskText lines={["See what's", { text: "really changing.", color: SAGE }]} at={at + 2} every={4} size={96} color={INK} weight={600} />
      </div>
      <div style={{ position: "absolute", left: 100, top: 580, width: 880, height: 820, borderRadius: 40, background: "#FFFFFF", boxShadow: "0 50px 90px -40px rgba(40,34,20,.35), 0 0 0 1px rgba(29,31,28,.05)" }}>
        <div style={{ position: "absolute", left: 60, top: 54, fontSize: 24, fontWeight: 600, letterSpacing: "0.2em", color: "rgba(29,31,28,.5)" }}>SKIN SCORE</div>
        <div style={{ position: "absolute", left: 52, top: 100, display: "flex", alignItems: "flex-end", gap: 26 }}>
          <Odometer from={64} to={76} a={at + 8} b={at + 38} size={230} color={INK} weight={200} />
          <div style={{ marginBottom: 34, fontSize: 52, fontWeight: 600, color: SAGE, opacity: prog(f, at + 36, at + 44), transform: `translateY(${(1 - prog(f, at + 36, at + 46)) * 20}px)` }}>+12</div>
        </div>
        <svg width={cw} height={ch + 20} style={{ position: "absolute", left: 60, top: 420, overflow: "visible" }}>
          <defs>
            <linearGradient id="area" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0" stopColor="rgba(110,154,120,.28)" />
              <stop offset="1" stopColor="rgba(110,154,120,0)" />
            </linearGradient>
            <clipPath id="reveal"><rect x={0} y={-20} width={cw * draw} height={ch + 40} /></clipPath>
          </defs>
          <path d={`${path} L${cw},${ch} L0,${ch} Z`} fill="url(#area)" clipPath="url(#reveal)" />
          <path d={path} fill="none" stroke={SAGE} strokeWidth={5} strokeLinejoin="round" strokeLinecap="round" strokeDasharray={len} strokeDashoffset={len * (1 - draw)} />
          {draw > 0.98 ? <circle cx={cw} cy={ch - ((76 - 58) / 22) * ch} r={11} fill={SAGE} /> : null}
        </svg>
        <div style={{ position: "absolute", left: 60, right: 60, bottom: 46, display: "flex", justifyContent: "space-between", fontSize: 24, fontWeight: 500, color: "rgba(29,31,28,.45)" }}>
          <span>Week 1</span>
          <span>Week 8</span>
        </div>
      </div>
      <div style={{ position: "absolute", top: 1440, width: "100%", textAlign: "center", fontSize: 24, fontWeight: 500, color: "rgba(29,31,28,.4)" }}>Example progress</div>
    </AbsoluteFill>
  );
}

// ── 6. "Every scan. Every step. Every week."

function Every() {
  const f = useCurrentFrame();
  const beats = [T.every1.at, T.every2.at, T.every3.at];
  const words = ["Every scan.", "Every step.", "Every week."];
  const lit = beats.reduce((acc, b) => acc + prog(f, b, b + 10) * 20, 0);
  const r = 300;
  return (
    <Shake at={beats} power={10}>
      <AbsoluteFill style={{ background: `radial-gradient(ellipse at 50% 45%, #262624, ${DARK} 68%)` }}>
        <svg width={W} height={H} style={{ position: "absolute", inset: 0 }}>
          {Array.from({ length: 60 }, (_, i) => {
            const a = (i / 60) * Math.PI * 2 - Math.PI / 2;
            const major = i % 5 === 0;
            const on = i < lit;
            const len = major ? 34 : 20;
            return (
              <line
                key={i}
                x1={540 + Math.cos(a) * r}
                y1={860 + Math.sin(a) * r}
                x2={540 + Math.cos(a) * (r - len)}
                y2={860 + Math.sin(a) * (r - len)}
                stroke={on ? C.cream : "rgba(243,230,202,.16)"}
                strokeWidth={major ? 5 : 3}
                strokeLinecap="round"
              />
            );
          })}
        </svg>
        {words.map((w, i) => (
          <Range key={w} from={beats[i]} to={i < 2 ? beats[i + 1] : T.brand.at}>
            <Slam text={w} at={beats[i]} size={128} split={false} style={{ position: "absolute", top: 1330, width: "100%" }} />
          </Range>
        ))}
        <div style={{ position: "absolute", top: 860 - 70, width: "100%", textAlign: "center", fontFamily: FONT, fontSize: 140, fontWeight: 200, color: C.cream, letterSpacing: "-0.05em", opacity: prog(f, beats[0], beats[0] + 8) }}>
          {f >= beats[2] ? "12" : f >= beats[1] ? "4" : "1"}
        </div>
        <div style={{ position: "absolute", top: 860 + 84, width: "100%", textAlign: "center", fontFamily: FONT, fontSize: 24, fontWeight: 600, letterSpacing: "0.2em", color: "rgba(243,230,202,.5)", opacity: prog(f, beats[0], beats[0] + 8) }}>
          {f >= beats[2] ? "WEEKS" : f >= beats[1] ? "STEPS" : "SCAN"}
        </div>
      </AbsoluteFill>
    </Shake>
  );
}

