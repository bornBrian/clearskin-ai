// Ad 07 — "Don't break the streak." Warm and punchy: a spark becomes the
// app's streak flame, the days count up on the beat, the week fills with
// flames, then the real streak screens in a phone. Every cut is on a beat
// of "Life of Riley" (102.01 BPM).

import { AbsoluteFill, Img, staticFile, useCurrentFrame } from "remotion";
import type { ReactNode } from "react";
import {
  beatsAt,
  C,
  Embers,
  EndCard,
  Enter,
  Flame,
  Flash,
  FONT,
  Glow,
  Grain,
  inOut,
  type Manifest,
  Note,
  Phone,
  prog,
  Rec,
  useJson,
  Words,
} from "./kit";

export const BPM = 102.01;
const b = beatsAt(BPM);
export const STREAK_FRAMES = b(32) + 15;

function Range({ from, to, children }: { from: number; to: number; children: ReactNode }) {
  const f = useCurrentFrame();
  return f >= from && f < to ? <>{children}</> : null;
}

const DAYS = [2, 3, 4, 5, 7, 10, 14, 21];
const STEPS = ["Cleanse.", "Treat.", "Moisturise.", "Protect.", "Repeat.", "Repeat.", "Repeat.", "Repeat."];
const WEEK = ["M", "T", "W", "T", "F", "S", "S"];

function Week({ lit, top, at, every = 0 }: { lit: number; top: number; at: number; every?: number }) {
  const f = useCurrentFrame();
  return (
    <div style={{ position: "absolute", top, width: "100%", display: "flex", justifyContent: "center", gap: 34 }}>
      {WEEK.map((d, i) => {
        const on = i < lit;
        const pop = on ? prog(f, at + i * every, at + i * every + 10) : 1;
        return (
          <div key={i} style={{ textAlign: "center", width: 96 }}>
            <Flame size={86} lit={on} seed={i + 3} grow={on ? 0.7 + 0.3 * pop : 0.9} />
            <div style={{ fontFamily: FONT, fontSize: 28, fontWeight: 600, color: C.cream, opacity: on ? 0.9 : 0.4, marginTop: 10 }}>{d}</div>
          </div>
        );
      })}
    </div>
  );
}

export function Streak() {
  const f = useCurrentFrame();
  const manifest = useJson<Manifest>("manifest.json");
  if (!manifest) return null;

  const heat = prog(f, 0, b(11), inOut);

  return (
    <AbsoluteFill style={{ background: "#0E0C0B" }}>
      <Glow color={`rgba(255,154,46,${0.12 + 0.3 * heat})`} x={540} y={860} r={520 + 260 * heat} drift={18} />

      {/* 1 · A spark becomes the flame. Day 1. */}
      <Range from={0} to={b(2)}>
        <AbsoluteFill>
          {f < b(1) ? (
            <div
              style={{
                position: "absolute",
                left: 540 - 20,
                top: 860 - 20,
                width: 40,
                height: 40,
                borderRadius: 20,
                background: C.flameCore,
                boxShadow: `0 0 ${40 + 30 * Math.sin(f / 2)}px 12px ${C.flameMid}`,
                opacity: 0.6 + 0.4 * Math.sin(f / 1.5),
              }}
            />
          ) : null}
          <div style={{ position: "absolute", left: 540 - 190, top: 560 }}>
            <Flame size={380} grow={prog(f, b(1), b(1) + 14)} seed={1} />
          </div>
          <Words text="Day 1." at={2} size={150} weight={800} style={{ position: "absolute", top: 1040, width: "100%" }} />
        </AbsoluteFill>
      </Range>

      {/* 2 · The days climb on the beat; the week fills. */}
      <Range from={b(2)} to={b(10)}>
        <AbsoluteFill>
          {(() => {
            let i = 0;
            while (i < DAYS.length - 1 && f >= b(3 + i)) i++;
            const at = b(2 + i);
            const punch = prog(f, at, at + 10);
            const size = 380 + 22 * i;
            return (
              <>
                <Words key={`s${i}`} text={STEPS[i]} at={at} size={92} weight={700} color={C.flameCore} style={{ position: "absolute", top: 260, width: "100%" }} />
                <div style={{ position: "absolute", left: 540 - size / 2, top: 940 - size }}>
                  <Flame size={size} seed={1} grow={0.92 + 0.08 * punch} />
                </div>
                <div
                  style={{
                    position: "absolute",
                    top: 990,
                    width: "100%",
                    textAlign: "center",
                    fontFamily: FONT,
                    fontSize: 170,
                    fontWeight: 800,
                    color: C.cream,
                    letterSpacing: "-0.045em",
                    transform: `scale(${1.18 - 0.18 * punch})`,
                  }}
                >
                  Day {DAYS[i]}
                </div>
                <Week lit={Math.min(7, i + 1)} top={1330} at={b(2)} every={b(1)} />
              </>
            );
          })()}
        </AbsoluteFill>
      </Range>

      {/* 3 · Day 28, at full blaze. */}
      <Range from={b(10)} to={b(12)}>
        <AbsoluteFill>
          <Embers x={540} y={900} start={b(10)} spread={420} count={34} />
          <div style={{ position: "absolute", left: 540 - 330, top: 960 - 640 }}>
            <Flame size={660} seed={1} grow={1 + 0.05 * Math.sin(f / 3)} />
          </div>
          <Words text="Day 28." at={b(10)} size={210} weight={800} style={{ position: "absolute", top: 1000, width: "100%" }} />
          <Week lit={7} top={1330} at={-100} />
          <Flash at={b(10)} color={C.flameCore} peak={0.5} />
        </AbsoluteFill>
      </Range>

      {/* 4 · The real streak screens. */}
      <Range from={b(12)} to={b(18)}>
        <PhoneScene
          top={["Skin changes slowly.", "Habits change it."]}
          screen={(f >= b(15) ? "renders/28-streak-extended.png" : "renders/26-today-streak.png")}
          switchAt={b(15)}
          start={b(12)}
        />
      </Range>

      {/* 5 · Progress. */}
      <Range from={b(18)} to={b(24)}>
        <PhoneScene top={["Show up every day.", "See what changes."]} flow="progress" manifest={manifest} start={b(18)} note="Sample data" />
      </Range>

      {/* 6 · The line. */}
      <Range from={b(24)} to={b(28)}>
        <AbsoluteFill>
          <Embers x={540} y={820} start={b(24)} spread={360} count={26} />
          <div style={{ position: "absolute", left: 540 - 260, top: 860 - 520 }}>
            <Flame size={520} seed={1} grow={prog(f, b(24), b(24) + 12)} />
          </div>
          <Words text="Don't break" at={b(24)} size={150} weight={800} style={{ position: "absolute", top: 940, width: "100%" }} />
          <Words text="the streak." at={b(25)} size={150} weight={800} color={C.flameMid} style={{ position: "absolute", top: 1100, width: "100%" }} />
        </AbsoluteFill>
      </Range>

      {/* 7 · Logo. */}
      <Range from={b(28)} to={STREAK_FRAMES}>
        <AbsoluteFill style={{ background: "#0E0C0B" }}>
          <Glow color="rgba(255,154,46,.14)" x={540} y={900} r={640} drift={20} />
          <EndCard at={b(28)} tagline="Skincare, every day." theme="dark" />
        </AbsoluteFill>
      </Range>

      <Flash at={b(12)} peak={0.3} />
      <Flash at={b(18)} peak={0.25} />
      <Flash at={b(24)} color={C.flameCore} peak={0.35} />
      <Grain opacity={0.07} />
    </AbsoluteFill>
  );
}

