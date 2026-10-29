// Ad 05 — "Your skin, decoded." Dark and cinematic, in the style of the
// big-brand motion spots: kinetic type, a hard-cut word montage, the scan
// drawing itself over the face, a counter, 3D phones, a logo reveal.
// Every cut is on a beat of "Wallpaper" (92.99 BPM, see render.mjs).
//
// The face is a licensed model photo labelled "Demo scan"; the mesh and lens
// maps are the engine's real readings of that photo, and the scores are the
// ones the app shows for it in the recorded report (seen later in the ad).

import { AbsoluteFill, Img, staticFile, useCurrentFrame } from "remotion";
import type { ReactNode } from "react";
import {
  beatsAt,
  C,
  Count,
  EndCard,
  Enter,
  Flash,
  FONT,
  Glow,
  Grain,
  H,
  inOut,
  Lens,
  type Manifest,
  type Mesh,
  MeshOverlay,
  Note,
  Phone,
  prog,
  Rec,
  useJson,
  W,
  Words,
} from "./kit";

export const BPM = 92.99;
const b = beatsAt(BPM);
export const DECODED_FRAMES = b(30) + 12;

function Range({ from, to, children }: { from: number; to: number; children: ReactNode }) {
  const f = useCurrentFrame();
  return f >= from && f < to ? <>{children}</> : null;
}

const MONTAGE = [
  { word: "Redness.", photo: "skin_macro.jpg" },
  { word: "Breakouts.", photo: "textures.jpg" },
  { word: "Dull days.", photo: "cream_beige.jpg" },
  { word: "Dark marks.", photo: "gel_swirl.jpg" },
];

const LENSES = [
  { name: "redness", color: "#FF5A4E", word: "redness." },
  { name: "texture", color: C.cream, word: "texture." },
  { name: "tone", color: C.amber, word: "tone." },
  { name: "shine", color: "#9FD8FF", word: "shine." },
  { name: "radiance", color: C.mint, word: "glow.", opacity: 0.45 },
];

