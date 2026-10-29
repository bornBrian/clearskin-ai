// Ad 08 — "Stop guessing." The core promise in plain words: buying skincare
// blind doesn't work; scan, get a routine for your skin, track it.
// Picture and score share src/sound/Guessing.json (100 BPM: a beat is
// exactly 18 frames).

import { AbsoluteFill, Img, staticFile, useCurrentFrame } from "remotion";
import {
  beatsAt,
  C,
  FONT,
  Grain,
  H,
  inOut,
  type Manifest,
  type Mesh,
  MeshOverlay,
  Note,
  prog,
  Rec,
  useJson,
  W,
} from "./kit";
import { Aurora, Dust, Finale, Float, LightLeak, MaskText, Phone3D, Range, Scene, Shake, Slam, Vignette } from "./premium";
import spec from "./sound/Guessing.json";

const b = beatsAt(spec.bpm);
export const GUESSING_FRAMES = b(spec.beats) + 18;

const TUNNEL = ["serum_pour.jpg", "dropper_amber.jpg", "cream_beige.jpg", "gel_swirl.jpg", "textures.jpg", "shelf.jpg", "skin_macro.jpg"];

export function Guessing() {
  const mesh = useJson<Mesh>("mesh.json");
  const manifest = useJson<Manifest>("manifest.json");
  if (!mesh || !manifest) return null;
  return (
    <AbsoluteFill style={{ background: "#0A0A09" }}>
      <Shake at={[b(4), b(5), b(6), b(7), b(8)]}>
        <Scene from={0} to={b(4)} enter="cut">
          <Tunnel />
        </Scene>

        {[0, 1, 2, 3].map((i) => (
          <Scene key={i} from={b(4 + i)} to={b(5 + i)} enter="cut" exit={i === 3 ? "fade" : "cut"} push={0.08}>
            <Agitate i={i} />
          </Scene>
        ))}

        <Scene from={b(8)} to={b(12)} enter="cut" bg="#07090A">
          <Aurora base="#07090A" colors={["rgba(63,143,90,.45)", "rgba(124,196,149,.25)", "rgba(243,230,202,.12)"]} />
          <Dust count={34} seed="drop" />
          <Slam text="Stop" at={b(8)} size={220} style={{ position: "absolute", top: 600, width: "100%" }} />
          <Slam text="guessing." at={b(8.5)} size={210} color={C.mint} style={{ position: "absolute", top: 830, width: "100%" }} />
          <MaskText lines={["Read your skin first."]} at={b(10)} size={66} weight={500} style={{ position: "absolute", top: 1170, width: "100%", opacity: 0.85 }} />
          <LightLeak at={b(8)} color="rgba(124,196,149,.6)" />
          <Vignette />
        </Scene>
      </Shake>

      <Range from={b(12)} to={b(24)}>
        <Steps mesh={mesh} manifest={manifest} />
      </Range>

      <Scene from={b(24)} to={b(28)} bg={C.paper} exit="zoom">
        <Aurora base={C.paper} colors={["rgba(176,214,186,.85)", "rgba(243,230,202,1)", "rgba(255,214,190,.7)"]} />
        <MaskText lines={["Made for", { text: "your skin.", color: C.leaf }]} at={b(24)} size={150} weight={800} color={C.ink} style={{ position: "absolute", top: 640, width: "100%" }} />
        <MaskText lines={["Not the trend."]} at={b(26)} size={78} weight={500} color={C.ink} style={{ position: "absolute", top: 1010, width: "100%", opacity: 0.55 }} />
      </Scene>

      <Scene from={b(28)} to={GUESSING_FRAMES} bg="#07090A" exit="cut" push={0.03}>
        <Aurora base="#07090A" colors={["rgba(63,143,90,.30)", "rgba(243,230,202,.10)"]} />
        <Dust count={24} seed="end" />
        <Finale at={b(28)} tagline="Scan. Plan. Track." theme="dark" glow="rgba(124,196,149,.8)" />
      </Scene>
      <Grain opacity={0.06} />
    </AbsoluteFill>
  );
}