function PhoneScene(props: {
  top: [string, string];
  start: number;
  screen?: string;
  switchAt?: number;
  flow?: string;
  manifest?: Manifest;
  note?: string;
}) {
  const f = useCurrentFrame();
  const t = prog(f, props.start, props.start + 22);
  const ry = Math.sin((f - props.start) / 40) * 9;
  const render = !!props.screen;
  const width = render ? 480 : 540;
  const aspect = render ? 1170 / 2532 : 9 / 16;
  return (
    <AbsoluteFill>
      <AbsoluteFill style={{ perspective: 2000 }}>
        <div
          style={{
            position: "absolute",
            left: 540 - width / 2,
            top: 440,
            transform: `translateY(${(1 - t) * 1000}px) rotateX(10deg) rotateY(${ry}deg) rotateZ(${(1 - t) * -8}deg)`,
          }}
        >
          <Phone width={width} aspect={aspect} glow="rgba(255,154,46,.35)">
            {render ? (
              <Enter at={props.switchAt && f >= props.switchAt ? props.switchAt : props.start} from={1.04} blur={10}>
                <Img src={staticFile(props.screen!)} style={{ width: "100%", height: "100%", objectFit: "cover" }} />
              </Enter>
            ) : (
              <Rec flow={props.flow!} manifest={props.manifest!} at={props.start + 6} speed={0.6} />
            )}
          </Phone>
        </div>
      </AbsoluteFill>
      <AbsoluteFill style={{ background: "linear-gradient(rgba(14,12,11,.95) 0%, rgba(14,12,11,.55) 20%, transparent 30%)" }} />
      <Words text={props.top[0]} at={props.start} size={86} weight={700} stagger={2} style={{ position: "absolute", top: 180, width: "100%" }} />
      <Words text={props.top[1]} at={props.start + b(1.5)} size={86} weight={700} color={C.flameMid} style={{ position: "absolute", top: 290, width: "100%" }} />
      {props.switchAt ? <Flash at={props.switchAt} color={C.flameCore} peak={0.25} /> : null}
      {props.note ? <Note text={props.note} style={{ position: "absolute", top: 1590, width: "100%", textAlign: "center", fontSize: 22 }} /> : null}
    </AbsoluteFill>
  );
}
