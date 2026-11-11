# Debagr launch kit

Prepared 22 October 2026 for the **0.2.0 technical preview**, published
4 November 2026. On 11 November 2026 the release notes and launch copy were
prepared for **0.3.0**, which is not yet published; the site and its download
link stay on 0.2.0 until the publish step in
[`../docs/RELEASE.md`](../docs/RELEASE.md). Open `index.html` for the local
gallery. Status and remaining gaps are in
[`../docs/SHIP_STATUS.md`](../docs/SHIP_STATUS.md).

| Asset | Format | Use |
| --- | --- | --- |
| `screenshots/device-setup-{light,dark}.png` | 2000 × 1680 PNG | Native setup UI |
| `screenshots/agent-tools-{light,dark}.png` | 2000 × 1680 PNG | Native agent onboarding |
| `video/debagr-promo-landscape.mp4` | 1920 × 1080, 24 s, H.264, 24 fps | Website and landscape social |
| `video/debagr-promo-vertical.mp4` | 1080 × 1920, 24 s, H.264, 24 fps | Vertical social |
| `video/debagr-promo.vtt` | English WebVTT | Accessible captions for both cuts |
| `video/debagr-promo.srt` | English SRT | Captions for social uploads |
| `video/*-poster.jpg` | Video-sized JPEG | Preview thumbnails |
| `social/launch-card.png` | 1200 × 630 PNG | Social sharing card |
| `sponsorship/cover.png` | 1200 × 630 PNG | Creator/sponsor cover |
| `launch-copy.md` | Copy and storyboard | Social posts, product descriptions, voiceover |
| `sponsorship/README.md` | Profile and tier drafts | GitHub Sponsors and Ko-fi setup |
| `release-notes.md` | GitHub release body | 0.3.0 technical-preview release |
| `site/` | Self-contained static site | Source of the live site at radeknovis.github.io/debagr-site |

The captures use the real AppKit/SwiftUI views compiled in a temporary source
copy. Only automatic peer discovery is disabled in that copy. The sample model
contains synthetic device details; no real UDID, hostname, VPN endpoint, pairing
profile, or user settings were read. `screenshots/provenance.json` records the
source version and view hash. Captures and videos illustrate the UI, not a fresh
hardware deployment. The shipped app has no demo mode or fixture code.

The website deliberately has no checkout, hard-coded subscription price,
unverified payment destination, or invented success state. The download link
points at the published 0.2.0 DMG until 0.3.0 is published; funding links stay in preparation until
verified HTTPS URLs are supplied in `site/config.js`. All runtime resources are local; the page has no tracker,
external font, signup form, or dependency on a frontend build system.

## Regenerate from the repository checkout

```sh
python3 scripts/capture-marketing.py
python3 scripts/render-marketing.py
```

Capture requires macOS, Xcode, and xcsift. Rendering requires Pillow, ffmpeg, and
macOS Arial fonts. Use the Codex bundled Python if the system Python has no
Pillow; no new dependency is added to Debagr itself. Rendering refreshes the
website's selected media too. Run `python3 scripts/check-marketing.py` to check
the local links, formats, sizes, and URL activation logic, then review key frames.

## Preview locally

From the repository root:

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory Marketing
```

Open `http://127.0.0.1:8765/` for the gallery or `/site/` for the launch page.
The live site is a copy of `site/` in the public
[`radeknovis/debagr-site`](https://github.com/radeknovis/debagr-site) repository,
served by GitHub Pages at https://radeknovis.github.io/debagr-site/. To update it, copy the
whole `site/` directory into that repository and push. Its `og:image` is an
absolute URL on that host; change it if the site moves.

The kit contains original product graphics and native UI. No stock, generated
people, licensed music, third-party testimonials, or fabricated deployment
results are included. Brand references identify compatibility, not endorsement.