/** Products rush past the camera while the question lands. */
function Tunnel() {
  const f = useCurrentFrame();
  return (
    <AbsoluteFill>
      <Aurora base="#0A0A09" colors={["rgba(227,174,85,.20)", "rgba(240,86,43,.10)"]} />
      <AbsoluteFill style={{ perspective: 900 }}>
        {Array.from({ length: 12 }, (_, i) => {
          const start = i * b(0.55) - 16;
          const t = (f - start) / 30;
          if (t < 0 || t > 1.15) return null;
          const z = -2200 + t * 2900;
          const ang = i * 2.4;
          const x = Math.cos(ang) * 430;
          const y = Math.sin(ang) * 620;
          return (
            <div
              key={i}
              style={{
                position: "absolute",
                left: 540 - 280 + x,
                top: 960 - 350 + y,
                width: 560,
                height: 700,
                borderRadius: 36,
                overflow: "hidden",
                transform: `translateZ(${z}px) rotateZ(${(i % 2 ? -1 : 1) * 8}deg)`,
                opacity: Math.min(1, t * 4),
                boxShadow: "0 30px 80px rgba(0,0,0,.5)",
              }}
            >
              <Img src={staticFile(`broll/${TUNNEL[i % TUNNEL.length]}`)} style={{ width: "100%", height: "100%", objectFit: "cover" }} />
            </div>
          );
        })}
      </AbsoluteFill>
      <AbsoluteFill style={{ background: "radial-gradient(ellipse at 50% 46%, rgba(10,10,9,.88) 16%, rgba(10,10,9,.25) 48%, transparent 70%)" }} />
      <MaskText lines={["Still guessing", { text: "what your skin", color: C.amber }, { text: "needs?", color: C.amber }]} at={2} every={6} size={118} style={{ position: "absolute", top: 640, width: "100%" }} />
      <Vignette strength={0.7} />
    </AbsoluteFill>
  );
}

const AGITATE = [
  { word: "New serum.", photo: "serum_pour.jpg", tint: "rgba(10,10,9,.45)", color: C.cream },
  { word: "New breakout.", photo: "skin_macro.jpg", tint: "rgba(60,8,6,.62)", color: "#FFB4A8" },
  { word: "New serum.", photo: "dropper_amber.jpg", tint: "rgba(10,10,9,.45)", color: C.cream },
  { word: "New breakout.", photo: "textures.jpg", tint: "rgba(60,8,6,.66)", color: "#FFB4A8" },
];

function Agitate({ i }: { i: number }) {
  const a = AGITATE[i];
  return (
    <AbsoluteFill>
      <Img src={staticFile(`broll/${a.photo}`)} style={{ width: "100%", height: "100%", objectFit: "cover", filter: "saturate(.9) contrast(1.05)" }} />
      <AbsoluteFill style={{ background: a.tint }} />
      <Vignette strength={0.75} />
      <Slam text={a.word} at={b(4 + i)} size={128} color={a.color} style={{ position: "absolute", top: 860, width: "100%" }} />
    </AbsoluteFill>
  );
}

const STEPS = [
  { n: "01", title: ["Scan", "your face."], note: "Shown on a model" },
  { n: "02", title: ["Get a routine", "for your skin."], note: "" },
  { n: "03", title: ["Track what", "changes."], note: "Sample data" },
];

