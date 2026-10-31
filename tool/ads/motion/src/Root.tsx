import { Composition } from "remotion";
import { Clash, CLASH_FRAMES } from "./Clash";
import { Decoded, DECODED_FRAMES } from "./Decoded";
import { Explained, EXPLAINED_FRAMES } from "./Explained";
import { Guessing, GUESSING_FRAMES } from "./Guessing";
import { Measured, MEASURED_FRAMES } from "./Measured";
import { Hands, HANDS_FRAMES, PHONE_H, PHONE_SCAN_FRAMES, PHONE_W, PhoneScan } from "./Hands";
import { FPS, H, W } from "./kit";
import { Avatar, Highlight, Poster, POSTER_H, POSTER_W, PosterLive } from "./Poster";
import { PosterPeel } from "./PosterPeel";
import { Products, PRODUCTS_FRAMES } from "./Products";
import { PropsPreview } from "./PropsPreview";
import { Reads, READS_FRAMES } from "./Reads";
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
  ["Reads", Reads, READS_FRAMES],
  ["Hands", Hands, HANDS_FRAMES],
] as const;

export function Root() {
  return (
    <>
      {ADS.map(([id, component, frames]) => (
        <Composition key={id} id={id} component={component} durationInFrames={frames} fps={FPS} width={W} height={H} />
      ))}
      <Composition id="PhoneScan" component={PhoneScan} durationInFrames={PHONE_SCAN_FRAMES} fps={FPS} width={PHONE_W} height={PHONE_H} />
      <Composition id="Poster" component={Poster} durationInFrames={1} fps={FPS} width={POSTER_W} height={POSTER_H} />
      <Composition id="PosterLive" component={PosterLive} durationInFrames={1} fps={FPS} width={POSTER_W} height={POSTER_H} />
      <Composition id="PosterPeel" component={PosterPeel} durationInFrames={1} fps={FPS} width={POSTER_W} height={POSTER_H} />
      <Composition id="Avatar" component={Avatar} durationInFrames={1} fps={FPS} width={1080} height={1080} />
      {[["Scan", 38], ["Routine", 46], ["Guides", 52], ["Results", 60]].map(([word, lit]) => (
        <Composition key={word} id={`Highlight${word}`} component={Highlight} defaultProps={{ word: word as string, lit: lit as number }} durationInFrames={1} fps={FPS} width={1080} height={1080} />
      ))}
      <Composition id="PropsPreview" component={PropsPreview} durationInFrames={120} fps={FPS} width={W} height={H} />
    </>
  );
}
