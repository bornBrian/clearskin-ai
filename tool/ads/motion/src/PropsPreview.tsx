// Contact sheet of the 3D props, for judging the look before animating.

import { ThreeCanvas } from "@remotion/three";
import { AbsoluteFill, useCurrentFrame } from "remotion";
import { H, W } from "./kit";
import { Dropper, Drop, Jar, Leaf, P, Pump, Serum, Sparkle, Studio, Sun, Tube } from "./props3d";

export function PropsPreview() {
  const f = useCurrentFrame();
  const spin = f / 40;
  return (
    <AbsoluteFill style={{ background: `radial-gradient(ellipse at 50% 40%, ${P.paper}, #EADCC0)` }}>
      <ThreeCanvas width={W} height={H} camera={{ position: [0, 0, 17], fov: 38 }} gl={{ antialias: true }}>
        <Studio />
        <Dropper position={[-1.9, 2.3, 0]} rotation={[0.15, spin, -0.12]} scale={1.1} />
        <Pump position={[0, 2.0, 0]} rotation={[0.1, spin + 0.6, 0.06]} scale={1} />
        <Serum position={[1.9, 2.4, 0]} rotation={[0.2, spin, 0.1]} scale={1.1} />
        <Jar position={[-1.9, -0.1, 0]} rotation={[0.45, spin, 0]} scale={1} />
        <Tube position={[0, -0.2, 0]} rotation={[0.2, spin + 0.4, -0.4]} scale={1.05} />
        <Sun position={[1.9, 0.2, 0]} rotation={[0.1, spin * 0.3, 0]} scale={0.95} />
        <Drop position={[-1.9, -2.9, 0]} rotation={[0.1, spin, 0.1]} scale={1.2} />
        <Leaf position={[0, -2.5, 0]} rotation={[0.2, spin * 0.6, 0.5]} scale={1} />
        <Sparkle position={[1.9, -2.5, 0]} rotation={[0.2, spin, 0]} scale={0.6} />
      </ThreeCanvas>
    </AbsoluteFill>
  );
}
