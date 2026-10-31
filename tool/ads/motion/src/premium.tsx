// The premium layer: camera float and push, zoom-through transitions with
// real motion blur, masked type, a phone with depth and glass, light leaks,
// dust, glass cards and impact hits. Built on kit.tsx.

import { CameraMotionBlur } from "@remotion/motion-blur";
import { noise2D } from "@remotion/noise";
import type { CSSProperties, ReactNode } from "react";
import { AbsoluteFill, Img, interpolate, random, spring, staticFile, useCurrentFrame } from "remotion";
import { C, expoOut, FONT, FPS, H, inOut, prog, W } from "./kit";

export type Beats = (n: number) => number;

/** Shows [children] only for frames [from, to). */
export function Range({ from, to, children }: { from: number; to: number; children: ReactNode }) {
  const f = useCurrentFrame();
  return f >= from && f < to ? <>{children}</> : null;
}

/**
 * A scene between frames [from, to). It arrives out of a zoom (or slides
 * in), drifts towards the camera while on screen, and with exit "zoom"
 * rushes into the lens before the cut. Transitions get motion blur.
 */
export function Scene(props: {
  from: number;
  to: number;
  children: ReactNode;
  enter?: "zoom" | "rise" | "cut" | "left" | "right";
  exit?: "zoom" | "cut" | "fade";
  push?: number;
  bg?: string;
  blur?: boolean;
}) {
  const f = useCurrentFrame();
  const { from, to, enter = "zoom", exit = "zoom", push = 0.05 } = props;
  if (f < from || f >= to) return null;
  const ein = 11;
  const eout = 7;
  const a = enter === "cut" ? 1 : prog(f, from, from + ein);
  const z = exit === "zoom" ? prog(f, to - eout, to, Easing3) : 0;
  const fade = exit === "fade" ? prog(f, to - 8, to, inOut) : 0;
  const drift = 1 + push * prog(f, from, to, inOut);
  let transform = `scale(${drift})`;
  if (enter === "zoom") transform += ` scale(${0.82 + 0.18 * a})`;
  if (enter === "rise") transform += ` translateY(${(1 - a) * 260}px)`;
  if (enter === "left") transform += ` translateX(${(1 - a) * -1100}px)`;
  if (enter === "right") transform += ` translateX(${(1 - a) * 1100}px)`;
  if (z) transform += ` scale(${1 + z * 1.6})`;
  const blur = (enter === "cut" ? 0 : (1 - a) * 22) + z * 26;
  const content = (
    <AbsoluteFill style={{ background: props.bg, transform, filter: blur > 0.5 ? `blur(${blur}px)` : undefined, opacity: (enter === "cut" ? 1 : Math.min(1, a * 1.6)) * (1 - z * 0.85) * (1 - fade) }}>
      {props.children}
    </AbsoluteFill>
  );
  const moving = props.blur !== false && ((enter !== "cut" && f < from + ein) || (z > 0 && z < 1));
  return moving ? (
    <CameraMotionBlur shutterAngle={200} samples={6}>
      {content}
    </CameraMotionBlur>
  ) : (
    content
  );
}
const Easing3 = (t: number) => t * t * t;

/** Slow handheld float, so nothing is ever perfectly still. */
export function Float({ children, amount = 1, seed = "cam" }: { children: ReactNode; amount?: number; seed?: string }) {
  const f = useCurrentFrame();
  const x = noise2D(seed, f / 90, 0) * 10 * amount;
  const y = noise2D(seed, 0, f / 110) * 12 * amount;
  const r = noise2D(seed, f / 140, 5) * 0.5 * amount;
  return <AbsoluteFill style={{ transform: `translate(${x}px, ${y}px) rotate(${r}deg)` }}>{children}</AbsoluteFill>;
}

