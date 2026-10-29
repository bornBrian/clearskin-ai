// Ad 09 — "Your products might be fighting." The shelf clash checker. The
// pairs and verdicts are the app's own rules (lib/domain/ingredients/
// conflict_checker.dart), including the myth it busts. 110 BPM.

import { AbsoluteFill, useCurrentFrame } from "remotion";
import { beatsAt, C, FONT, Grain, inOut, type Manifest, prog, Rec, useJson } from "./kit";
import { Aurora, Dust, Finale, Float, Glass, LightLeak, MaskText, Phone3D, Pop, Range, Scene, Shake, Vignette } from "./premium";
import spec from "./sound/Clash.json";

const b = beatsAt(spec.bpm);
export const CLASH_FRAMES = b(spec.beats) + 18;

const RED = "#FF6B5E";
const AMBER = "#FFC062";
const GREEN = C.mint;

const PAIRS = [
  { pair: ["Retinol", "+ AHA"], verdict: "Not together.", why: "Redness and peeling. Alternate nights.", color: RED },
  { pair: ["Benzoyl peroxide", "+ Vitamin C"], verdict: "Split AM / PM.", why: "It can oxidise the vitamin C.", color: AMBER },
  { pair: ["Niacinamide", "+ Vitamin C"], verdict: "Totally fine.", why: "An old myth. Use them together.", color: GREEN },
  { pair: ["Two retinoids"], verdict: "Pick one.", why: "More irritation, not more results.", color: RED },
];

export function Clash() {
  const manifest = useJson<Manifest>("manifest.json");
  if (!manifest) return null;
  return (
    <AbsoluteFill style={{ background: "#0B0B0D" }}>
      <Shake at={[b(2), b(14)]} power={28}>
        <Scene from={0} to={b(4)} enter="cut" exit="zoom">
          <Collision />
        </Scene>

        <Range from={b(4)} to={b(12)}>
          <Pairs />
        </Range>

        <Scene from={b(12)} to={b(14)} bg="#0B0B0D" exit="cut">
          <Aurora base="#0B0B0D" colors={["rgba(255,107,94,.18)", "rgba(255,192,98,.12)"]} />
          <MaskText lines={["Hard to keep", "track of?"]} at={b(12)} size={128} style={{ position: "absolute", top: 700, width: "100%" }} />
        </Scene>

        <Range from={b(14)} to={b(24)}>
          <Solution manifest={manifest} />
        </Range>
      </Shake>

      <Scene from={b(24)} to={b(28)} bg={C.paper}>
        <Aurora base={C.paper} colors={["rgba(176,214,186,.85)", "rgba(243,230,202,1)", "rgba(255,214,190,.7)"]} />
        <MaskText lines={["Know what", { text: "works together.", color: C.leaf }]} at={b(24)} size={128} weight={800} color={C.ink} style={{ position: "absolute", top: 720, width: "100%" }} />
      </Scene>

      <Scene from={b(28)} to={CLASH_FRAMES} bg="#08090A" exit="cut" push={0.03}>
        <Aurora base="#08090A" colors={["rgba(63,143,90,.28)", "rgba(243,230,202,.10)"]} />
        <Dust count={24} seed="end" />
        <Finale at={b(28)} tagline="Your shelf, checked." theme="dark" glow="rgba(124,196,149,.8)" />
      </Scene>
      <Grain opacity={0.06} />
    </AbsoluteFill>
  );
}