/** The three steps: phones on a rail, the camera dollies between them. */
function Steps({ mesh, manifest }: { mesh: Mesh; manifest: Manifest }) {
  const f = useCurrentFrame();
  const gap = 760;
  const cam = gap * (prog(f, b(16) - 6, b(16) + 10, inOut) + prog(f, b(20) - 6, b(20) + 10, inOut));
  const step = f < b(16) ? 0 : f < b(20) ? 1 : 2;
  const enter = prog(f, b(12), b(12) + 20);
  const exitZoom = prog(f, b(24) - 7, b(24), (t) => t * t * t);
  return (
    <AbsoluteFill style={{ background: "#07090A", opacity: 1 - exitZoom * 0.9, filter: exitZoom ? `blur(${exitZoom * 24}px)` : undefined, transform: `scale(${1 + exitZoom * 1.4})` }}>
      <Aurora base="#07090A" colors={["rgba(63,143,90,.35)", "rgba(243,230,202,.10)", "rgba(124,196,149,.18)"]} />
      <Dust count={30} seed="steps" />
      <Float amount={0.7}>
        <AbsoluteFill style={{ perspective: 1800, perspectiveOrigin: "50% 50%" }}>
          {STEPS.map((s, i) => {
            const x = i * gap - cam;
            const d = Math.abs(x) / gap;
            return (
              <div
                key={s.n}
                style={{
                  position: "absolute",
                  left: 540 - 250 + x,
                  top: 600 + (1 - enter) * 900,
                  transformStyle: "preserve-3d",
                  transform: `translateZ(${-d * 520}px)`,
                  opacity: 1 - Math.min(0.75, d * 0.6),
                }}
              >
                <Phone3D width={500} ry={-x / 26} rx={6} glow={i === step ? "rgba(124,196,149,.45)" : undefined}>
                  {i === 0 ? <ScanScreen mesh={mesh} /> : null}
                  {i === 1 ? <Rec flow="routine" manifest={manifest} at={b(16.5)} speed={0.75} /> : null}
                  {i === 2 ? <Rec flow="progress" manifest={manifest} at={b(20.3)} speed={0.7} /> : null}
                </Phone3D>
              </div>
            );
          })}
        </AbsoluteFill>
      </Float>
      <AbsoluteFill style={{ background: "linear-gradient(#07090A 0%, rgba(7,9,10,.85) 17%, transparent 30%)" }} />
      {STEPS.map((s, i) => (
        <Range key={s.n} from={b(12 + i * 4)} to={b(16 + i * 4)}>
          <div style={{ position: "absolute", top: 205, width: "100%", textAlign: "center", fontFamily: FONT, fontSize: 30, fontWeight: 600, letterSpacing: "0.3em", color: C.mint }}>
            {s.n} / 03
          </div>
          <MaskText lines={s.title} at={b(12 + i * 4) + 3} size={96} style={{ position: "absolute", top: 260, width: "100%" }} out={b(16 + i * 4) - 9} />
          {s.note ? <Note text={s.note} style={{ position: "absolute", top: 1560, width: "100%", textAlign: "center", fontSize: 22 }} /> : null}
        </Range>
      ))}
    </AbsoluteFill>
  );
}

/** Inside the first phone: the demo scan drawing itself. */
function ScanScreen({ mesh }: { mesh: Mesh }) {
  const f = useCurrentFrame();
  const scanY = 0.15 + 0.85 * prog(f, b(12.6), b(14.6), inOut);
  const k = 470 / W;
  return (
    <div style={{ position: "absolute", left: 0, top: 0, width: W, height: H, transform: `scale(${k})`, transformOrigin: "0 0" }}>
      <Img src={staticFile("model.jpg")} style={{ position: "absolute", width: W, height: H, filter: "brightness(.35) saturate(.5)" }} />
      <Img src={staticFile("model.jpg")} style={{ position: "absolute", width: W, height: H, clipPath: `inset(0 0 ${(1 - scanY) * 100}% 0)` }} />
      <MeshOverlay mesh={mesh} scanY={scanY} color={C.cream} />
      {scanY < 0.99 ? <div style={{ position: "absolute", left: 0, width: W, top: scanY * H - 3, height: 6, background: C.mint, boxShadow: "0 0 40px 12px rgba(124,196,149,.6)" }} /> : null}
    </div>
  );
}