/** Camera shake that decays after each frame in [at]. */
export function Shake({ at, children, power = 22 }: { at: number[]; children: ReactNode; power?: number }) {
  const f = useCurrentFrame();
  let k = 0;
  for (const a of at) if (f >= a) k = Math.max(k, Math.exp(-(f - a) / 4) * (f - a < 18 ? 1 : 0));
  const x = noise2D("sx", f / 1.6, 0) * power * k;
  const y = noise2D("sy", 0, f / 1.6) * power * k;
  return <AbsoluteFill style={{ transform: `translate(${x}px, ${y}px) rotate(${x * 0.05}deg)` }}>{children}</AbsoluteFill>;
}

// ── Type ──────────────────────────────────────────────────────────────

/**
 * Lines that rise from behind a mask, one after another (the classic
 * keynote reveal). [lines] may tint words with {text, color}.
 */
export function MaskText(props: {
  lines: (string | { text: string; color?: string })[];
  at: number;
  every?: number;
  size: number;
  weight?: number;
  color?: string;
  align?: "center" | "left";
  style?: CSSProperties;
  out?: number;
  tracking?: number;
}) {
  const f = useCurrentFrame();
  const { at, every = 5, size, weight = 700, color = C.cream, align = "center", out, tracking = -0.04 } = props;
  return (
    <div style={{ fontFamily: FONT, fontSize: size, fontWeight: weight, color, letterSpacing: `${tracking}em`, lineHeight: 1.02, textAlign: align, ...props.style }}>
      {props.lines.map((l, i) => {
        const line = typeof l === "string" ? { text: l } : l;
        const s = spring({ frame: f - at - i * every, fps: FPS, config: { damping: 200, stiffness: 120, mass: 0.7 } });
        const o = out === undefined ? 0 : prog(f, out + i * 2, out + i * 2 + 9, inOut);
        return (
          <div key={i} style={{ overflow: "hidden", paddingBottom: "0.08em", marginBottom: "-0.08em" }}>
            <div style={{ transform: `translateY(${(1 - s) * 110 - o * 110}%)`, color: line.color, whiteSpace: "pre" }}>{line.text}</div>
          </div>
        );
      })}
    </div>
  );
}

/** A word that slams in: big, blurred, with a colour-split edge. */
export function Slam(props: { text: string; at: number; size: number; color?: string; weight?: number; style?: CSSProperties; split?: boolean }) {
  const f = useCurrentFrame();
  const t = prog(f, props.at, props.at + 6, expoOut);
  if (f < props.at) return null;
  const k = Math.exp(-(f - props.at) / 5);
  const sp = props.split === false ? 0 : 10 * k;
  return (
    <div
      style={{
        fontFamily: FONT,
        fontSize: props.size,
        fontWeight: props.weight ?? 800,
        color: props.color ?? C.cream,
        letterSpacing: "-0.045em",
        lineHeight: 1,
        textAlign: "center",
        transform: `scale(${1.55 - 0.55 * t})`,
        opacity: Math.min(1, t * 2),
        filter: `blur(${(1 - t) * 18}px)${sp > 0.4 ? ` drop-shadow(${sp}px 0 0 rgba(255,40,60,.75)) drop-shadow(${-sp}px 0 0 rgba(40,220,255,.75))` : ""}`,
        ...props.style,
      }}
    >
      {props.text}
    </div>
  );
}

/** A number that rolls like an odometer from [from] to [to]. */
export function Odometer({ from, to, a, b, size, color = C.cream, weight = 200 }: { from: number; to: number; a: number; b: number; size: number; color?: string; weight?: number }) {
  const f = useCurrentFrame();
  const v = interpolate(prog(f, a, b, inOut), [0, 1], [from, to]);
  const digits = String(Math.round(to)).length;
  return (
    <div style={{ display: "flex", fontFamily: FONT, fontSize: size, fontWeight: weight, color, letterSpacing: "-0.05em", lineHeight: 1, height: size, overflow: "hidden" }}>
      {Array.from({ length: digits }, (_, i) => {
        const place = 10 ** (digits - 1 - i);
        const d = (v / place) % 10;
        // whole digits snap, the last one glides
        const pos = i === digits - 1 ? d : Math.floor(d) + Math.max(0, (d % 1) - 0.85) / 0.15;
        return (
          <div key={i} style={{ height: size, overflow: "hidden" }}>
            <div style={{ transform: `translateY(${-pos * size}px)` }}>
              {Array.from({ length: 11 }, (_, n) => (
                <div key={n} style={{ height: size, textAlign: "center" }}>{n % 10}</div>
              ))}
            </div>
          </div>
        );
      })}
    </div>
  );
}

