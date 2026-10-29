// Brand-free 3D skincare props in ClearSkin's palette: matte "clay" objects
// with soft studio light, built from lathe profiles and rounded primitives so
// they can turn, bounce and catch light in real 3D (no stock images).

import { Environment, Lightformer, RoundedBox } from "@react-three/drei";
import type { ReactNode } from "react";
import { useMemo } from "react";
import * as THREE from "three";

export const P = {
  cream: "#F3E6CA",
  paper: "#FBF6EC",
  sage: "#B9CDB4",
  sageDeep: "#7FA287",
  charcoal: "#2A2A28",
  amber: "#C7843F",
  peach: "#EDBFA3",
  blush: "#E8B4A8",
  sun: "#F2C46B",
  water: "#BFE0DA",
};

/** Matte clay: soft, a touch of sheen, no plastic shine. */
export function Clay({ color, rough = 0.62, sheen = 0.35 }: { color: string; rough?: number; sheen?: number }) {
  return <meshPhysicalMaterial color={color} roughness={rough} metalness={0} clearcoat={0.15} clearcoatRoughness={0.6} sheen={sheen} sheenColor="#ffffff" sheenRoughness={0.8} />;
}

/** Tinted glass with real refraction. */
export function GlassMat({ color, thickness = 0.6 }: { color: string; thickness?: number }) {
  return (
    <meshPhysicalMaterial
      color={color}
      roughness={0.08}
      metalness={0}
      transmission={0.92}
      thickness={thickness}
      ior={1.45}
      attenuationColor={color}
      attenuationDistance={0.9}
      clearcoat={1}
      clearcoatRoughness={0.05}
    />
  );
}

/** Revolves a 2D profile [(radius, height)...] into a smooth solid. */
function useLathe(points: [number, number][], segments = 96) {
  return useMemo(() => {
    const curve = new THREE.SplineCurve(points.map(([x, y]) => new THREE.Vector2(x, y)));
    return new THREE.LatheGeometry(curve.getPoints(80), segments);
  }, [points, segments]);
}

type G = { position?: [number, number, number]; rotation?: [number, number, number]; scale?: number; children?: ReactNode };

/** Amber dropper bottle with a charcoal bulb. */
export function Dropper(p: G) {
  const body = useLathe([[0, 0], [0.42, 0.02], [0.5, 0.12], [0.5, 0.78], [0.44, 0.92], [0.2, 1.02], [0.18, 1.1], [0, 1.1]]);
  return (
    <group position={p.position} rotation={p.rotation} scale={p.scale}>
      <mesh geometry={body}><GlassMat color={P.amber} /></mesh>
      <mesh position={[0, 0.42, 0]}><cylinderGeometry args={[0.36, 0.36, 0.5, 64]} /><meshPhysicalMaterial color="#8A4E1C" roughness={0.5} transparent opacity={0.55} /></mesh>
      <mesh position={[0, 1.2, 0]}><cylinderGeometry args={[0.22, 0.22, 0.22, 64]} /><Clay color={P.charcoal} rough={0.4} /></mesh>
      <mesh position={[0, 1.52, 0]}><capsuleGeometry args={[0.19, 0.32, 12, 48]} /><Clay color={P.charcoal} rough={0.55} /></mesh>
    </group>
  );
}

/** Tall pump bottle. */
export function Pump(p: G & { color?: string }) {
  const body = useLathe([[0, 0], [0.4, 0.01], [0.46, 0.08], [0.46, 1.3], [0.4, 1.42], [0.16, 1.5], [0, 1.5]]);
  return (
    <group position={p.position} rotation={p.rotation} scale={p.scale}>
      <mesh geometry={body}><Clay color={p.color ?? P.paper} /></mesh>
      <mesh position={[0, 1.6, 0]}><cylinderGeometry args={[0.17, 0.2, 0.22, 48]} /><Clay color={P.sageDeep} /></mesh>
      <mesh position={[0, 1.8, 0]}><cylinderGeometry args={[0.07, 0.07, 0.24, 32]} /><Clay color={P.sageDeep} /></mesh>
      <RoundedBox args={[0.5, 0.12, 0.18]} radius={0.05} position={[0.14, 1.95, 0]}><Clay color={P.sageDeep} /></RoundedBox>
    </group>
  );
}

