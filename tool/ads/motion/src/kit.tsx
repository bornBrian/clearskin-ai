// Shared pieces for the motion ads: timing on the music's beat, kinetic
// type, the phone, the demo-scan face, the flame and the end card.

import { useEffect, useState, type CSSProperties, type ReactNode } from "react";
import {
  AbsoluteFill,
  continueRender,
  delayRender,
  Easing,
  Img,
  interpolate,
  random,
  staticFile,
  useCurrentFrame,
} from "remotion";

export const FPS = 30;
export const W = 1080;
export const H = 1920;

export const C = {
  ink: "#151A17",
  charcoal: "#232321",
  night: "#08090A",
  cream: "#F3E6CA",
  paper: "#F6F2EA",
  sage: "#EEF2ED",
  leaf: "#3F8F5A",
  mint: "#7CC495",
  amber: "#E3AE55",
  flameCore: "#FFD45C",
  flameMid: "#FF9A2E",
  flameEdge: "#F0562B",
};
export const FONT = "Jakarta";

/** Frame of beat [n] (fractions allowed) at [bpm]. */
export const beatsAt = (bpm: number) => (n: number) => Math.round((n * FPS * 60) / bpm);

export const expoOut = Easing.bezier(0.16, 1, 0.3, 1);
export const inOut = Easing.bezier(0.65, 0, 0.35, 1);

/** 0→1 between frames [a] and [b]. */
export function prog(f: number, a: number, b: number, easing = expoOut): number {
  return interpolate(f, [a, b], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing });
}

// ── Fonts ─────────────────────────────────────────────────────────────

const WEIGHTS: [number, string][] = [
  [200, "ExtraLight"],
  [300, "Light"],
  [400, "Regular"],
  [500, "Medium"],
  [600, "SemiBold"],
  [700, "Bold"],
  [800, "ExtraBold"],
];
const fontsReady = delayRender("brand font");
Promise.all(
  WEIGHTS.map(([weight, name]) =>
    new FontFace(FONT, `url('${staticFile(`fonts/PlusJakartaSans-${name}.ttf`)}')`, { weight: String(weight) })
      .load()
      .then((face) => document.fonts.add(face)),
  ),
).then(() => continueRender(fontsReady));

export function useJson<T>(file: string): T | null {
  const [data, setData] = useState<T | null>(null);
  const [handle] = useState(() => delayRender(file));
  useEffect(() => {
    fetch(staticFile(file))
      .then((r) => r.json())
      .then((d: T) => {
        setData(d);
        continueRender(handle);
      });
  }, [file, handle]);
  return data;
}

// ── Type ──────────────────────────────────────────────────────────────

/**
 * A line whose words rise out of a blur, one after another, from frame
 * [at]; with [out], they blur away again.
 */
export function Words(props: {
  text: string;
  at: number;
  out?: number;
  size: number;
  weight?: number;
  color?: string;
  stagger?: number;
  style?: CSSProperties;
  dim?: string[];
}) {
  const f = useCurrentFrame();
  const { text, at, out, size, weight = 600, color = C.cream, stagger = 3, style, dim = [] } = props;
  const gone = out === undefined ? 0 : prog(f, out, out + 8, inOut);
  return (
    <div
      style={{
        fontFamily: FONT,
        fontSize: size,
        fontWeight: weight,
        color,
        letterSpacing: "-0.035em",
        lineHeight: 1.04,
        textAlign: "center",
        opacity: 1 - gone,
        filter: gone ? `blur(${gone * 14}px)` : undefined,
        ...style,
      }}
    >
      {text.split(" ").map((w, i) => {
        const t = prog(f, at + i * stagger, at + i * stagger + 14);
        return (
          <span
            key={i}
            style={{
              display: "inline-block",
              whiteSpace: "pre",
              opacity: t * (dim.includes(w) ? 0.42 : 1),
              transform: `translateY(${(1 - t) * 0.4}em) scale(${0.96 + 0.04 * t})`,
              filter: t < 1 ? `blur(${(1 - t) * 16}px)` : undefined,
            }}
          >
            {w + (i < text.split(" ").length - 1 ? " " : "")}
          </span>
        );
      })}
    </div>
  );
}

/** A number that counts up from [from] to [to] between frames [a] and [b]. */
export function Count(props: { from: number; to: number; a: number; b: number; style?: CSSProperties }) {
  const f = useCurrentFrame();
  const v = Math.round(interpolate(prog(f, props.a, props.b, inOut), [0, 1], [props.from, props.to]));
  return <span style={{ fontVariantNumeric: "tabular-nums", ...props.style }}>{v}</span>;
}