/** Two ingredients race in from the sides and crash on the beat. */
function Collision() {
  const f = useCurrentFrame();
  const hit = b(2);
  const t = Math.min(1, f / hit);
  const ease = t * t;
  const after = Math.max(0, f - hit);
  const recoil = after ? Math.exp(-after / 6) * Math.sin(after / 2) * 50 : 0;
  const speed = f < hit ? 3 * t * t : 0;
  const word = (text: string, side: -1 | 1) => {
    const x = side * (1 - ease) * 340 + side * (16 + Math.max(0, recoil * side));
    return (
      <div
        style={{
          position: "absolute",
          top: 560,
          left: 540 + x + (side < 0 ? -640 : 0),
          width: 640,
          display: "flex",
          justifyContent: side < 0 ? "flex-end" : "flex-start",
          filter: speed > 0.2 ? `blur(${speed * 10}px)` : undefined,
          transform: `skewX(${side * -speed * 8}deg)`,
        }}
      >
        <Glass style={{ padding: "26px 40px", borderRadius: 999 }} tint={after ? "rgba(255,107,94,.22)" : "rgba(255,255,255,.10)"}>
          <span style={{ fontSize: 60, fontWeight: 800, color: "#fff", letterSpacing: "-0.03em", whiteSpace: "nowrap" }}>{text}</span>
        </Glass>
      </div>
    );
  };
  const flash = after ? Math.exp(-after / 5) : 0;
  return (
    <AbsoluteFill>
      <Aurora base="#0B0B0D" colors={[`rgba(255,107,94,${0.12 + 0.3 * flash})`, "rgba(120,120,140,.12)"]} />
      <Dust count={30} seed="clash" />
      <div style={{ position: "absolute", top: 430, width: "100%", textAlign: "center", fontFamily: FONT, fontSize: 30, fontWeight: 600, letterSpacing: "0.3em", color: "rgba(255,255,255,.55)" }}>
        IN THE SAME ROUTINE?
      </div>
      {word("Retinol", -1)}
      {word("Glycolic acid", 1)}
      {after ? (
        <div style={{ position: "absolute", left: 540 - 300 * (1 + after / 8), top: 610 - 300 * (1 + after / 8), width: 600 * (1 + after / 8), height: 600 * (1 + after / 8), borderRadius: "50%", border: `6px solid rgba(255,107,94,${flash})`, boxShadow: `0 0 80px rgba(255,107,94,${flash})` }} />
      ) : null}
      <AbsoluteFill style={{ background: RED, opacity: flash * 0.35, mixBlendMode: "screen" }} />
      <MaskText lines={["Your products", { text: "might be fighting.", color: RED }]} at={hit + 6} every={6} size={112} style={{ position: "absolute", top: 820, width: "100%" }} />
      <Vignette strength={0.7} />
    </AbsoluteFill>
  );
}

/** Four pairs, a verdict on every other beat, cards flying through depth. */
function Pairs() {
  const f = useCurrentFrame();
  const i = Math.min(3, Math.floor((f - b(4)) / b(2)));
  const p = PAIRS[i];
  const start = b(4 + i * 2);
  const verdictAt = b(5 + i * 2);
  const leave = prog(f, b(6 + i * 2) - 6, b(6 + i * 2), (t) => t * t);
  const v = prog(f, verdictAt, verdictAt + 8);
  return (
    <AbsoluteFill>
      <Aurora base="#0B0B0D" colors={[`${p.color}33`, "rgba(120,120,140,.10)", `${p.color}1f`]} />
      <Dust count={24} seed={`p${i}`} />
      <div style={{ position: "absolute", top: 250, width: "100%", textAlign: "center", fontFamily: FONT, fontSize: 30, fontWeight: 600, letterSpacing: "0.3em", color: "rgba(255,255,255,.55)" }}>
        IN THE SAME ROUTINE?
      </div>
      <Float amount={0.6} seed={`f${i}`}>
        <div style={{ position: "absolute", top: 520, left: 90, right: 90, transform: `translateX(${-leave * 1300}px) rotate(${-leave * 8}deg)`, filter: leave ? `blur(${leave * 18}px)` : undefined }}>
          <Pop at={start} fly={900} from={0.7}>
            <Glass style={{ padding: "64px 56px", textAlign: "center" }}>
              {p.pair.map((line, k) => (
                <div key={k} style={{ fontSize: k === 0 ? 96 : 84, fontWeight: 800, color: "#fff", letterSpacing: "-0.04em", lineHeight: 1.08, opacity: k === 0 ? 1 : 0.8 }}>
                  {line}
                </div>
              ))}
              <div style={{ height: 2, background: "rgba(255,255,255,.14)", margin: "44px 0 40px" }} />
              <div style={{ transform: `scale(${0.8 + 0.2 * v})`, opacity: v, filter: v < 1 ? `blur(${(1 - v) * 10}px)` : undefined }}>
                <div style={{ display: "inline-block", padding: "16px 40px", borderRadius: 999, background: `${p.color}26`, border: `2px solid ${p.color}`, color: p.color, fontSize: 70, fontWeight: 800, letterSpacing: "-0.03em", boxShadow: `0 0 60px -10px ${p.color}` }}>
                  {p.verdict}
                </div>
                <div style={{ marginTop: 30, fontSize: 40, fontWeight: 500, color: "rgba(255,255,255,.78)" }}>{p.why}</div>
              </div>
            </Glass>
          </Pop>
        </div>
      </Float>
      <div style={{ position: "absolute", top: 1440, width: "100%", display: "flex", justifyContent: "center", gap: 18 }}>
        {PAIRS.map((_, k) => (
          <div key={k} style={{ width: k === i ? 56 : 16, height: 16, borderRadius: 8, background: k === i ? p.color : "rgba(255,255,255,.25)" }} />
        ))}
      </div>
      <Vignette />
    </AbsoluteFill>
  );
}

