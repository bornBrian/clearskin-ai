// Instagram post, editorial: a real face (Mixkit, released) whose skin peels
// back along the nose to show what ClearSkin sees: the app's contour mesh,
// tracked on that face (track/scan.json, frame FACE_FRAME). A huge vertical
// "MEASURED" behind her, and the real hand-held phone with the score.
// The peel never shows "worse" skin: one side is her skin, the other the scan.

import type { CSSProperties } from "react";
import { AbsoluteFill, Img, staticFile } from "remotion";
import { C, FONT, Grain, useJson } from "./kit";

const PW = 1080;
const PH = 1350;
const FACE_FRAME = 65; // scan.mp4 frame of face.png
const S = 0.66; // face image scale (source 1080×1920)
const FX = PW - 1080 * S; // right-aligned: she bleeds off the right edge
const FY = PH - 1920 * S; // and off the bottom edge
const INK = "#1D1F1C";

interface Track {
  tris: [number, number, number][];
  frames: ([number, number][] | null)[];
}

const faceStyle: CSSProperties = { position: "absolute", left: FX, top: FY, width: 1080 * S, height: 1920 * S };

export function PosterPeel() {
  const track = useJson<Track>("track/scan.json");
  if (!track) return null;
  const pts = (track.frames[FACE_FRAME] ?? []).map(([x, y]) => [FX + x * 1080 * S, FY + y * 1920 * S] as const);
  const cx = pts.reduce((s, p) => s + p[0], 0) / pts.length;
  // the peel line, along the nose, leaning slightly
  const top = cx + 70;
  const bot = cx - 150;
  const at = (y: number) => top + (bot - top) * (y / PH);
  const scanSide = `polygon(0 0, ${top}px 0, ${bot}px ${PH}px, 0 ${PH}px)`;
  const edges = new Map<string, [number, number]>();
  for (const [p, q, r] of track.tris) for (const [u, v] of [[p, q], [q, r], [r, p]]) edges.set(u < v ? `${u}-${v}` : `${v}-${u}`, [u, v]);
  // the flap: her skin, curling back off the scan from the peel line
  const ay = FY + 1920 * S * 0.5;
  const by = PH;
  const A = [at(ay), ay];
  const B = [at(by), by];
  const Cc = [at(ay) - 230, ay + 330];

  return (
    <AbsoluteFill style={{ fontFamily: FONT, overflow: "hidden", background: "linear-gradient(162deg, #F5F0E6 0%, #EDEFE6 45%, #D9E4D5 100%)" }}>
      {/* soft light behind her */}
      <AbsoluteFill style={{ background: "radial-gradient(ellipse 60% 50% at 62% 34%, rgba(255,255,255,.75), transparent 70%)" }} />

      {/* MEASURED, huge and vertical, behind her */}
      <div
        style={{
          position: "absolute",
          left: 140,
          top: 455,
          transform: "translate(-50%, -50%) rotate(-90deg)",
          fontSize: 150,
          fontWeight: 200,
          letterSpacing: "0.02em",
          lineHeight: 1,
          whiteSpace: "nowrap",
          backgroundImage: "linear-gradient(90deg, #9DB8A2, #3F8F5A 60%, #2F6E46)",
          WebkitBackgroundClip: "text",
          backgroundClip: "text",
          color: "transparent",
        }}
      >
        MEASURED
      </div>

      {/* her, as she is */}
      <Img src={staticFile("poster/face_cut.png")} style={faceStyle} />

      {/* the scan side: what ClearSkin sees */}
      <div style={{ position: "absolute", inset: 0, clipPath: scanSide, WebkitClipPath: scanSide }}>
        <Img src={staticFile("poster/face_cut.png")} style={{ ...faceStyle, filter: "grayscale(1) contrast(1.08) brightness(.82)" }} />
        <AbsoluteFill style={{ background: "rgba(30,48,38,.38)", mixBlendMode: "multiply", WebkitMaskImage: `url(${staticFile("poster/face_cut.png")})`, maskImage: `url(${staticFile("poster/face_cut.png")})`, WebkitMaskSize: `${1080 * S}px ${1920 * S}px`, maskSize: `${1080 * S}px ${1920 * S}px`, WebkitMaskPosition: `${FX}px ${FY}px`, maskPosition: `${FX}px ${FY}px`, WebkitMaskRepeat: "no-repeat", maskRepeat: "no-repeat" }} />
        <svg width={PW} height={PH} style={{ position: "absolute", inset: 0 }}>
          {[...edges.values()].map(([p, q]) => (
            <line key={`${p}-${q}`} x1={pts[p][0]} y1={pts[p][1]} x2={pts[q][0]} y2={pts[q][1]} stroke={C.cream} strokeWidth={1.8} strokeOpacity={0.7} />
          ))}
          {pts.map(([x, y], i) => (
            <circle key={i} cx={x} cy={y} r={3.4} fill={C.cream} />
          ))}
        </svg>
      </div>

      {/* the peel's edge, lit */}
      <svg width={PW} height={PH} style={{ position: "absolute", inset: 0 }}>
        <defs>
          <linearGradient id="flap" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stopColor="#FFFFFF" />
            <stop offset="0.55" stopColor="#ECEAE4" />
            <stop offset="1" stopColor="#C9C6BE" />
          </linearGradient>
          <filter id="lift" x="-30%" y="-30%" width="160%" height="160%">
            <feDropShadow dx="-14" dy="18" stdDeviation="18" floodColor="#1D1F1C" floodOpacity="0.35" />
          </filter>
        </defs>
        <line x1={top} y1={0} x2={A[0]} y2={A[1]} stroke="rgba(255,255,255,.85)" strokeWidth={3} />
        <path d={`M${A[0]},${A[1]} Q${Cc[0] + 90},${(A[1] + Cc[1]) / 2 - 40} ${Cc[0]},${Cc[1]} Q${(Cc[0] + B[0]) / 2 - 10},${Cc[1] + 70} ${B[0]},${B[1]} Z`} fill="url(#flap)" filter="url(#lift)" />
      </svg>

      {/* the real phone, the score on it */}
      <Img src={staticFile("poster/phone_cut.png")} style={{ position: "absolute", left: -40, top: 870, width: 470, height: (470 * 1380) / 853, transform: "rotate(-7deg)", transformOrigin: "0% 100%", filter: "drop-shadow(0 30px 40px rgba(29,31,28,.35))" }} />

      {/* lockup and line */}
      <div style={{ position: "absolute", right: 64, top: 64, display: "flex", alignItems: "center", gap: 12 }}>
        <Img src={staticFile("brand/crescent-ink.svg")} style={{ width: 42, height: 42 }} />
        <span style={{ fontSize: 32, fontWeight: 300, color: INK, letterSpacing: "-0.03em" }}>clearskin</span>
      </div>
      <div style={{ position: "absolute", right: 64, bottom: 78, textAlign: "right", color: INK }}>
        <div style={{ fontSize: 40, fontWeight: 400, letterSpacing: "-0.03em", lineHeight: 1.12 }}>
          See what your skin
          <br />
          is telling you.
        </div>
        <div style={{ marginTop: 14, fontSize: 22, fontWeight: 600, letterSpacing: "0.16em", color: "rgba(29,31,28,.55)" }}>ONE SCAN · NINE READINGS</div>
      </div>
      <Grain opacity={0.03} />
    </AbsoluteFill>
  );
}
