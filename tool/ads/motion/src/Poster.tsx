// The Instagram launch post, 1080×1350 (the feed's portrait size). A real
// hand holding a real phone with the app's score report on it (screen_comp
// plate "poster"), on the app's charcoal, under an editorial headline.
// "PosterLive" adds Google's badge, for when the Play listing is live.

import { AbsoluteFill, Img, staticFile } from "remotion";
import { C, FONT, Grain } from "./kit";

export const POSTER_W = 1080;
export const POSTER_H = 1350;

export function Poster({ live = false }: { live?: boolean }) {
  // the photo's own edge colour, so the band above it is seamless
  return (
    <AbsoluteFill style={{ background: "#20201D", overflow: "hidden", fontFamily: FONT }}>
      {/* edge to edge: the hand comes in from the frame's own edge */}
      <Img src={staticFile("poster/phone.png")} style={{ position: "absolute", left: 0, top: 40, width: 1080, height: 1920 }} />
      {/* over the photo too, a lamp over the headline: warm, barely there */}
      <AbsoluteFill style={{ background: "radial-gradient(ellipse 70% 45% at 22% 12%, rgba(243,230,202,.09), transparent 70%)" }} />

      <div style={{ position: "absolute", left: 84, top: 84, display: "flex", alignItems: "center", gap: 14 }}>
        <Img src={staticFile("brand/crescent-cream.svg")} style={{ width: 46, height: 46 }} />
        <span style={{ fontSize: 34, fontWeight: 300, color: C.cream, letterSpacing: "-0.03em" }}>clearskin</span>
      </div>

      <div style={{ position: "absolute", left: 80, top: 176, fontSize: 132, fontWeight: 300, lineHeight: 0.98, letterSpacing: "-0.05em", color: C.cream }}>
        Your skin,
        <br />
        <span style={{ color: C.mint }}>measured.</span>
      </div>

      <div style={{ position: "absolute", left: 84, top: 448, fontSize: 30, fontWeight: 400, lineHeight: 1.38, color: "rgba(243,230,202,.78)", letterSpacing: "-0.01em" }}>
        One scan of your face, from every side.
        <br />
        Nine readings in plain words, and a routine built from them.
      </div>
      {live ? (
        <Img src={staticFile("brand/google-play-badge.png")} style={{ position: "absolute", right: 58, top: 56, width: 232, height: 90 }} />
      ) : null}
      <Grain opacity={0.035} />
    </AbsoluteFill>
  );
}

export const PosterLive = () => <Poster live />;

/** Profile picture: the C·skin mark, cream on charcoal, inside the circle Instagram crops to. */
export function Avatar() {
  return (
    <AbsoluteFill style={{ background: "#1E1E1C", alignItems: "center", justifyContent: "center" }}>
      {/* the mark's crescent, and "skin" set live in the brand font at the
          mark's own position (an <img> SVG can't use web fonts) */}
      <div style={{ position: "relative", width: 640, height: 640 }}>
        <Img src={staticFile("brand/crescent-cream.svg")} style={{ position: "absolute", inset: 0, width: 640, height: 640 }} />
        <div style={{ position: "absolute", left: (583.7 / 1024) * 640, top: 320, transform: "translate(-50%, -50%)", fontFamily: FONT, fontSize: (344 / 1024) * 640, fontWeight: 400, color: C.cream, lineHeight: 1 }}>skin</div>
      </div>
    </AbsoluteFill>
  );
}

/** A highlight cover: the app's tick ring, one word. */
export function Highlight({ word = "Scan", lit = 46 }: { word?: string; lit?: number }) {
  const n = 60;
  const r = 400;
  return (
    <AbsoluteFill style={{ background: "#1E1E1C", alignItems: "center", justifyContent: "center", fontFamily: FONT }}>
      <svg width={1080} height={1080} style={{ position: "absolute" }}>
        {Array.from({ length: n }, (_, i) => {
          const a = (i / n) * Math.PI * 2 - Math.PI / 2;
          const major = i % 5 === 0;
          const len = major ? 46 : 28;
          return (
            <line
              key={i}
              x1={540 + Math.cos(a) * r}
              y1={540 + Math.sin(a) * r}
              x2={540 + Math.cos(a) * (r - len)}
              y2={540 + Math.sin(a) * (r - len)}
              stroke={i < lit ? C.cream : "rgba(243,230,202,.18)"}
              strokeWidth={major ? 9 : 6}
              strokeLinecap="round"
            />
          );
        })}
      </svg>
      <div style={{ fontSize: 120, fontWeight: 300, letterSpacing: "-0.04em", color: C.cream }}>{word}</div>
    </AbsoluteFill>
  );
}