// ── Light and atmosphere ─────────────────────────────────────────────

/** Coloured light washing across the frame around frame [at]. */
export function LightLeak({ at, color = "rgba(255,190,120,.55)", len = 26, from = -0.3, to = 1.3, y = 0.4 }: { at: number; color?: string; len?: number; from?: number; to?: number; y?: number }) {
  const f = useCurrentFrame();
  if (f < at - 2 || f > at + len) return null;
  const t = prog(f, at, at + len, inOut);
  const o = Math.sin(Math.PI * t);
  const x = (from + (to - from) * t) * W;
  return (
    <AbsoluteFill style={{ mixBlendMode: "screen", opacity: o, pointerEvents: "none" }}>
      <div style={{ position: "absolute", left: x - 700, top: y * H - 900, width: 1400, height: 1800, borderRadius: "50%", background: `radial-gradient(ellipse, ${color}, transparent 65%)`, transform: "rotate(-20deg)" }} />
    </AbsoluteFill>
  );
}

/** Floating dust and bokeh at different depths. */
export function Dust({ count = 40, color = "255,255,255", seed = "d" }: { count?: number; color?: string; seed?: string }) {
  const f = useCurrentFrame();
  return (
    <AbsoluteFill style={{ pointerEvents: "none" }}>
      {Array.from({ length: count }, (_, i) => {
        const depth = random(`${seed}z${i}`);
        const r = 2 + depth * depth * 26;
        const x = (random(`${seed}x${i}`) * W + f * (0.3 + depth) * 0.6 + noise2D(seed, i, f / 120) * 40) % (W + 100) - 50;
        const y = (random(`${seed}y${i}`) * H - f * (0.4 + depth * 1.2)) % H;
        const yy = y < 0 ? y + H : y;
        return (
          <div
            key={i}
            style={{
              position: "absolute",
              left: x,
              top: yy,
              width: r,
              height: r,
              borderRadius: "50%",
              background: `rgba(${color},${0.5 - depth * 0.35})`,
              filter: `blur(${depth * depth * 9}px)`,
            }}
          />
        );
      })}
    </AbsoluteFill>
  );
}

/** A bright band that sweeps across its (clipped) parent once, from frame [at]. */
export function Sweep({ at, len = 22, color = "rgba(255,255,255,.55)", angle = 20 }: { at: number; len?: number; color?: string; angle?: number }) {
  const f = useCurrentFrame();
  if (f < at || f > at + len) return null;
  const t = prog(f, at, at + len, inOut);
  return (
    <div
      style={{
        position: "absolute",
        inset: "-50%",
        background: `linear-gradient(${90 + angle}deg, transparent ${30 + t * 60 - 12}%, ${color} ${30 + t * 60}%, transparent ${30 + t * 60 + 12}%)`,
        mixBlendMode: "overlay",
        pointerEvents: "none",
        transform: `translateX(${(t - 0.5) * 40}%)`,
      }}
    />
  );
}

export function Vignette({ strength = 0.55 }: { strength?: number }) {
  return <AbsoluteFill style={{ background: `radial-gradient(ellipse at 50% 45%, transparent 45%, rgba(0,0,0,${strength}))`, pointerEvents: "none" }} />;
}

