// Ad 10 — "Is your routine even working?" Skin changes too slowly to see
// day to day, so people give up; ClearSkin tracks it. The week 2/6/12
// timeline is the app's own copy ("typical with daily use"); the chart is
// labelled sample data. 92 BPM.

import { AbsoluteFill, Img, staticFile, useCurrentFrame } from "remotion";
import { beatsAt, C, FONT, Grain, inOut, Note, prog } from "./kit";
import { Aurora, Dust, Finale, Float, Glass, LightLeak, MaskText, Odometer, Pop, Range, Scene, Shake, Slam, Vignette } from "./premium";
import spec from "./sound/Working.json";

const b = beatsAt(spec.bpm);
export const WORKING_FRAMES = b(spec.beats) + 18;

const NIGHT = "#08090B";

export function Working() {
  const f = useCurrentFrame();
  return (
    <AbsoluteFill style={{ background: NIGHT }}>
      <Shake at={[b(12)]}>
        <Scene from={0} to={b(4)} enter="cut">
          <Aurora base={NIGHT} colors={["rgba(227,174,85,.18)", "rgba(120,130,160,.12)"]} />
          <Dust count={24} seed="hook" />
          <MaskText lines={["Is your routine", { text: "even working?", color: C.amber }]} at={2} every={6} size={118} style={{ position: "absolute", top: 330, width: "100%" }} />
          <FlatChart />
          <Vignette />
        </Scene>

        <Range from={b(4)} to={b(12)}>
          <SameFace />
        </Range>

        <Range from={b(12)} to={b(20)}>
          <Tracking />
        </Range>
      </Shake>

      <Scene from={b(20)} to={b(26)} bg={NIGHT}>
        <Aurora base={NIGHT} colors={["rgba(63,143,90,.32)", "rgba(243,230,202,.10)"]} />
        <Dust count={22} seed="tl" />
        <MaskText lines={["What to expect"]} at={b(20)} size={92} style={{ position: "absolute", top: 300, width: "100%" }} />
        {[
          ["Week 2", "Your routine becomes a habit"],
          ["Week 6", "Fewer new breakouts"],
          ["Week 12", "Clearer skin, marks fading"],
        ].map(([w, text], i) => (
          <div key={w} style={{ position: "absolute", top: 520 + i * 250, left: 80, right: 80 }}>
            <Pop at={b(20.5 + i)} from={0.85} fly={500}>
              <Glass style={{ display: "flex", alignItems: "center", gap: 40, padding: "40px 48px" }}>
                <div style={{ fontSize: 40, fontWeight: 700, color: C.mint, width: 200, letterSpacing: "-0.01em" }}>{w}</div>
                <div style={{ fontSize: 46, fontWeight: 600, color: C.cream, letterSpacing: "-0.02em", lineHeight: 1.15 }}>{text}</div>
              </Glass>
            </Pop>
          </div>
        ))}
        <Note text="Typical with daily use" style={{ position: "absolute", top: 1300, width: "100%", textAlign: "center", fontSize: 24, opacity: prog(f, b(23), b(23) + 12) * 0.65 }} />
      </Scene>

      <Scene from={b(26)} to={WORKING_FRAMES} bg="#07090A" exit="cut" push={0.03}>
        <Aurora base="#07090A" colors={["rgba(63,143,90,.30)", "rgba(243,230,202,.10)"]} />
        <Dust count={24} seed="end" />
        <Finale at={b(26)} tagline="See your progress." theme="dark" glow="rgba(124,196,149,.8)" />
      </Scene>
      <Grain opacity={0.06} />
    </AbsoluteFill>
  );
}