// ── Surfaces ──────────────────────────────────────────────────────────

/** Film grain, so flat gradients don't band and the frame feels shot. */
export function Grain({ opacity = 0.07 }: { opacity?: number }) {
  const f = useCurrentFrame();
  return (
    <AbsoluteFill style={{ mixBlendMode: "overlay", opacity, pointerEvents: "none" }}>
      <svg width={W} height={H}>
        <filter id="grain">
          <feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves="2" seed={f % 12} />
          <feColorMatrix type="saturate" values="0" />
        </filter>
        <rect width={W} height={H} filter="url(#grain)" />
      </svg>
    </AbsoluteFill>
  );
}

/** Soft coloured light drifting behind the content. */
export function Glow(props: { color: string; x: number; y: number; r: number; opacity?: number; drift?: number }) {
  const f = useCurrentFrame();
  const d = props.drift ?? 40;
  const x = props.x + Math.sin(f / 47) * d;
  const y = props.y + Math.cos(f / 61) * d;
  return (
    <div
      style={{
        position: "absolute",
        left: x - props.r,
        top: y - props.r,
        width: props.r * 2,
        height: props.r * 2,
        borderRadius: "50%",
        background: `radial-gradient(circle, ${props.color} 0%, transparent 68%)`,
        opacity: props.opacity ?? 1,
      }}
    />
  );
}

