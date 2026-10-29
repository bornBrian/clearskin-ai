// Ad 06 — "Start with your skin." Light and airy, in the style of the
// polished product-launch films: soft gradient light, a scrolling word
// list with floating photo tiles, big kinetic statements, the app in a
// tilting phone. Every cut is on a beat of "Carefree" (96 BPM).

import { AbsoluteFill, Img, interpolate, staticFile, useCurrentFrame } from "remotion";
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

export const BPM = 96;
const b = beatsAt(BPM);
export const PRODUCTS_FRAMES = b(32) + 12;

function Range({ from, to, children }: { from: number; to: number; children: ReactNode }) {
  const f = useCurrentFrame();
  return f >= from && f < to ? <>{children}</> : null;
}

const INGREDIENTS = [
  "Retinol",
  "Niacinamide",
  "Vitamin C",
  "Salicylic acid",
  "Snail mucin",
  "Hyaluronic acid",
  "Azelaic acid",
  "Ceramides",
  "Glycolic acid",
  "Benzoyl peroxide",
];

const TILES = [
  { photo: "dropper_amber.jpg", x: -70, y: 170, w: 300, h: 380, r: -8, at: 0 },
  { photo: "cream_beige.jpg", x: 820, y: 230, w: 290, h: 300, r: 7, at: 0.5 },
  { photo: "serum_pour.jpg", x: -40, y: 1380, w: 320, h: 300, r: 6, at: 1 },
  { photo: "gel_swirl.jpg", x: 790, y: 1300, w: 300, h: 380, r: -6, at: 1.5 },
];

function Backdrop() {
  return (
    <AbsoluteFill style={{ background: C.paper }}>
      <Glow color="rgba(176,214,186,.9)" x={180} y={420} r={720} drift={60} />
      <Glow color="rgba(243,230,202,1)" x={940} y={1420} r={760} drift={50} />
      <Glow color="rgba(255,214,190,.75)" x={620} y={900} r={560} drift={80} />
    </AbsoluteFill>
  );
}

export function Products() {
  const f = useCurrentFrame();
  const mesh = useJson<Mesh>("mesh.json");
  const manifest = useJson<Manifest>("manifest.json");
  if (!mesh || !manifest) return null;

  return (
    <AbsoluteFill>
      <Backdrop />

      {/* 1 · Hook: a question, a number climbing behind it. */}
      <Range from={0} to={b(3)}>
        <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
          <div style={{ position: "absolute", top: 520, width: "100%", textAlign: "center", fontFamily: FONT, fontSize: 760, fontWeight: 800, color: C.leaf, opacity: 0.1, letterSpacing: "-0.06em" }}>
            <Count from={1} to={14} a={0} b={b(3)} />
          </div>
          <Words text="How many products" at={0} size={104} weight={700} color={C.ink} stagger={2} style={{ position: "absolute", top: 700, width: 980 }} />
          <Words text="did you try" at={b(1)} size={104} weight={700} color={C.ink} style={{ position: "absolute", top: 820, width: "100%" }} />
          <Words text="this year?" at={b(2)} size={104} weight={700} color={C.leaf} style={{ position: "absolute", top: 940, width: "100%" }} />
        </AbsoluteFill>
      </Range>

      {/* 2 · The list everyone scrolls through, with product tiles. */}
      <Range from={b(3)} to={b(8)}>
        <ListScene />
      </Range>

      {/* 3 · The point. */}
      <Range from={b(8)} to={b(11)}>
        <AbsoluteFill>
          <Words text="Trending" at={b(8)} size={176} weight={800} color={C.ink} style={{ position: "absolute", top: 640, width: "100%" }} />
          <Words text="isn't the same as" at={b(9)} size={74} weight={500} color={C.ink} stagger={2} style={{ position: "absolute", top: 850, width: "100%" }} />
          <Words text="right for you." at={b(10)} size={150} weight={800} color={C.leaf} style={{ position: "absolute", top: 960, width: "100%" }} />
          <Flash at={b(8)} peak={0.4} />
        </AbsoluteFill>
      </Range>

      {/* 4 · The face, through a window of light. */}
      <Range from={b(11)} to={b(16)}>
        <FaceScene mesh={mesh} />
      </Range>

      {/* 5 · Routine, then shelf, in a tilting phone. */}
      <Range from={b(16)} to={b(27)}>
        <AppScene manifest={manifest} />
      </Range>

      {/* 6 · Logo. */}
      <Range from={b(27)} to={PRODUCTS_FRAMES}>
        <EndCard at={b(27)} tagline="Start with your skin." theme="light" />
      </Range>

      <Grain opacity={0.05} />
    </AbsoluteFill>
  );
}