/** Low cream jar with a round, softly bevelled lid. */
export function Jar(p: G & { color?: string; lid?: string }) {
  const body = useLathe([[0, 0], [0.55, 0.01], [0.62, 0.08], [0.64, 0.4], [0.6, 0.46], [0, 0.46]]);
  const lid = useLathe([[0, 0.44], [0.66, 0.44], [0.7, 0.48], [0.71, 0.66], [0.68, 0.72], [0.6, 0.75], [0, 0.76]]);
  return (
    <group position={p.position} rotation={p.rotation} scale={p.scale}>
      <mesh geometry={body}><Clay color={p.color ?? P.sage} /></mesh>
      <mesh geometry={lid}><Clay color={p.lid ?? P.cream} rough={0.5} /></mesh>
    </group>
  );
}

/** Squeeze tube: oval body pressed flat into a crimp, ribbed cap. */
export function Tube(p: G & { color?: string }) {
  const geo = useMemo(() => {
    const g = new THREE.CylinderGeometry(0.36, 0.36, 1.7, 72, 48, false);
    const pos = g.attributes.position;
    for (let i = 0; i < pos.count; i++) {
      const y = pos.getY(i);
      const t = THREE.MathUtils.smoothstep(y, -0.55, 0.85); // 0 at the cap, 1 at the crimp
      pos.setZ(i, pos.getZ(i) * (0.78 - 0.74 * t));
      pos.setX(i, pos.getX(i) * (1 + 0.22 * t));
    }
    g.computeVertexNormals();
    return g;
  }, []);
  const color = p.color ?? P.blush;
  return (
    <group position={p.position} rotation={p.rotation} scale={p.scale}>
      <mesh geometry={geo}><Clay color={color} /></mesh>
      <RoundedBox args={[0.9, 0.16, 0.08]} radius={0.035} smoothness={4} position={[0, 0.9, 0]}><Clay color={color} rough={0.5} /></RoundedBox>
      <mesh position={[0, -0.97, 0]}><cylinderGeometry args={[0.25, 0.28, 0.3, 48]} /><Clay color={P.charcoal} rough={0.45} /></mesh>
      {Array.from({ length: 3 }, (_, i) => (
        <mesh key={i} position={[0, -0.88 - i * 0.08, 0]} rotation={[Math.PI / 2, 0, 0]}><torusGeometry args={[0.258 + i * 0.012, 0.012, 8, 48]} /><Clay color="#3a3a37" rough={0.4} /></mesh>
      ))}
    </group>
  );
}

/** SPF sun: soft sphere with rounded rays. */
export function Sun(p: G) {
  return (
    <group position={p.position} rotation={p.rotation} scale={p.scale}>
      <mesh><sphereGeometry args={[0.5, 64, 64]} /><Clay color={P.sun} rough={0.5} /></mesh>
      {Array.from({ length: 10 }, (_, i) => {
        const a = (i / 10) * Math.PI * 2;
        return (
          <mesh key={i} position={[Math.cos(a) * 0.82, Math.sin(a) * 0.82, 0]} rotation={[0, 0, a + Math.PI / 2]}>
            <capsuleGeometry args={[0.07, 0.16, 8, 24]} />
            <Clay color={P.sun} rough={0.5} />
          </mesh>
        );
      })}
    </group>
  );
}

/** Water drop. */
export function Drop(p: G) {
  const geo = useLathe([[0, 0], [0.32, 0.06], [0.44, 0.28], [0.4, 0.52], [0.26, 0.78], [0.1, 1.0], [0, 1.12]]);
  return (
    <group position={p.position} rotation={p.rotation} scale={p.scale}>
      <mesh geometry={geo}><GlassMat color={P.water} thickness={1.2} /></mesh>
    </group>
  );
}