/** A jittery line that goes nowhere: what guessing looks like. */
function FlatChart() {
  const f = useCurrentFrame();
  const draw = prog(f, 6, b(3.5), inOut);
  const pts = Array.from({ length: 41 }, (_, i) => {
    const x = 90 + (i / 40) * 900;
    const y = 1150 + Math.sin(i * 1.7) * 40 + Math.sin(i * 0.6 + 1) * 55 + Math.cos(i * 3.1) * 22;
    return [x, y] as const;
  });
  const n = Math.max(2, Math.floor(draw * pts.length));
  const d = pts.slice(0, n).map(([x, y], i) => `${i ? "L" : "M"}${x},${y}`).join(" ");
  const [hx, hy] = pts[n - 1];
  return (
    <svg width={1080} height={1920} style={{ position: "absolute" }}>
      {[0, 1, 2, 3].map((k) => (
        <line key={k} x1={90} x2={990} y1={950 + k * 130} y2={950 + k * 130} stroke="rgba(255,255,255,.08)" strokeWidth={2} />
      ))}
      <path d={d} fill="none" stroke={C.amber} strokeWidth={7} strokeLinejoin="round" strokeLinecap="round" style={{ filter: "drop-shadow(0 0 14px rgba(227,174,85,.7))" }} />
      <circle cx={hx} cy={hy} r={14} fill={C.amber} style={{ filter: "drop-shadow(0 0 18px rgba(227,174,85,.9))" }} />
      <text x={540} y={1470} textAnchor="middle" fontFamily={FONT} fontSize={44} fontWeight={600} fill="rgba(243,230,202,.6)" opacity={prog(f, b(2), b(2.6))}>
        Better? Worse? Same?
      </text>
    </svg>
  );
}

/** Three identical days: you can't see change day to day. */
function SameFace() {
  const f = useCurrentFrame();
  const fall = prog(f, b(10), b(10) + 14, (t) => t * t);
  const exitZoom = prog(f, b(12) - 6, b(12), (t) => t * t * t);
  const days = ["Mon", "Tue", "Wed"];
  return (
    <AbsoluteFill style={{ opacity: 1 - exitZoom, filter: exitZoom ? `blur(${exitZoom * 20}px)` : undefined }}>
      <Aurora base={NIGHT} colors={["rgba(120,130,160,.16)", "rgba(227,174,85,.10)"]} />
      <Dust count={24} seed="days" />
      <Range from={b(4)} to={b(8)}>
        <MaskText lines={["Day to day,", { text: "you can't see it.", color: C.amber }]} at={b(4)} size={108} style={{ position: "absolute", top: 260, width: "100%" }} out={b(8) - 9} />
      </Range>
      <Range from={b(8)} to={b(12)}>
        <MaskText lines={["So it's easy", { text: "to give up.", color: C.amber }]} at={b(8)} size={108} style={{ position: "absolute", top: 260, width: "100%" }} />
      </Range>
      <Float amount={0.8} seed="cards">
        {days.map((d, i) => {
          const at = b(4.5 + i);
          const x = 540 + (i - 1) * 300;
          const rot = (i - 1) * 7;
          return (
            <div key={d} style={{ position: "absolute", left: x - 190, top: 640 + fall * (900 + i * 120), transform: `rotate(${rot + fall * (i - 1) * 25}deg)`, filter: fall ? `blur(${fall * 10}px)` : undefined, zIndex: i === 1 ? 2 : 1 }}>
              <Pop at={at} from={0.7} fly={700}>
                <div style={{ width: 380, padding: 16, paddingBottom: 70, background: "#F6F2EA", borderRadius: 18, boxShadow: "0 40px 80px -20px rgba(0,0,0,.8)" }}>
                  <div style={{ width: 348, height: 460, overflow: "hidden", borderRadius: 8 }}>
                    <Img src={staticFile("model.jpg")} style={{ width: 348 * 1.5, transform: "translate(-87px, -230px)" }} />
                  </div>
                  <div style={{ fontFamily: FONT, fontSize: 40, fontWeight: 700, color: C.ink, marginTop: 14, textAlign: "center" }}>{d}</div>
                </div>
              </Pop>
            </div>
          );
        })}
      </Float>
      <Note text="Demo photos" style={{ position: "absolute", top: 1420, width: "100%", textAlign: "center", fontSize: 22, opacity: 0.5 * (1 - fall) }} />
      <Vignette />
    </AbsoluteFill>
  );
}