export function Decoded() {
  const f = useCurrentFrame();
  const mesh = useJson<Mesh>("mesh.json");
  const manifest = useJson<Manifest>("manifest.json");
  if (!mesh || !manifest) return null;

  return (
    <AbsoluteFill style={{ background: C.night }}>
      {/* 1 · Hook: a line of light, two words. */}
      <Range from={0} to={b(2)}>
        <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
          <div
            style={{
              position: "absolute",
              top: 1040,
              height: 3,
              width: 880 * prog(f, 0, b(1.2)),
              background: `linear-gradient(90deg, transparent, ${C.cream}, transparent)`,
              boxShadow: `0 0 40px 6px rgba(243,230,202,.35)`,
            }}
          />
          <Words text="Your skin" at={2} size={150} weight={700} style={{ position: "absolute", top: 740, width: "100%" }} />
          <Words text="is talking." at={b(1)} size={150} weight={700} color={C.mint} style={{ position: "absolute", top: 1090, width: "100%" }} />
        </AbsoluteFill>
      </Range>

      {/* 2 · Montage: a word and a texture every half beat. */}
      {MONTAGE.map((m, i) => {
        const from = b(2 + i * 0.5);
        const to = b(2.5 + i * 0.5);
        const t = prog(f, from, to + 10);
        return (
          <Range key={m.word} from={from} to={to}>
            <AbsoluteFill style={{ overflow: "hidden" }}>
              <Img
                src={staticFile(`broll/${m.photo}`)}
                style={{ width: "100%", height: "100%", objectFit: "cover", transform: `scale(${1.25 - 0.12 * t})`, filter: "brightness(.55) saturate(.9)" }}
              />
              <AbsoluteFill style={{ background: "radial-gradient(circle at 50% 50%, transparent 30%, rgba(0,0,0,.6))" }} />
              <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
                <div style={{ fontFamily: FONT, fontSize: 170, fontWeight: 800, color: "#fff", letterSpacing: "-0.04em", transform: `scale(${1.12 - 0.12 * t})` }}>
                  {m.word}
                </div>
              </AbsoluteFill>
            </AbsoluteFill>
          </Range>
        );
      })}

      {/* 3 · Turn. */}
      <Range from={b(4)} to={b(5)}>
        <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
          <Glow color="rgba(124,196,149,.28)" x={540} y={960} r={620} />
          <Words text="Here's how to read it." at={b(4)} size={92} weight={600} stagger={2} style={{ width: 860 }} />
        </AbsoluteFill>
      </Range>

      {/* 4 · The scan draws itself over the face. */}
      <Range from={b(5)} to={b(11)}>
        <ScanScene mesh={mesh} />
      </Range>

      {/* 5 · Lens montage, one per beat. */}
      {LENSES.map((l, i) => (
        <Range key={l.name} from={b(11 + i)} to={b(12 + i)}>
          <AbsoluteFill>
            <Enter at={b(11 + i)} from={1.05} blur={8}>
              <Img src={staticFile("model.jpg")} style={{ width: W, height: H, filter: "brightness(.38) saturate(.35)" }} />
              <Lens name={l.name} color={l.color} opacity={l.opacity ?? 1} />
            </Enter>
            <AbsoluteFill style={{ background: "linear-gradient(transparent 55%, rgba(0,0,0,.75))" }} />
            <div style={{ position: "absolute", top: 1240, width: "100%", textAlign: "center", fontFamily: FONT, fontSize: 190, fontWeight: 700, letterSpacing: "-0.045em", color: l.color === C.cream ? "#fff" : l.color }}>
              {l.word}
            </div>
            <Note text="Demo scan" style={{ position: "absolute", top: 230, width: "100%", textAlign: "center" }} />
            <Flash at={b(11 + i)} peak={0.18} />
          </AbsoluteFill>
        </Range>
      ))}

      {/* 6 · The score counts up around the app's dial. */}
      <Range from={b(16)} to={b(20)}>
        <ScoreScene />
      </Range>

      {/* 7 · The app: phones in 3D space. */}
      <Range from={b(20)} to={b(26)}>
        <PhonesScene manifest={manifest} />
      </Range>

      {/* 8 · Logo. */}
      <Range from={b(26)} to={DECODED_FRAMES}>
        <AbsoluteFill>
          <Glow color="rgba(243,230,202,.16)" x={540} y={900} r={700} drift={20} />
          <EndCard at={b(26)} tagline="Read your skin." theme="dark" />
        </AbsoluteFill>
      </Range>

      <Flash at={b(5)} peak={0.35} />
      <Flash at={b(16)} peak={0.3} />
      <Flash at={b(20)} peak={0.3} />
      <Grain opacity={0.06} />
    </AbsoluteFill>
  );
}