function ListScene() {
  const f = useCurrentFrame();
  const half = b(0.5);
  // Glide to each item on the half beat, settling fast.
  const raw = (f - b(3)) / half;
  const step = Math.floor(raw);
  const pos = Math.min(INGREDIENTS.length - 1, step + prog(raw - step, 0, 0.45));
  return (
    <AbsoluteFill>
      {TILES.map((t, i) => {
        const k = prog(f, b(3 + t.at * 0.6), b(3 + t.at * 0.6) + 16);
        const drift = Math.sin((f + i * 30) / 38) * 14;
        return (
          <div
            key={t.photo}
            style={{
              position: "absolute",
              left: t.x,
              top: t.y + drift + (1 - k) * 120,
              width: t.w,
              height: t.h,
              borderRadius: 34,
              overflow: "hidden",
              opacity: k,
              transform: `rotate(${t.r}deg) scale(${0.85 + 0.15 * k})`,
              boxShadow: "0 40px 80px -30px rgba(21,26,23,.35)",
            }}
          >
            <Img src={staticFile(`broll/${t.photo}`)} style={{ width: "100%", height: "100%", objectFit: "cover" }} />
          </div>
        );
      })}
      {INGREDIENTS.map((name, i) => {
        const d = i - pos;
        const a = Math.abs(d);
        if (a > 3.2) return null;
        const focus = Math.max(0, 1 - a);
        return (
          <div
            key={name}
            style={{
              position: "absolute",
              top: 900 + d * 128,
              width: "100%",
              textAlign: "center",
              fontFamily: FONT,
              fontSize: 62 + 34 * focus,
              fontWeight: focus > 0.5 ? 700 : 500,
              color: C.ink,
              letterSpacing: "-0.03em",
              opacity: interpolate(a, [0, 1, 2, 3.2], [1, 0.42, 0.18, 0]),
              filter: a > 0.6 ? `blur(${(a - 0.6) * 2.4}px)` : undefined,
            }}
          >
            {focus > 0.5 ? <span style={{ display: "inline-block", width: 22, height: 22, borderRadius: 11, background: C.leaf, marginRight: 26, verticalAlign: "middle", transform: "translateY(-6px)" }} /> : null}
            {name}
          </div>
        );
      })}
    </AbsoluteFill>
  );
}

function FaceScene({ mesh }: { mesh: Mesh }) {
  const f = useCurrentFrame();
  const open = prog(f, b(11), b(12.5), inOut);
  const radius = 20 + 380 * open;
  const zoom = 1.25 - 0.15 * prog(f, b(11), b(16), inOut);
  const clip = `circle(${radius}px at 540px 800px)`;
  return (
    <AbsoluteFill>
      <div style={{ position: "absolute", left: 540 - radius - 40, top: 800 - radius - 40, width: (radius + 40) * 2, height: (radius + 40) * 2, borderRadius: "50%", background: "radial-gradient(circle, rgba(124,196,149,.45), transparent 70%)" }} />
      <AbsoluteFill style={{ clipPath: clip }}>
        <AbsoluteFill style={{ transform: `scale(${zoom})`, transformOrigin: "540px 800px" }}>
          <Img src={staticFile("model.jpg")} style={{ position: "absolute", left: 0, top: -160, width: W, height: H }} />
          <div style={{ position: "absolute", left: 0, top: -160, width: W, height: H }}>
            <MeshOverlay mesh={mesh} scanY={1.2} color={C.cream} opacity={0.75 * prog(f, b(12.5), b(13.5))} />
          </div>
        </AbsoluteFill>
      </AbsoluteFill>
      <Words text="ClearSkin reads" at={b(12)} size={96} weight={700} color={C.ink} style={{ position: "absolute", top: 1270, width: "100%" }} />
      <Words text="your skin first." at={b(13)} size={96} weight={700} color={C.leaf} style={{ position: "absolute", top: 1380, width: "100%" }} />
      <Note text="Demo scan on a model" color={C.ink} style={{ position: "absolute", top: 1530, width: "100%", textAlign: "center", fontSize: 22 }} />
    </AbsoluteFill>
  );
}

function AppScene({ manifest }: { manifest: Manifest }) {
  const f = useCurrentFrame();
  const shelf = f >= b(22);
  const t = prog(f, b(16), b(16) + 24);
  const ry = Math.sin((f - b(16)) / 44) * 10;
  return (
    <AbsoluteFill>
      <AbsoluteFill style={{ perspective: 2000 }}>
        <div
          style={{
            position: "absolute",
            left: 540 - 280,
            top: 470,
            transform: `translateY(${(1 - t) * 1100}px) rotateX(${8 - 8 * t + 4}deg) rotateY(${ry}deg)`,
          }}
        >
          <Phone width={560} aspect={9 / 16} glow="rgba(63,143,90,.25)">
            <Enter at={shelf ? b(22) : b(16)} from={1.04} blur={10}>
              <Rec flow={shelf ? "shelf" : "routine"} manifest={manifest} at={shelf ? b(22) : b(16.5)} speed={shelf ? 0.5 : 0.7} />
            </Enter>
          </Phone>
        </div>
      </AbsoluteFill>
      {shelf ? (
        <>
          <Words text="And checks your shelf" at={b(22)} size={84} weight={700} color={C.ink} stagger={2} style={{ position: "absolute", top: 200, width: "100%" }} />
          <Words text="for clashes." at={b(23)} size={84} weight={700} color={C.leaf} style={{ position: "absolute", top: 305, width: "100%" }} />
          <Flash at={b(22)} peak={0.35} />
        </>
      ) : (
        <>
          <Words text="Then builds a routine" at={b(16)} size={84} weight={700} color={C.ink} stagger={2} style={{ position: "absolute", top: 200, width: "100%" }} />
          <Words text="around it." at={b(17)} size={84} weight={700} color={C.leaf} style={{ position: "absolute", top: 305, width: "100%" }} />
        </>
      )}
    </AbsoluteFill>
  );
}
