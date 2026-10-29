// Ad 11 — "Your skin, explained." Bumps, marks, dry patches: what's going
// on? One selfie gives a report in plain words, then a routine for it.
// The scan is the labelled demo on a model; the findings are the example
// report the app shows for it (rec/report). 96 BPM.

import { AbsoluteFill, Img, staticFile, useCurrentFrame } from "remotion";
import { beatsAt, C, Grain, H, inOut, type Manifest, type Mesh, MeshOverlay, Note, prog, Rec, useJson, W } from "./kit";
import { Aurora, Dust, Finale, Float, Glass, LightLeak, MaskText, Phone3D, Pop, Range, Scene, Shake, Slam, Vignette } from "./premium";
import spec from "./sound/Explained.json";

const b = beatsAt(spec.bpm);
export const EXPLAINED_FRAMES = b(spec.beats) + 18;

const NIGHT = "#08090A";

const QUESTIONS = [
  { word: "Bumps?", x: 0.44, y: 0.6, zoom: 2.0 },
  { word: "Dark marks?", x: 0.14, y: 0.58, zoom: 2.2 },
  { word: "Dry patches?", x: 0.5, y: 0.15, zoom: 2.2 },
  { word: "Redness?", x: 0.24, y: 0.63, zoom: 1.9 },
];

export function Explained() {
  const f = useCurrentFrame();
  const mesh = useJson<Mesh>("mesh.json");
  const manifest = useJson<Manifest>("manifest.json");
  if (!mesh || !manifest) return null;
  return (
    <AbsoluteFill style={{ background: NIGHT }}>
      <Shake at={[0, b(1), b(2), b(3), b(8)]} power={16}>
        {QUESTIONS.map((q, i) => (
          <Scene key={q.word} from={b(i)} to={b(i + 1)} enter="cut" exit="cut" push={0.1}>
            <Question q={q} at={b(i)} />
          </Scene>
        ))}

        <Scene from={b(4)} to={b(8)} enter="cut" exit="fade" bg={NIGHT}>
          <Img src={staticFile("broll/skin_macro.jpg")} style={{ width: "100%", height: "100%", objectFit: "cover", filter: "blur(30px) brightness(.35)" }} />
          <MaskText lines={["What's actually", { text: "going on?", color: C.amber }]} at={b(4)} size={124} style={{ position: "absolute", top: 760, width: "100%" }} />
          <Vignette strength={0.7} />
        </Scene>

        <Range from={b(8)} to={b(14)}>
          <Selfie mesh={mesh} />
        </Range>
      </Shake>

      <Range from={b(14)} to={b(24)}>
        <Report manifest={manifest} />
      </Range>

      <Scene from={b(24)} to={b(28)} bg={NIGHT}>
        <Aurora base={NIGHT} colors={["rgba(63,143,90,.38)", "rgba(243,230,202,.10)"]} />
        <Dust count={22} seed="rt" />
        <MaskText lines={["Then a routine", { text: "made for it.", color: C.mint }]} at={b(24)} size={96} style={{ position: "absolute", top: 230, width: "100%" }} />
        <AbsoluteFill style={{ perspective: 1800 }}>
          <div style={{ position: "absolute", left: 540 - 250, top: 520 }}>
            <Phone3D width={500} rx={8} ry={-10 + 16 * prog(f, b(24), b(28), inOut)} glow="rgba(124,196,149,.45)">
              <Rec flow="routine" manifest={manifest} at={b(24.2) - 14} speed={1} />
            </Phone3D>
          </div>
        </AbsoluteFill>
      </Scene>

      <Scene from={b(28)} to={EXPLAINED_FRAMES} bg="#07090A" exit="cut" push={0.03}>
        <Aurora base="#07090A" colors={["rgba(63,143,90,.30)", "rgba(243,230,202,.10)"]} />
        <Dust count={24} seed="end" />
        <Finale at={b(28)} tagline="Understand your skin." theme="dark" glow="rgba(124,196,149,.8)" />
      </Scene>
      <Grain opacity={0.06} />
    </AbsoluteFill>
  );
}