/** Large soft colour fields that slowly move: a living gradient. */
export function Aurora({ colors, base }: { colors: string[]; base: string }) {
  const f = useCurrentFrame();
  return (
    <AbsoluteFill style={{ background: base, overflow: "hidden" }}>
      {colors.map((c, i) => {
        const x = 540 + noise2D(`ax${i}`, f / 160, i) * 520;
        const y = 960 + noise2D(`ay${i}`, i, f / 180) * 760;
        const r = 620 + i * 90;
        return <div key={i} style={{ position: "absolute", left: x - r, top: y - r, width: r * 2, height: r * 2, borderRadius: "50%", background: `radial-gradient(circle, ${c}, transparent 66%)` }} />;
      })}
    </AbsoluteFill>
  );
}

// ── Objects ──────────────────────────────────────────────────────────

/**
 * A phone with real depth: a stack of layers behind the glass makes the
 * edge visible when it turns; a highlight slides over the glass as it
 * moves; a soft shadow sits under it.
 */
export function Phone3D(props: {
  width: number;
  aspect?: number;
  rx?: number;
  ry?: number;
  rz?: number;
  children: ReactNode;
  glow?: string;
  style?: CSSProperties;
}) {
  const { width, aspect = 9 / 16, rx = 0, ry = 0, rz = 0 } = props;
  const bezel = width * 0.03;
  const h = width / aspect + bezel * 2;
  const radius = width * 0.14;
  const depth = 16;
  const glare = 50 + ry * 2.2 + rx * 1.2;
  return (
    <div style={{ position: "relative", width, height: h, transformStyle: "preserve-3d", transform: `rotateX(${rx}deg) rotateY(${ry}deg) rotateZ(${rz}deg)`, ...props.style }}>
      {Array.from({ length: depth }, (_, i) => (
        <div key={i} style={{ position: "absolute", inset: 0, borderRadius: radius, background: i === depth - 1 ? "#050506" : `rgb(${38 - i},${39 - i},${42 - i})`, transform: `translateZ(${-i - 1}px)` }} />
      ))}
      <div
        style={{
          position: "absolute",
          inset: 0,
          padding: bezel,
          borderRadius: radius,
          background: "linear-gradient(145deg, #3a3b3e, #0b0b0c 38%, #232427)",
          boxShadow: `0 0 0 1.5px rgba(255,255,255,.10) inset${props.glow ? `, 0 0 160px -20px ${props.glow}` : ""}`,
        }}
      >
        <div style={{ width: "100%", height: "100%", borderRadius: radius - bezel, overflow: "hidden", background: "#000", position: "relative" }}>
          {props.children}
          <div style={{ position: "absolute", inset: 0, background: `linear-gradient(115deg, transparent ${glare - 18}%, rgba(255,255,255,.16) ${glare}%, transparent ${glare + 14}%)`, pointerEvents: "none" }} />
        </div>
      </div>
    </div>
  );
}

/** Frosted glass card. */
export function Glass({ children, style, tint = "rgba(255,255,255,.10)", dark = true }: { children: ReactNode; style?: CSSProperties; tint?: string; dark?: boolean }) {
  return (
    <div
      style={{
        borderRadius: 44,
        padding: "44px 52px",
        background: tint,
        backdropFilter: "blur(30px) saturate(1.4)",
        WebkitBackdropFilter: "blur(30px) saturate(1.4)",
        border: `1.5px solid ${dark ? "rgba(255,255,255,.18)" : "rgba(21,26,23,.08)"}`,
        boxShadow: dark ? "0 40px 90px -30px rgba(0,0,0,.7), inset 0 1px 0 rgba(255,255,255,.2)" : "0 40px 90px -36px rgba(21,26,23,.35), inset 0 1px 0 rgba(255,255,255,.8)",
        fontFamily: FONT,
        position: "relative",
        overflow: "hidden",
        ...style,
      }}
    >
      {children}
    </div>
  );
}