/** The drop: a weekly trend draws itself as each scan lands. */
function Tracking() {
  const f = useCurrentFrame();
  const draw = prog(f, b(13), b(18.5), inOut);
  const vals = [61, 63, 62, 66, 68, 67, 71, 73, 75];
  const x0 = 70;
  const x1 = 870;
  const y = (v: number) => 1260 - (v - 55) * 22;
  const pts = vals.map((v, i) => [x0 + (i / (vals.length - 1)) * (x1 - x0), y(v)] as const);
  const upto = draw * (pts.length - 1);
  const k = Math.floor(upto);
  const fr = upto - k;
  const head = k < pts.length - 1 ? [pts[k][0] + (pts[k + 1][0] - pts[k][0]) * fr, pts[k][1] + (pts[k + 1][1] - pts[k][1]) * fr] : pts[pts.length - 1];
  const line = [...pts.slice(0, k + 1), head].map(([px, py], i) => `${i ? "L" : "M"}${px},${py}`).join(" ");
  const area = `${line} L${head[0]},1300 L${x0},1300 Z`;
  const exitZoom = prog(f, b(20) - 7, b(20), (t) => t * t * t);
  return (
    <AbsoluteFill style={{ transform: `scale(${1 + exitZoom * 1.4})`, opacity: 1 - exitZoom * 0.9, filter: exitZoom ? `blur(${exitZoom * 24}px)` : undefined }}>
      <Aurora base={NIGHT} colors={["rgba(63,143,90,.42)", "rgba(124,196,149,.20)", "rgba(243,230,202,.10)"]} />
      <Dust count={30} seed="trk" />
      <LightLeak at={b(12)} color="rgba(124,196,149,.6)" />
      <Slam text="ClearSkin" at={b(12)} size={120} split={false} style={{ position: "absolute", top: 230, width: "100%" }} />
      <MaskText lines={[{ text: "tracks it for you.", color: C.mint }]} at={b(12.5)} size={92} style={{ position: "absolute", top: 370, width: "100%" }} />
      <Float amount={0.5} seed="chart">
        <div style={{ position: "absolute", left: 50, right: 50, top: 560 }}>
          <Pop at={b(12.3)} from={0.85} fly={800}>
            <Glass style={{ height: 820, padding: 0 }}>
              <div style={{ position: "absolute", left: 50, top: 46 }}>
                <div style={{ fontSize: 28, fontWeight: 600, letterSpacing: "0.2em", color: "rgba(243,230,202,.6)" }}>RADIANCE</div>
                <div style={{ display: "flex", alignItems: "flex-end", gap: 22, marginTop: 6 }}>
                  <Odometer from={61} to={75} a={b(13)} b={b(18.5)} size={150} />
                  <div style={{ fontSize: 40, fontWeight: 600, color: C.mint, marginBottom: 22, opacity: prog(f, b(18.5), b(19)) }}>+14</div>
                </div>
              </div>
              <svg width={980} height={820} style={{ position: "absolute", left: 0, top: 0 }} viewBox="0 560 980 820">
                <defs>
                  <linearGradient id="area" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0" stopColor="rgba(124,196,149,.45)" />
                    <stop offset="1" stopColor="rgba(124,196,149,0)" />
                  </linearGradient>
                </defs>
                {[0, 1, 2].map((g) => (
                  <line key={g} x1={x0} x2={x1 + 40} y1={y(60 + g * 7)} y2={y(60 + g * 7)} stroke="rgba(255,255,255,.07)" strokeWidth={2} />
                ))}
                <path d={area} fill="url(#area)" />
                <path d={line} fill="none" stroke={C.mint} strokeWidth={8} strokeLinecap="round" strokeLinejoin="round" style={{ filter: "drop-shadow(0 0 16px rgba(124,196,149,.8))" }} />
                {pts.map(([px, py], i) => (i <= upto ? <circle key={i} cx={px} cy={py} r={i === pts.length - 1 ? 16 : 9} fill={i === pts.length - 1 ? C.cream : C.mint} opacity={0.95} /> : null))}
                <circle cx={head[0]} cy={head[1]} r={20} fill={C.cream} style={{ filter: "drop-shadow(0 0 22px rgba(243,230,202,.9))" }} />
                <text x={x0} y={1340} fontFamily={FONT} fontSize={30} fill="rgba(243,230,202,.5)">Sep 19</text>
                <text x={x1} y={1340} fontFamily={FONT} fontSize={30} fill="rgba(243,230,202,.5)" textAnchor="end">Oct 24</text>
              </svg>
            </Glass>
          </Pop>
        </div>
      </Float>
      <Note text="Sample data · weekly scans" style={{ position: "absolute", top: 1430, width: "100%", textAlign: "center", fontSize: 22 }} />
    </AbsoluteFill>
  );
}
