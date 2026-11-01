# Website product demonstration

The bilingual site in `docs/` remains a static GitHub Pages site. Its optional
hero illustration is built locally with React and the MIT-licensed Stageshow kit
from [benjitaylor/skills](https://github.com/benjitaylor/skills). The generated JS,
CSS, and license notices are committed under `docs/assets/demo/`; visitors do not
need Node, a CDN, or a backend. If JavaScript is unavailable, the hero shows the
existing actual-app screenshot instead.

## Build and preview

From the repository root:

```sh
npm ci --prefix Website
npm run typecheck --prefix Website
npm run build --prefix Website
python3 Scripts/verify_website.py
python3 -m http.server 8000 --directory docs
```

Open `http://127.0.0.1:8000/` or `/en.html`.

`demo.tsx` contains the bilingual scene, the reduced-motion poster, and its
once-in-view sequence. `demo.css` is scoped to the scene. The illustration shows
rectangle annotation and copying; it is labeled as an illustration, rather than
an actual app screenshot. The actual app screenshots remain in the experience
and feature sections. No new capabilities are implied by the demonstration.

## Reference and verification

`gold/` is the copied Stageshow `static-card` reference (only its import path was
adjusted). Its pinned window, shared gutter, bleed, and foreground payoff guided
the composition. Product content, native annotation tools, colors, compact
layout, and cursor sequence were rewritten for Sakura-Cap.

To view the gold, run `npm run dev --prefix Website` and open
`http://127.0.0.1:5175/gold.html`. Verification tools copied from Stageshow are in
`vendor/stageshow/scripts/`. For example:

```sh
node Website/vendor/stageshow/scripts/film.mjs http://127.0.0.1:8000/ --gate --out /tmp/desktop.png
node Website/vendor/stageshow/scripts/film.mjs http://127.0.0.1:8000/ --width 390 --gate --out /tmp/phone.png
```

Read `REHEARSAL.md` for the actual captured widths, checks, and limitations.
Upstream Stageshow sources retain their MIT license and notice. Generated bundle
notices are rebuilt by `notices.mjs` after every production build.
