import { Composition } from "remotion";
import { Clash, CLASH_FRAMES } from "./Clash";
import { Decoded, DECODED_FRAMES } from "./Decoded";
import { Explained, EXPLAINED_FRAMES } from "./Explained";
import { Guessing, GUESSING_FRAMES } from "./Guessing";
import { Measured, MEASURED_FRAMES } from "./Measured";
import { FPS, H, W } from "./kit";
import { Products, PRODUCTS_FRAMES } from "./Products";
import { PropsPreview } from "./PropsPreview";
import { Streak, STREAK_FRAMES } from "./Streak";
import { Working, WORKING_FRAMES } from "./Working";

const ADS = [
  ["Decoded", Decoded, DECODED_FRAMES],
  ["Products", Products, PRODUCTS_FRAMES],
  ["Streak", Streak, STREAK_FRAMES],
  ["Guessing", Guessing, GUESSING_FRAMES],
  ["Clash", Clash, CLASH_FRAMES],
  ["Working", Working, WORKING_FRAMES],
  ["Explained", Explained, EXPLAINED_FRAMES],
  ["Measured", Measured, MEASURED_FRAMES],
] as const;

export function Root() {
  return (
    <>
      {ADS.map(([id, component, frames]) => (
        <Composition key={id} id={id} component={component} durationInFrames={frames} fps={FPS} width={W} height={H} />
      ))}
      <Composition id="PropsPreview" component={PropsPreview} durationInFrames={120} fps={FPS} width={W} height={H} />
    </>
  );
}
