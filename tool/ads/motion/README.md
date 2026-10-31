# Motion ads

9:16 motion-graphics ads made with [Remotion](https://www.remotion.dev)
(React, rendered frame by frame in a headless browser). Their style follows
big-brand motion spots: kinetic type, hard cuts on the beat, the demo scan
drawing itself over the face, 3D phones and a logo reveal.

| Composition | File | Problem it answers | Sound |
| --- | --- | --- | --- |
| `Decoded` | `clearskin-ad-05-decoded` | what your skin is telling you | "Wallpaper"* |
| `Products` | `clearskin-ad-06-start-with-your-skin` | trending isn't right for you | "Carefree"* |
| `Streak` | `clearskin-ad-07-streak` | sticking with a routine | "Life of Riley"* |
| `Guessing` | `clearskin-ad-08-stop-guessing` | buying skincare blind | scored |
| `Clash` | `clearskin-ad-09-products-fighting` | products that irritate together | scored |
| `Working` | `clearskin-ad-10-is-it-working` | can't tell if it's working | scored |
| `Explained` | `clearskin-ad-11-skin-explained` | not knowing what's going on | scored |
| `Measured` | `clearskin-ad-12-measured` | still guessing (voiced, 3D props) | scored + voice |
| `Reads` | `clearskin-ad-13-reads-your-skin` | guessing, in real life (voiced, live footage) | scored + voice + recorded effects |
| `Hands` | `clearskin-ad-14-in-your-hands` | what the app does, one feature at a time, on real phones | scored + voice + recorded effects |

\* Kevin MacLeod (incompetech.com), CC BY 4.0: credit in the caption.

**Scored** ads get their soundtrack from `sound.py`: music written to the
cuts (pads, plucks, bass, drums, chords per bar) plus sound design
(whooshes, risers, impacts, ticks, pops), all synthesised, so no credit or
licence is needed. Picture and sound share `src/sound/<Id>.json`: tempo,
chords, which instruments play where, and the effect cues on beats. They
render with the score and as `-sfx-only` (effects only, quieter) for adding
a trending sound in TikTok or Instagram.

`premium.tsx` holds the motion kit for ads 08+: scenes with zoom-through
transitions and motion blur, masked type, camera float and shake, a phone
with depth and glass, glass cards, light leaks, dust and the finale.

Ad 13 (`Reads`) is live action: Mixkit stock footage (Mixkit Video Free
License: commercial use and ads, no attribution; only clips marked "Free",
never "Restricted"), cut to 9:16 from 4K by `prepare.mjs`. Its scan is the
app's own contour mesh tracked onto a real face, frame by frame, by
`track.py` (Google MediaPipe face landmarker), and its effects are recorded
sounds (Mixkit Sound Effects Free License) played from cues in
`src/sound/Reads.json`. The end card carries Google's official "Get it on
Google Play" badge, unaltered.

Ad 14 (`Hands`) puts the real app on real phones. Stock clips of hands
holding phones with blue or green screens (Mixkit, Free licence) are
composited by `screen_comp.py`: it finds the screen in every frame, fits its
edges, warps a recorded app flow onto it with fingers and notch kept in
front, carries the clip's light onto it and keys green backdrops to brand
colours. Plates are listed in `src/plates.json`. The flows are recorded at a
phone's shape (390×844) by the screenshot harness, and the scan screen is
the `PhoneScan` composition rendered as frames:

```sh
RECORD="$PWD/marketing/ads/source/rec2" flutter test tool/screenshots --plain-name "phone-shaped"   # from the repo root
node node_modules/@remotion/cli/remotion-cli.js render src/index.ts PhoneScan ../../../marketing/ads/source/rec2/phone/scan --sequence --image-format=png
python screen_comp.py src/plates.json
node render.mjs Hands
```

Screens only move when a finger moves on them. `fingers.py` finds the
fingertip on each plate's screen (in the screen's own flat space, from what
covers the key colour), `touch.py` turns upward strokes into swipes, and the
harness replays them into the app as real touch gestures, one plate frame
per recorded frame, so the app scrolls and flings under that finger. Plates
with `"follow"` in `src/plates.json` use those recordings; the others hold
still (or show what the app does on its own, like the scan finishing):

```sh
python fingers.py src/plates.json && python touch.py src/plates.json couch routine progress
RECORD="$PWD/marketing/ads/source/rec2" TOUCH="$PWD/marketing/ads/source/rec2/touch" flutter test tool/screenshots --plain-name "following a finger"   # repo root
python screen_comp.py src/plates.json
```

```sh
npm install
node prepare.mjs          # copies marketing/ads/source + brand assets into public/
python track.py public/footage/scan.mp4 public/track/scan.json   # ad 13's live mesh
KOKORO_DIR=... python voice.py src/sound/Reads.json              # voiced ads
npm run studio            # preview and scrub in the browser
node render.mjs           # all of them → marketing/ads/
node render.mjs Streak    # just one
```

Ads 05–07 render with their track and as `-no-music`; put the credit
printed by `render.mjs` in the caption of any post that uses the track.
`sound.py` needs Python with numpy and scipy.

## Rules the ads keep

- New ads use released stock footage for faces. `model.jpg` (used by
  `Decoded`, `Products`, `Guessing`, `Working`, `Explained` and the Python
  ads 03–04) is the Unsplash render-fixture face with no model release:
  don't run those as paid ads until the face is replaced. `Reads` and
  `Measured` don't use it, and app screens that show it are left out.
- App screens are recorded from the real app; progress screens show
  sample data and say so.
- No results promised and no claims the app doesn't make.
- The end card says "Available now on Google Play"; `Finale` can add the
  official badge (`badge`).

Remotion is free for individuals and companies of up to three people;
larger teams need a company licence.