/** A macro close-up, a target ring locking onto a spot, one word. */
function Question({ q, at }: { q: (typeof QUESTIONS)[number]; at: number }) {
  const f = useCurrentFrame();
  const ring = prog(f, at + 2, at + 12);
  return (
    <AbsoluteFill style={{ overflow: "hidden" }}>
      {/* the photo at its own aspect, so (x, y) of the photo lands on the ring */}
      <Img
        src={staticFile("broll/skin_macro.jpg")}
        style={{ position: "absolute", width: H * q.zoom * (1466 / 2200), height: H * q.zoom, left: 540 - q.x * H * q.zoom * (1466 / 2200), top: 760 - q.y * H * q.zoom, filter: "contrast(1.08) saturate(1.05) brightness(.8)" }}
      />
      <Vignette strength={0.6} />
      <div style={{ position: "absolute", left: 540 - 170, top: 760 - 170, width: 340, height: 340, borderRadius: "50%", border: `5px solid rgba(243,230,202,${ring})`, transform: `scale(${1.6 - 0.6 * ring})`, boxShadow: `0 0 40px rgba(243,230,202,${0.4 * ring})` }} />
      <div style={{ position: "absolute", left: 540 - 6, top: 760 - 6, width: 12, height: 12, borderRadius: 6, background: C.cream, opacity: ring }} />
      <Slam text={q.word} at={at} size={150} style={{ position: "absolute", top: 1080, width: "100%" }} />
    </AbsoluteFill>
  );
}

/** One selfie: flash, then the scan draws itself. */
function Selfie({ mesh }: { mesh: Mesh }) {
  const f = useCurrentFrame();
  const flash = Math.exp(-Math.max(0, f - b(8)) / 4);
  const scanY = 0.12 + 0.86 * prog(f, b(8.6), b(11), inOut);
  const zoom = 1.12 - 0.12 * prog(f, b(8), b(14), inOut);
  const exitZoom = prog(f, b(14) - 7, b(14), (t) => t * t * t);
  return (
    <AbsoluteFill style={{ overflow: "hidden", transform: `scale(${1 + exitZoom * 1.4})`, opacity: 1 - exitZoom * 0.9, filter: exitZoom ? `blur(${exitZoom * 24}px)` : undefined }}>
      <AbsoluteFill style={{ transform: `scale(${zoom})` }}>
        <Img src={staticFile("model.jpg")} style={{ position: "absolute", width: W, height: H, filter: "brightness(.25) saturate(.4)" }} />
        <Img src={staticFile("model.jpg")} style={{ position: "absolute", width: W, height: H, clipPath: `inset(0 0 ${(1 - scanY) * 100}% 0)`, filter: "brightness(.9)" }} />
        <MeshOverlay mesh={mesh} scanY={scanY} color={C.cream} opacity={1 - 0.5 * prog(f, b(12), b(13))} />
        {scanY < 0.97 ? (
          <>
            <div style={{ position: "absolute", left: 0, width: W, top: scanY * H - 240, height: 240, background: "linear-gradient(transparent, rgba(124,196,149,.25))" }} />
            <div style={{ position: "absolute", left: 0, width: W, top: scanY * H - 2, height: 5, background: C.mint, boxShadow: "0 0 36px 10px rgba(124,196,149,.6)" }} />
          </>
        ) : null}
      </AbsoluteFill>
      <AbsoluteFill style={{ background: "linear-gradient(rgba(0,0,0,.65), transparent 25%, transparent 66%, rgba(0,0,0,.85))" }} />
      <Slam text="One selfie." at={b(8)} size={150} split={false} style={{ position: "absolute", top: 250, width: "100%" }} />
      <MaskText lines={["134 points,", { text: "read in seconds.", color: C.mint }]} at={b(11.5)} size={84} style={{ position: "absolute", top: 1330, width: "100%" }} />
      <Note text="Demo scan" style={{ position: "absolute", top: 420, width: "100%", textAlign: "center" }} />
      <AbsoluteFill style={{ background: "#fff", opacity: flash * 0.9 }} />
    </AbsoluteFill>
  );
}

