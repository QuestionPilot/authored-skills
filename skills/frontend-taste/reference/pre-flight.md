# Pre-Flight Check (mechanical, countable)

*Folded in from taste-skill (MIT) — see ../NOTICE.md. This is the last filter before delivering a landing page / portfolio / marketing build. Unlike the qualitative slop test, most boxes here are **countable** — you can verify them by grepping the markup, which is exactly why they catch the tells that "looks fine" misses. Run every box; if one can't be honestly ticked, the page is not done.*

The most powerful items are mechanical — turn them into a literal count over the component tree:

- [ ] **Brief inference** declared (one-line design read) and **dial values** explicit + reasoned, not silently baseline.
- [ ] **Design system** chosen from [design-systems.md](design-systems.md) if applicable, or the aesthetic labeled honestly.
- [ ] **Redesign mode** detected + audit done if applicable ([redesign.md](redesign.md)).
- [ ] **ZERO em-dashes (`—`/`–`) anywhere visible** — headlines, eyebrows, pills, body, quotes, attribution, captions, buttons, alt text. See [ai-tells.md](ai-tells.md). Grep the rendered strings; one occurrence = fail.
- [ ] **Page theme lock** — one theme (light / dark / auto) for the whole page; no section flips to inverted mid-page.
- [ ] **Color consistency lock** — one accent used identically across all sections; no surprise CTA color in section 7.
- [ ] **Shape consistency lock** — one corner-radius system, applied everywhere.
- [ ] **Button contrast** — every CTA text readable on its background (WCAG AA 4.5:1; 3:1 for ≥18px). No white-on-white, no border-less ghost buttons over photos.
- [ ] **CTA wrap** — no primary CTA label wraps to 2+ lines at desktop (≤3 words, ideally 1–2).
- [ ] **No duplicate CTA intent** — "Get in touch" + "Let's talk" + "Contact us" on one page = fail. One label per intent.
- [ ] **Form contrast** — inputs, placeholders, focus rings, labels, helper/error text all pass WCAG AA on the section bg.
- [ ] **Hero fits the viewport** — headline ≤2 lines, subtext ≤20 words AND ≤4 lines, CTA visible without scroll, font scale planned with the asset. Hero top padding ≤`pt-24`.
- [ ] **Hero stack** — ≤4 text elements (eyebrow OR brand strip, headline, subtext, CTAs). No tagline below CTAs, no trust micro-strip inside the hero.
- [ ] **Eyebrow count (mechanical)** — count `uppercase tracking` micro-labels above section headlines. Must be ≤ `ceil(sectionCount / 3)`; hero counts as 1.
- [ ] **Split-header ban** — no "big left headline + small right explainer paragraph" section headers; stack vertically (max-width 65ch).
- [ ] **Zigzag cap** — no 3+ consecutive sections with the same image+text-split layout.
- [ ] **Section-layout-repetition** — ≥4 distinct layout families across 8 sections; no family used twice for adjacent sections.
- [ ] **Bento** — N items → exactly N cells (no empty middle/trailing cell); ≥2–3 cells have real visual variation, not white-on-white text cards.
- [ ] **Logo wall** — under the hero, real SVG logos (Simple Icons / devicon) or generated marks, never plain text wordmarks, no industry labels under logos.
- [ ] **Copy self-audit** — re-read every visible string; no grammatically broken or hallucinated phrasing, no fake-precise numbers presented as real data.
- [ ] **Motion motivated** — each animation justifiable in one sentence (hierarchy / storytelling / feedback / state). Marquee ≤1 per page.
- [ ] **Navigation** — single line at desktop, height ≤80px.
- [ ] **Long lists** — >5 items use a real component (cards / tabs / carousel / scroll-snap), not `<ul>` + `divide-y`. No `border-t` + `border-b` on every row.
- [ ] **Real images** — gen-tool first, then `picsum.photos/seed/...`, then explicit placeholder slots. No div-based fake screenshots, no hand-rolled decorative SVGs, no pure-text "minimalism."
- [ ] **No decoration tells** — no version labels in hero, no section-number eyebrows (`001 · Capabilities`), no decorative status dots, no locale/time/weather strips, no scroll cues, no `v1.4.2`/`Build 0048` footers on marketing pages.
- [ ] **GSAP scroll** patterns match the [scroll-motion.md](scroll-motion.md) skeletons (`start: "top top"`, `pin: true`, correct scrub). No `window.addEventListener('scroll')`.
- [ ] **Reduced motion** wrapped for everything `MOTION_INTENSITY > 3`; **dark mode** tokens defined + tested in both modes; **viewport stability** `min-h-[100dvh]` not `h-screen`; `useEffect` animations have cleanup.
- [ ] **Interactive states** — loading / empty / error all provided.
- [ ] **Icons** from one allowed family (Phosphor / HugeIcons / Radix / Tabler), no hand-rolled SVG paths.
- [ ] **Core Web Vitals** plausibly hit (LCP < 2.5s, INP < 200ms, CLS < 0.1).