/** A soft extruded leaf with a centre vein. */
export function Leaf(p: G & { color?: string }) {
  const geo = useMemo(() => {
    const s = new THREE.Shape();
    s.moveTo(0, -0.9);
    s.bezierCurveTo(0.55, -0.5, 0.6, 0.4, 0, 0.95);
    s.bezierCurveTo(-0.6, 0.4, -0.55, -0.5, 0, -0.9);
    return new THREE.ExtrudeGeometry(s, { depth: 0.06, bevelEnabled: true, bevelThickness: 0.06, bevelSize: 0.06, bevelSegments: 8, curveSegments: 48 });
  }, []);
  return (
    <group position={p.position} rotation={p.rotation} scale={p.scale}>
      <mesh geometry={geo}><Clay color={p.color ?? P.sageDeep} /></mesh>
      <mesh position={[0, 0, 0.13]}><capsuleGeometry args={[0.018, 1.4, 4, 12]} /><Clay color={P.sage} /></mesh>
    </group>
  );
}

/** Four-point sparkle. */
export function Sparkle(p: G & { color?: string }) {
  const geo = useMemo(() => {
    const s = new THREE.Shape();
    const k = 0.22;
    s.moveTo(0, 1);
    s.quadraticCurveTo(k, k, 1, 0);
    s.quadraticCurveTo(k, -k, 0, -1);
    s.quadraticCurveTo(-k, -k, -1, 0);
    s.quadraticCurveTo(-k, k, 0, 1);
    return new THREE.ExtrudeGeometry(s, { depth: 0.22, bevelEnabled: true, bevelThickness: 0.14, bevelSize: 0.1, bevelSegments: 12, curveSegments: 64 });
  }, []);
  return (
    <group position={p.position} rotation={p.rotation} scale={p.scale}>
      <mesh geometry={geo}><Clay color={p.color ?? P.cream} rough={0.45} /></mesh>
    </group>
  );
}

/** Round serum bottle with a sage cap. */
export function Serum(p: G) {
  const body = useLathe([[0, 0], [0.5, 0.02], [0.6, 0.3], [0.58, 0.62], [0.36, 0.86], [0.2, 0.92], [0, 0.92]]);
  return (
    <group position={p.position} rotation={p.rotation} scale={p.scale}>
      <mesh geometry={body}><GlassMat color={P.peach} /></mesh>
      <mesh position={[0, 1.06, 0]}><cylinderGeometry args={[0.24, 0.24, 0.32, 64]} /><Clay color={P.sageDeep} /></mesh>
    </group>
  );
}

/** Soft studio light: big overhead softbox, warm key, cool rim, no HDR download. */
export function Studio({ warm = 1 }: { warm?: number }) {
  return (
    <>
      <ambientLight intensity={0.35} />
      <hemisphereLight args={["#fff8ee", "#c9b9a0", 0.55]} />
      <directionalLight position={[3, 5, 4]} intensity={1.5 * warm} color="#fff1dc" />
      <directionalLight position={[-4, 2, -3]} intensity={0.9} color="#dfeaff" />
      <Environment resolution={256}>
        <Lightformer form="rect" intensity={3} position={[0, 5, 2]} scale={[8, 3, 1]} color="#fffaf0" />
        <Lightformer form="rect" intensity={1.6} position={[-5, 1, 1]} rotation={[0, Math.PI / 2, 0]} scale={[4, 6, 1]} color="#f3e6ca" />
        <Lightformer form="rect" intensity={1.2} position={[5, 1, -1]} rotation={[0, -Math.PI / 2, 0]} scale={[4, 6, 1]} color="#dfe9ff" />
        <Lightformer form="circle" intensity={2} position={[0, -3, 3]} scale={3} color="#f6efe2" />
      </Environment>
    </>
  );
}
