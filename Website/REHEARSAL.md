# Rehearsal: Sakura-Cap website hero

Verified locally on 2026-11-01 against the production bundle in `docs/assets/demo/`.

## Composition and story

Gold: the installed Stageshow `static-card` example, copied into `gold/` and
filmed before adaptation. Kept the pinned window, shared gutter, deliberate
bleed and foreground payoff. Replaced the customer list with screenshot
annotation chrome, native-style outline tools, an editorial field note and
Sakura-Cap's bilingual copy. The surrounding page now uses mist blue and
soft pink following the user's palette preference; the lower sections retain
the existing actual-app screenshots.

Beats: choose rectangle, drag around the headline, return to the pointer,
copy, then hold the completed annotation and success message. Playback runs
once in view, approximately 11 seconds including the final hold; replay is
explicit. There is no automatic reset or loop seam. Targets are measured.
The rectangle grows from the cursor's actual position along a shared path.

Wide scene: 620 x 480 with a 24px gutter. Compact scene: 358 x 358 with a
16px gutter, a larger relative headline, fewer toolbar controls and a crop of
decorative artwork. Controls, the annotation and the success message remain
inside the visible composition. Reduced motion shows the completed result
without a cursor; JavaScript-disabled visits retain a real screenshot.

## Captures and results

All artifact paths below are local verification outputs, not site assets.
Final sheets and reports are retained in `../build/website-preview/`.

| Capture | Coverage | Result |
| --- | --- | --- |
| `wide-final.png`, 1280px host, 11 samples at 1200ms | 768 geometry frames / 12.78s, largest gap 26.2ms | No visual findings; complete coverage; gate passed |
| `phone-states-final.png`, 390px host, opening / each mark / settled states / end | 768 geometry frames / 12.78s, largest gap 26.1ms | No visual findings; complete coverage; gate passed |
| Earlier full phone sequence, 11 samples at 1200ms | 766 geometry frames / 12.77s, largest gap 25.7ms | No visual findings; complete coverage; gate passed |
| `drag-final.png`, 390px host, 24 samples at 80ms | One 27.3ms sampling gap | No visual findings in inspected images; continuous coverage inconclusive |
| `copy-detail.png`, 12 samples at 50ms | One 28.1ms sampling gap | No visual findings in inspected images; continuous coverage inconclusive |
| Desktop and phone reduced-motion posters | Static captures | No visual findings; gate passed; motion not assessed |
| Host layout audit, 390px, after 1800ms entrance settling | 2 controls / 3 padded containers in the viewport | No findings |

Contact sheets were visually inspected, including the drag and confirmation
close-ups. Earlier wide/detail recordings occasionally exceeded the film
tool's 27ms sampling threshold. Those individual recordings remain
inconclusive for continuous motion, even when their visual gate passed.
The final wide and phone-state recordings completed without sampling gaps.
These checks are finite samples, not a guarantee about every rendered frame
on every browser or device.

Findings fixed during rehearsal:

- Replaced a scaled screenshot wrapper with a kit Window and an authored scene.
- Bounded the illustration artwork inside one SVG instead of overflowing shapes.
- Moved the success message below the toolbar and restored the compact gutter.
- Gave the phone its own composition rather than shrinking the wide layout.
- Stacked the phone caption and its link to avoid an orphaned English word.
- Darkened small text and the primary download button for clearer contrast.
- Corrected the annotation drag: its dimensions now follow measured cursor
  coordinates, and the canvas uses a crosshair. Time-based growth had drifted
  from the cursor's eased trajectory.

## Fresh-eye review

A separate reviewer inspected the gold, bilingual viewport screenshots and
contact sheets. The only initial actionable finding was the English mobile
caption's isolated `share`; this was fixed by stacking the caption and link
below 420px. The reviewer then inspected the final drag detail and updated
desktop/mobile screenshots and found no new actionable visual issue. They
confirmed that the rectangle's corner tracks the crosshair and encloses the
headline. The reviewer did not verify every lower section or browser action;
those checks were performed separately as described here.

## Host website checks

- Both languages checked for horizontal overflow at 320, 390, 768, 1097 and
  1440px; none detected.
- Desktop 1440 x 1000 and phone 390 x 1000 screenshots inspected in both
  languages. Feature and installation sections also inspected on the phone.
- All image elements decoded successfully after loading the lazy images.
- Experience tabs checked with mouse, ArrowRight, Home and End, including
  wraparound, selected state, focus and matching visible panel.
- Language switching preserved the current section hash.
- Homebrew copy buttons showed successful feedback in Chinese and English.
- Replay restarted the scene and reached the rectangle-tool beat.
- Reduced-motion poster and JavaScript-disabled screenshot fallback verified.
- `npm run typecheck --prefix Website` passed.
- `npm run build --prefix Website` passed and regenerated license notices.
- `python3 Scripts/verify_website.py` passed for language parity, local links,
  accessibility references, tabs, image dimensions and the six WebP assets.
- `node --check docs/site.js` and `git diff --check` passed.

## Mist blue and pink palette revision

Replaced the initial green/coral palette across the page and demo, including
the SVG illustration, tools, annotation, confirmation and browser theme color.
The feature section uses a light blue ground and the download section uses
soft pink. Pink buttons have dark text. Small text uses deeper blue or rose;
navigation hover and small tab numbers use deeper rose for contrast.

Rebuilt and typechecked the production bundle. The bilingual site verifier
and whitespace checks passed. New desktop and phone reduced-motion film
posters (`blue-pink-poster-wide.png` and `blue-pink-poster-phone.png`) both
passed the visual gate without findings; these are still captures, not new
motion coverage. The layout and choreography are unchanged from the motion
checks above. Both languages were inspected at 1440px and 390px with no
horizontal overflow. Phone feature and download sections were also inspected.
The main pink button has 6.7:1 text contrast and the blue navigation button
has 5.4:1 text contrast.

Updated screenshots are named `blue-pink-*.png` in `../build/website-preview/`.

## Assumptions and limits

The hero is a labeled illustration of existing screenshot annotation and
copying. It is not an embedded app editor. Actual app interfaces remain
available in the experience and feature sections.

Not checked: physical iPhone or Android hardware, Safari/WebKit and Firefox,
production hosting/CDN behavior, and downloading or launching a release from
the external GitHub links. No deployment or release was performed.