const FINDINGS = [
  { label: "FINDING", title: "Small inflamed bumps", detail: "Along the jaw · Moderate", dot: "#FFC062" },
  { label: "FINDING", title: "Post-blemish marks", detail: "Fading · Mild", dot: "#FFC062" },
  { label: "YOUR FOCUS", title: "Calm jawline breakouts", detail: "Then fade the marks they leave", dot: C.mint },
];

/** The report in plain words, then the real report in a phone. */
function Report({ manifest }: { manifest: Manifest }) {
  const f = useCurrentFrame();
  const cardsOut = prog(f, b(20) - 6, b(20) + 6, inOut);
  const phoneIn = prog(f, b(20), b(20) + 18);
  const exitZoom = prog(f, b(24) - 7, b(24), (t) => t * t * t);
  return (
    <AbsoluteFill style={{ transform: `scale(${1 + exitZoom * 1.4})`, opacity: 1 - exitZoom * 0.9, filter: exitZoom ? `blur(${exitZoom * 24}px)` : undefined }}>
      <Img src={staticFile("model.jpg")} style={{ position: "absolute", width: W, height: H, filter: "blur(36px) brightness(.32) saturate(.6)", transform: "scale(1.2)" }} />
      <Aurora base="transparent" colors={["rgba(63,143,90,.28)", "rgba(243,230,202,.08)"]} />
      <Dust count={24} seed="rep" />
      <LightLeak at={b(14)} color="rgba(243,230,202,.35)" />
      <Range from={b(14)} to={b(20)}>
        <MaskText lines={["In plain words."]} at={b(14)} size={104} style={{ position: "absolute", top: 250, width: "100%" }} out={b(20) - 8} />
      </Range>
      <Range from={b(20)} to={b(24)}>
        <MaskText lines={["Your full report,", { text: "explained.", color: C.mint }]} at={b(20)} size={92} style={{ position: "absolute", top: 230, width: "100%" }} />
      </Range>
      <Float amount={0.5} seed="cards">
        {FINDINGS.map((c, i) => (
          <div key={c.title} style={{ position: "absolute", left: 70, right: 70, top: 470 + i * 300, transform: `translateX(${cardsOut * (i % 2 ? 1 : -1) * 1200}px)`, filter: cardsOut ? `blur(${cardsOut * 14}px)` : undefined }}>
            <Pop at={b(15 + i * 1.5)} from={0.8} fly={700}>
              <Glass style={{ padding: "40px 48px" }}>
                <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
                  <div style={{ width: 16, height: 16, borderRadius: 8, background: c.dot, boxShadow: `0 0 20px ${c.dot}` }} />
                  <div style={{ fontSize: 26, fontWeight: 600, letterSpacing: "0.2em", color: c.dot }}>{c.label}</div>
                </div>
                <div style={{ fontSize: 62, fontWeight: 700, color: "#fff", letterSpacing: "-0.03em", marginTop: 14 }}>{c.title}</div>
                <div style={{ fontSize: 38, fontWeight: 500, color: "rgba(255,255,255,.7)", marginTop: 8 }}>{c.detail}</div>
              </Glass>
            </Pop>
          </div>
        ))}
      </Float>
      {phoneIn > 0 ? (
        <AbsoluteFill style={{ perspective: 1800 }}>
          <div style={{ position: "absolute", left: 540 - 250, top: 500 + (1 - phoneIn) * 1100 }}>
            <Phone3D width={500} rx={8} ry={12 - 18 * prog(f, b(20), b(24), inOut)} glow="rgba(124,196,149,.45)">
              <Rec flow="report" manifest={manifest} at={b(20)} speed={2.2} from={20} />
            </Phone3D>
          </div>
        </AbsoluteFill>
      ) : null}
      <Note text="Example report · demo scan" style={{ position: "absolute", top: 1450, width: "100%", textAlign: "center", fontSize: 22 }} />
    </AbsoluteFill>
  );
}