/** Pops in with a springy scale from frame [at]; optional depth fly-in. */
export function Pop({ at, children, style, from = 0.6, fly = 0 }: { at: number; children: ReactNode; style?: CSSProperties; from?: number; fly?: number }) {
  const f = useCurrentFrame();
  const s = spring({ frame: f - at, fps: FPS, config: { damping: 14, stiffness: 160, mass: 0.8 } });
  const o = prog(f, at, at + 6);
  return (
    <div style={{ transform: `perspective(1600px) translateZ(${(1 - s) * -fly}px) scale(${from + (1 - from) * s})`, opacity: o, filter: o < 1 ? `blur(${(1 - o) * 12}px)` : undefined, ...style }}>
      {children}
    </div>
  );
}

/** Rule of thirds safe area for TikTok/Reels UI: keep words inside. */
export const SAFE = { top: 250, bottom: 1480 };

/**
 * The closing frame: the crescent draws itself with a bloom, the wordmark
 * rises letter by letter, a light sweep crosses it, then tagline and footer.
 */
export function Finale(props: { at: number; tagline: string; theme: "dark" | "light"; footer?: string; glow?: string; badge?: boolean }) {
  const f = useCurrentFrame();
  const { at, theme } = props;
  const ink = theme === "dark" ? C.cream : C.ink;
  const sweep = prog(f, at, at + 16, inOut);
  const settle = spring({ frame: f - at, fps: FPS, config: { damping: 200, stiffness: 60 } });
  const bloom = Math.exp(-Math.max(0, f - at - 14) / 14) * prog(f, at + 4, at + 16);
  const mark = `brand/crescent-${theme === "dark" ? "cream" : "ink"}.svg`;
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
      <div style={{ position: "absolute", top: 640, width: "100%", display: "flex", justifyContent: "center", alignItems: "center", gap: 36, transform: `scale(${0.9 + 0.1 * settle})` }}>
        <div style={{ position: "relative", width: 200, height: 200 }}>
          <Img
            src={staticFile(mark)}
            style={{
              width: 200,
              height: 200,
              WebkitMaskImage: `conic-gradient(from 210deg, #000 ${sweep * 360}deg, transparent ${sweep * 360 + 0.5}deg)`,
              maskImage: `conic-gradient(from 210deg, #000 ${sweep * 360}deg, transparent ${sweep * 360 + 0.5}deg)`,
              filter: `drop-shadow(0 0 ${8 + 50 * bloom}px ${props.glow ?? "rgba(243,230,202,.6)"})`,
            }}
          />
        </div>
        <div style={{ position: "relative", overflow: "hidden", padding: "10px 6px 18px" }}>
          <div style={{ display: "flex", fontFamily: FONT, fontSize: 138, fontWeight: 300, color: ink, letterSpacing: "-0.035em", lineHeight: 1 }}>
            {"clearskin".split("").map((ch, i) => {
              const s = spring({ frame: f - at - 4 - i * 1.6, fps: FPS, config: { damping: 200, stiffness: 110 } });
              return (
                <span key={i} style={{ display: "inline-block", transform: `translateY(${(1 - s) * 120}%)` }}>
                  {ch}
                </span>
              );
            })}
          </div>
          <Sweep at={at + 26} len={26} color={theme === "dark" ? "rgba(255,255,255,.9)" : "rgba(255,255,255,1)"} />
        </div>
      </div>
      <MaskText lines={[props.tagline]} at={at + 18} size={64} weight={500} color={ink} tracking={-0.02} style={{ position: "absolute", top: 930, width: "100%" }} />
      <MaskText
        lines={[props.footer ?? "Available now on Google Play"]}
        at={at + 26}
        size={36}
        weight={500}
        color={ink}
        tracking={0}
        style={{ position: "absolute", top: 1040, width: "100%", opacity: 0.6 }}
      />
      {/* Google's badge, unaltered (its own clear space is in the image) */}
      {props.badge ? (
        <Pop at={at + 34} from={0.85} style={{ position: "absolute", top: 1110, width: "100%", display: "flex", justifyContent: "center" }}>
          <Img src={staticFile("brand/google-play-badge.png")} style={{ width: 517, height: 200 }} />
        </Pop>
      ) : null}
    </AbsoluteFill>
  );
}