/** The phone checks the shelf; a warning card lifts out of it. */
function Solution({ manifest }: { manifest: Manifest }) {
  const f = useCurrentFrame();
  const enter = prog(f, b(14), b(14) + 20);
  const lift = prog(f, b(18), b(18) + 16);
  const ry = -14 + 22 * prog(f, b(14), b(24), inOut);
  const exitZoom = prog(f, b(24) - 7, b(24), (t) => t * t * t);
  return (
    <AbsoluteFill style={{ background: "#08090A", transform: `scale(${1 + exitZoom * 1.4})`, opacity: 1 - exitZoom * 0.9, filter: exitZoom ? `blur(${exitZoom * 24}px)` : undefined }}>
      <Aurora base="#08090A" colors={["rgba(63,143,90,.40)", "rgba(124,196,149,.18)", "rgba(243,230,202,.10)"]} />
      <Dust count={30} seed="sol" />
      <LightLeak at={b(14)} color="rgba(124,196,149,.55)" />
      <Float amount={0.6}>
        <AbsoluteFill style={{ perspective: 1800 }}>
          <div style={{ position: "absolute", left: 540 - 260, top: 560 + (1 - enter) * 1000, transformStyle: "preserve-3d" }}>
            <Phone3D width={520} ry={ry} rx={8} glow="rgba(124,196,149,.45)">
              <Rec flow="shelf" manifest={manifest} at={b(14.5)} speed={0.5} />
            </Phone3D>
          </div>
        </AbsoluteFill>
        {lift > 0 ? (
          <div style={{ position: "absolute", left: 70, right: 70, top: 1080 - lift * 110, transform: `perspective(1600px) translateZ(${lift * 140}px) rotateX(${(1 - lift) * 30}deg) scale(${0.7 + 0.3 * lift})`, opacity: lift }}>
            <Glass tint="rgba(30,18,16,.72)" style={{ padding: "40px 46px" }}>
              <div style={{ display: "flex", alignItems: "center", gap: 18, marginBottom: 18 }}>
                <div style={{ width: 18, height: 18, borderRadius: 9, background: RED, boxShadow: `0 0 24px ${RED}` }} />
                <div style={{ fontSize: 28, fontWeight: 600, letterSpacing: "0.2em", color: RED }}>CLASH</div>
              </div>
              <div style={{ fontSize: 46, fontWeight: 700, color: "#fff", letterSpacing: "-0.02em", lineHeight: 1.15 }}>Retinoid + exfoliating acid in the same routine</div>
              <div style={{ marginTop: 16, fontSize: 34, fontWeight: 400, color: "rgba(255,255,255,.75)", lineHeight: 1.35 }}>
                Together they often cause redness and peeling. Use them on alternate nights.
              </div>
            </Glass>
          </div>
        ) : null}
      </Float>
      <AbsoluteFill style={{ background: "linear-gradient(#08090A 0%, rgba(8,9,10,.85) 17%, transparent 30%)" }} />
      <Range from={b(14)} to={b(21)}>
        <MaskText lines={["ClearSkin checks", { text: "your shelf.", color: C.mint }]} at={b(14) + 3} size={96} style={{ position: "absolute", top: 220, width: "100%" }} out={b(21) - 9} />
      </Range>
      <Range from={b(21)} to={b(24)}>
        <MaskText lines={["And tells you", { text: "how to fix it.", color: C.mint }]} at={b(21)} size={96} style={{ position: "absolute", top: 220, width: "100%" }} />
      </Range>
    </AbsoluteFill>
  );
}