function ScanScene({ mesh }: { mesh: Mesh }) {
  const f = useCurrentFrame();
  const scanY = 0.12 + 0.86 * prog(f, b(5.3), b(8), inOut);
  const zoom = 1.16 - 0.16 * prog(f, b(5), b(11), inOut);
  const lock = prog(f, b(8), b(8.8));
  const box = { x0: 0.2, x1: 0.86, y0: 0.26, y1: 0.74 };
  const pad = 40 * (1 - lock);
  return (
    <AbsoluteFill style={{ overflow: "hidden" }}>
      <AbsoluteFill style={{ transform: `scale(${zoom})` }}>
        <Img src={staticFile("model.jpg")} style={{ position: "absolute", width: W, height: H, filter: "brightness(.22) saturate(.4)" }} />
        <Img
          src={staticFile("model.jpg")}
          style={{ position: "absolute", width: W, height: H, clipPath: `inset(0 0 ${(1 - scanY) * 100}% 0)`, filter: "brightness(.85)" }}
        />
        <MeshOverlay mesh={mesh} scanY={scanY} color={C.cream} opacity={1 - 0.45 * prog(f, b(9), b(10.5))} />
        {/* the scan line and its trail */}
        {scanY < 0.97 ? (
          <>
            <div style={{ position: "absolute", left: 0, width: W, top: scanY * H - 220, height: 220, background: "linear-gradient(transparent, rgba(124,196,149,.22))" }} />
            <div style={{ position: "absolute", left: 0, width: W, top: scanY * H - 2, height: 4, background: C.mint, boxShadow: `0 0 30px 8px rgba(124,196,149,.6)` }} />
          </>
        ) : null}
        {/* corner brackets lock onto the face */}
        {lock > 0
          ? (
            [
              [box.x0, box.y0, 1, 1],
              [box.x1, box.y0, -1, 1],
              [box.x0, box.y1, 1, -1],
              [box.x1, box.y1, -1, -1],
            ] as const
          ).map(([x, y, sx, sy], i) => (
            <div
              key={i}
              style={{
                position: "absolute",
                left: x * W - (sx > 0 ? pad : 70 - pad),
                top: y * H - (sy > 0 ? pad : 70 - pad),
                width: 70,
                height: 70,
                opacity: lock,
                borderColor: C.cream,
                borderStyle: "solid",
                borderWidth: `${sy > 0 ? 4 : 0}px ${sx < 0 ? 4 : 0}px ${sy < 0 ? 4 : 0}px ${sx > 0 ? 4 : 0}px`,
              }}
            />
          ))
          : null}
      </AbsoluteFill>
      <AbsoluteFill style={{ background: "linear-gradient(rgba(0,0,0,.5), transparent 22%, transparent 70%, rgba(0,0,0,.8))" }} />
      <Note text="Demo scan" style={{ position: "absolute", top: 230, width: "100%", textAlign: "center" }} />
      <Words text="134 points." at={b(8.5)} size={120} weight={700} style={{ position: "absolute", top: 1330, width: "100%" }} />
      <Words text="Read on your phone." at={b(9.5)} size={64} weight={500} color={C.mint} stagger={2} style={{ position: "absolute", top: 1480, width: "100%" }} />
    </AbsoluteFill>
  );
}

// As the app's report shows them for this photo (rec/report).
const SCORES = { score: 75, evenness: 74, clarity: 89, sheen: 57 };

function ScoreScene() {
  const f = useCurrentFrame();
  const r = SCORES;
  const fill = prog(f, b(16.3), b(18.2), inOut) * (r.score / 100);
  const ticks = 72;
  const cx = 540;
  const cy = 860;
  return (
    <AbsoluteFill>
      <Glow color="rgba(124,196,149,.30)" x={540} y={860} r={560} />
      <Enter at={b(16)} from={0.9} blur={20}>
        <svg width={W} height={H} style={{ position: "absolute" }}>
          {Array.from({ length: ticks }, (_, i) => {
            const a = (i / ticks) * 2 * Math.PI - Math.PI / 2;
            const on = i / ticks < fill;
            const r0 = 330;
            const r1 = on ? 380 : 362;
            return (
              <line
                key={i}
                x1={cx + Math.cos(a) * r0}
                y1={cy + Math.sin(a) * r0}
                x2={cx + Math.cos(a) * r1}
                y2={cy + Math.sin(a) * r1}
                stroke={on ? C.mint : "rgba(243,230,202,.18)"}
                strokeWidth={6}
                strokeLinecap="round"
              />
            );
          })}
        </svg>
        <div style={{ position: "absolute", top: 640, width: "100%", textAlign: "center" }}>
          <Note text="Radiance" style={{ opacity: 0.75 }} />
          <div style={{ fontFamily: FONT, fontSize: 300, fontWeight: 200, color: C.cream, letterSpacing: "-0.05em", lineHeight: 1.1 }}>
            <Count from={0} to={r.score} a={b(16.3)} b={b(18.2)} />
          </div>
        </div>
      </Enter>
      <div style={{ position: "absolute", top: 1330, width: "100%", display: "flex", justifyContent: "center", gap: 90 }}>
        {(
          [
            ["Evenness", r.evenness],
            ["Clarity", r.clarity],
            ["Sheen", r.sheen],
          ] as const
        ).map(([label, v], i) => {
          const t = prog(f, b(18 + i * 0.5), b(18.6 + i * 0.5));
          return (
            <div key={label} style={{ textAlign: "center", opacity: t, transform: `translateY(${(1 - t) * 40}px)`, filter: t < 1 ? `blur(${(1 - t) * 10}px)` : undefined }}>
              <div style={{ fontFamily: FONT, fontSize: 96, fontWeight: 300, color: C.cream, letterSpacing: "-0.04em" }}>
                <Count from={0} to={v} a={b(18 + i * 0.5)} b={b(19 + i * 0.5)} />
              </div>
              <div style={{ fontFamily: FONT, fontSize: 32, fontWeight: 500, color: C.cream, opacity: 0.6 }}>{label}</div>
            </div>
          );
        })}
      </div>
      <Note text="Demo scan on a model" style={{ position: "absolute", top: 1580, width: "100%", textAlign: "center", fontSize: 22 }} />
    </AbsoluteFill>
  );
}

