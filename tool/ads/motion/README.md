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

```sh
npm install
node prepare.mjs          # copies marketing/ads/source + brand assets into public/
npm run studio            # preview and scrub in the browser
node render.mjs           # all of them → marketing/ads/
node render.mjs Streak    # just one
```

Ads 05–07 render with their track and as `-no-music`; put the credit
printed by `render.mjs` in the caption of any post that uses the track.
`sound.py` needs Python with numpy and scipy.

## Rules the ads keep

- The face is a licensed model photo, labelled "Demo scan"; the mesh and
  lens maps are the engine's real readings of that photo, and the scores
  are the ones the app's report shows for it.
- App screens are recorded from the real app; progress screens show
  sample data and say so.
- No results promised and no claims the app doesn't make.
- The end card says "Coming soon on Google Play" until the app is live
  (change `footer` on `EndCard`).

Remotion is free for individuals and companies of up to three people;
larger teams need a company licence.