/** A white flash that marks a big cut. */
export function Flash({ at, color = "#fff", peak = 0.55 }: { at: number; color?: string; peak?: number }) {
  const f = useCurrentFrame();
  const o = interpolate(f, [at - 2, at, at + 7], [0, peak, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  return o > 0 ? <AbsoluteFill style={{ background: color, opacity: o }} /> : null;
}

/** Scene entrance: arrives slightly large and blurred, settles fast. */
export function Enter(props: { at: number; children: ReactNode; from?: number; blur?: number; style?: CSSProperties }) {
  const f = useCurrentFrame();
  const t = prog(f, props.at, props.at + 12);
  const s = (props.from ?? 1.08) + (1 - (props.from ?? 1.08)) * t;
  return (
    <AbsoluteFill
      style={{ transform: `scale(${s})`, filter: t < 1 ? `blur(${(1 - t) * (props.blur ?? 18)}px)` : undefined, ...props.style }}
    >
      {props.children}
    </AbsoluteFill>
  );
}

// ── Phone ─────────────────────────────────────────────────────────────

export interface Manifest {
  rec: Record<string, number>;
}

/** A recorded app flow, played from frame [at] at [speed]. */
export function Rec({ flow, at, manifest, speed = 1, from = 0 }: { flow: string; at: number; manifest: Manifest; speed?: number; from?: number }) {
  const f = useCurrentFrame();
  const n = manifest.rec[flow];
  const i = Math.max(0, Math.min(n - 1, Math.floor(from + (f - at) * speed)));
  return <Img src={staticFile(`rec/${flow}/${String(i).padStart(5, "0")}.jpg`)} style={{ width: "100%", height: "100%", objectFit: "cover" }} />;
}

export function Phone(props: { width: number; aspect: number; children: ReactNode; style?: CSSProperties; glow?: string }) {
  const { width, aspect } = props;
  const bezel = width * 0.028;
  return (
    <div
      style={{
        width,
        height: width / aspect + bezel * 2,
        padding: bezel,
        borderRadius: width * 0.14,
        background: "linear-gradient(145deg, #2b2c2e, #0a0a0b 40%, #1c1d1f)",
        boxShadow: `0 60px 120px -30px rgba(0,0,0,.75), 0 0 0 2px rgba(255,255,255,.06) inset${props.glow ? `, 0 0 140px -10px ${props.glow}` : ""}`,
        ...props.style,
      }}
    >
      <div style={{ width: "100%", height: "100%", borderRadius: width * 0.115, overflow: "hidden", background: "#000", position: "relative" }}>
        {props.children}
      </div>
    </div>
  );
}

// ── Demo-scan face ────────────────────────────────────────────────────

export interface Mesh {
  points: [number, number][];
  tris: [number, number, number][];
  radiance: { score: number; evenness: number; clarity: number; sheen: number };
}

/**
 * The engine's 134-point mesh, appearing as a scan line at [scanY] (0..1 of
 * the frame) passes over it.
 */
export function MeshOverlay({ mesh, scanY, color = C.cream, opacity = 1 }: { mesh: Mesh; scanY: number; color?: string; opacity?: number }) {
  const edges = new Map<string, [number, number]>();
  for (const [a, b, c] of mesh.tris) {
    for (const [p, q] of [[a, b], [b, c], [c, a]]) edges.set(p < q ? `${p}-${q}` : `${q}-${p}`, [p, q]);
  }
  const shown = (y: number) => Math.max(0, Math.min(1, (scanY - y) / 0.05));
  return (
    <svg width={W} height={H} style={{ position: "absolute", inset: 0, opacity }}>
      {[...edges.values()].map(([p, q]) => {
        const [x1, y1] = mesh.points[p];
        const [x2, y2] = mesh.points[q];
        const o = shown(Math.max(y1, y2));
        return o > 0 ? (
          <line key={`${p}-${q}`} x1={x1 * W} y1={y1 * H} x2={x2 * W} y2={y2 * H} stroke={color} strokeWidth={1.4} strokeOpacity={0.38 * o} />
        ) : null;
      })}
      {mesh.points.map(([x, y], i) => {
        const o = shown(y);
        return o > 0 ? <circle key={i} cx={x * W} cy={y * H} r={2 + 4 * (1 - o)} fill={color} opacity={0.9 * o} /> : null;
      })}
    </svg>
  );
}

/** One of the engine's lens maps, as coloured light on the face. */
export function Lens({ name, color, opacity = 1 }: { name: string; color: string; opacity?: number }) {
  const mask: CSSProperties = {
    WebkitMaskImage: `url(${staticFile(`lens/lens_${name}.png`)})`,
    maskImage: `url(${staticFile(`lens/lens_${name}.png`)})`,
    WebkitMaskSize: "cover",
    maskSize: "cover",
    maskMode: "luminance",
  };
  return (
    <AbsoluteFill style={{ opacity, mixBlendMode: "screen" }}>
      <AbsoluteFill style={{ ...mask, background: color, filter: "blur(18px)", opacity: 0.9 }} />
      <AbsoluteFill style={{ ...mask, background: color, opacity: 0.75 }} />
    </AbsoluteFill>
  );
}

// ── Flame (the app's streak flame, same shape) ───────────────────────

function flamePaths(sway: number) {
  const x = (v: number) => v * 100;
  const y = (v: number) => v * 100;
  const tip = 0.5 + sway;
  const outer = `M${x(tip)},${y(0)} C${x(0.62 + sway)},${y(0.2)} ${x(0.98)},${y(0.38)} ${x(0.94)},${y(0.66)} C${x(0.91)},${y(0.88)} ${x(0.72)},${y(1)} ${x(0.5)},${y(1)} C${x(0.27)},${y(1)} ${x(0.06)},${y(0.86)} ${x(0.06)},${y(0.62)} C${x(0.06)},${y(0.46)} ${x(0.16)},${y(0.36)} ${x(0.27)},${y(0.27)} C${x(0.26)},${y(0.4)} ${x(0.32)},${y(0.49)} ${x(0.4)},${y(0.52)} C${x(0.36)},${y(0.32)} ${x(0.42 + sway)},${y(0.14)} ${x(tip)},${y(0)} Z`;
  const s = sway * 1.6;
  const inner = `M${x(0.52 - s)},${y(0.42)} C${x(0.6)},${y(0.56)} ${x(0.74)},${y(0.66)} ${x(0.72)},${y(0.8)} C${x(0.7)},${y(0.93)} ${x(0.6)},${y(1)} ${x(0.5)},${y(1)} C${x(0.38)},${y(1)} ${x(0.28)},${y(0.93)} ${x(0.28)},${y(0.8)} C${x(0.28)},${y(0.66)} ${x(0.44)},${y(0.56)} ${x(0.52 - s)},${y(0.42)} Z`;
  return { outer, inner };
}

export function Flame({ size, grow = 1, lit = true, seed = 0, style }: { size: number; grow?: number; lit?: boolean; seed?: number; style?: CSSProperties }) {
  const f = useCurrentFrame();
  const t = ((f + seed * 17) / 72) * 2 * Math.PI;
  const sway = lit ? Math.sin(t) * 0.025 + Math.sin(t * 2.3) * 0.012 : 0;
  const stretch = lit ? 1 + Math.sin(t * 1.7) * 0.035 : 1;
  const { outer, inner } = flamePaths(sway);
  const id = `fl${seed}`;
  return (
    <svg width={size} height={size} viewBox="0 0 100 100" style={{ overflow: "visible", ...style }}>
      <defs>
        <linearGradient id={`${id}o`} x1="0" y1="1" x2="0" y2="0">
          <stop offset="0" stopColor={C.flameMid} />
          <stop offset="1" stopColor={C.flameEdge} />
        </linearGradient>
        <linearGradient id={`${id}i`} x1="0" y1="1" x2="0" y2="0">
          <stop offset="0" stopColor={C.flameCore} />
          <stop offset="1" stopColor={C.flameMid} />
        </linearGradient>
      </defs>
      <g transform={`translate(50 100) scale(${grow} ${grow * stretch}) translate(-50 -100)`}>
        <path d={outer} fill={lit ? `url(#${id}o)` : "#4a4744"} />
        <path d={inner} fill={lit ? `url(#${id}i)` : "#5e5a56"} />
      </g>
    </svg>
  );
}

/** Sparks drifting up from a fire at ([x], [y]). */
export function Embers({ x, y, count = 26, spread = 260, start = 0, color = C.flameCore }: { x: number; y: number; count?: number; spread?: number; start?: number; color?: string }) {
  const f = useCurrentFrame() - start;
  if (f < 0) return null;
  return (
    <>
      {Array.from({ length: count }, (_, i) => {
        const life = 40 + random(`l${i}`) * 50;
        const t = ((f + random(`o${i}`) * life) % life) / life;
        const px = x + (random(`x${i}`) - 0.5) * spread + Math.sin(t * 6 + i) * 18;
        const py = y - t * (380 + random(`h${i}`) * 300);
        const r = 2 + random(`r${i}`) * 4;
        return (
          <div
            key={i}
            style={{
              position: "absolute",
              left: px,
              top: py,
              width: r * 2,
              height: r * 2,
              borderRadius: "50%",
              background: color,
              boxShadow: `0 0 ${r * 4}px ${C.flameMid}`,
              opacity: Math.sin(t * Math.PI) * 0.9,
            }}
          />
        );
      })}
    </>
  );
}

// ── Labels and the end card ───────────────────────────────────────────

/** Small honest label, e.g. that the scan is a demo on a model. */
export function Note({ text, color = C.cream, style }: { text: string; color?: string; style?: CSSProperties }) {
  return (
    <div style={{ fontFamily: FONT, fontSize: 26, fontWeight: 500, letterSpacing: "0.12em", textTransform: "uppercase", color, opacity: 0.62, ...style }}>
      {text}
    </div>
  );
}

export function EndCard(props: { at: number; tagline: string; theme: "dark" | "light"; footer?: string }) {
  const f = useCurrentFrame();
  const { at, theme } = props;
  const ink = theme === "dark" ? C.cream : C.ink;
  const sweep = prog(f, at, at + 26, inOut);
  const settle = prog(f, at, at + 40);
  const word = "clearskin";
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
      <div style={{ display: "flex", alignItems: "center", gap: 34, transform: `translateY(-60px) scale(${0.92 + 0.08 * settle})` }}>
        <Img
          src={staticFile(`brand/crescent-${theme === "dark" ? "cream" : "ink"}.svg`)}
          style={{
            width: 190,
            height: 190,
            WebkitMaskImage: `conic-gradient(from 210deg, #000 ${sweep * 360}deg, transparent ${sweep * 360 + 0.5}deg)`,
            maskImage: `conic-gradient(from 210deg, #000 ${sweep * 360}deg, transparent ${sweep * 360 + 0.5}deg)`,
            filter: theme === "dark" ? `drop-shadow(0 0 ${30 * (1 - settle) + 12}px rgba(243,230,202,.35))` : undefined,
          }}
        />
        <div style={{ fontFamily: FONT, fontSize: 132, fontWeight: 300, color: ink, letterSpacing: "-0.03em", display: "flex" }}>
          {word.split("").map((ch, i) => {
            const t = prog(f, at + 8 + i * 2, at + 24 + i * 2);
            return (
              <span key={i} style={{ display: "inline-block", opacity: t, transform: `translateY(${(1 - t) * 40}px)`, filter: t < 1 ? `blur(${(1 - t) * 10}px)` : undefined }}>
                {ch}
              </span>
            );
          })}
        </div>
      </div>
      <Words text={props.tagline} at={at + 30} size={58} weight={400} color={ink} style={{ position: "absolute", top: 1080, width: "100%" }} />
      <Words
        text={props.footer ?? "Available now on Google Play"}
        at={at + 42}
        size={34}
        weight={500}
        color={ink}
        stagger={2}
        style={{ position: "absolute", top: 1200, width: "100%", opacity: 0.7, letterSpacing: "0.01em" }}
      />
    </AbsoluteFill>
  );
}