function PhonesScene({ manifest }: { manifest: Manifest }) {
  const f = useCurrentFrame();
  const second = f >= b(23);
  const sway = Math.sin((f - b(20)) / 40) * 6;
  const fly = (at: number) => prog(f, at, at + 22);
  const phones = [
    { flow: "plan", x: -330, z: -380, ry: 28, at: b(20.5), speed: 1 },
    { flow: "routine", x: 330, z: -380, ry: -28, at: b(21), speed: 0.8 },
    { flow: second ? "progress" : "report", x: 0, z: 0, ry: 0, at: b(20), speed: second ? 0.7 : 2 },
  ];
  return (
    <AbsoluteFill>
      <Glow color="rgba(63,143,90,.35)" x={300} y={1100} r={700} />
      <Glow color="rgba(243,230,202,.16)" x={850} y={600} r={600} />
      <AbsoluteFill style={{ perspective: 2200, perspectiveOrigin: "50% 45%" }}>
        <div style={{ position: "absolute", inset: 0, transformStyle: "preserve-3d", transform: `rotateY(${sway}deg) rotateX(6deg)` }}>
          {phones.map((p) => {
            const t = fly(p.at);
            return (
              <div
                key={p.x}
                style={{
                  position: "absolute",
                  left: 540 - 260,
                  top: 560,
                  transform: `translate3d(${p.x}px, ${(1 - t) * 900}px, ${p.z}px) rotateY(${p.ry}deg)`,
                  opacity: t,
                  filter: t < 1 ? `blur(${(1 - t) * 14}px)` : undefined,
                }}
              >
                <Phone width={520} aspect={9 / 16} glow={p.z === 0 ? "rgba(124,196,149,.35)" : undefined}>
                  <Rec flow={p.flow} manifest={manifest} at={second && p.z === 0 ? b(23) : p.at} speed={p.speed} />
                </Phone>
              </div>
            );
          })}
        </div>
      </AbsoluteFill>
      <AbsoluteFill style={{ background: "linear-gradient(rgba(8,9,10,.92) 0%, rgba(8,9,10,.6) 22%, transparent 34%)" }} />
      {second ? (
        <>
          <Words text="Then see" at={b(23)} size={96} weight={700} style={{ position: "absolute", top: 210, width: "100%" }} />
          <Words text="what changes." at={b(23.5)} size={96} weight={700} color={C.mint} style={{ position: "absolute", top: 320, width: "100%" }} />
          <Note text="Sample data" style={{ position: "absolute", top: 1560, width: "100%", textAlign: "center", fontSize: 22 }} />
          <Flash at={b(23)} peak={0.22} />
        </>
      ) : (
        <>
          <Words text="A routine built" at={b(20)} size={96} weight={700} style={{ position: "absolute", top: 210, width: "100%" }} />
          <Words text="from your scan." at={b(21)} size={96} weight={700} color={C.mint} style={{ position: "absolute", top: 320, width: "100%" }} />
        </>
      )}
    </AbsoluteFill>
  );
}
