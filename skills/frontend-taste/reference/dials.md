# Dials — DESIGN_VARIANCE / MOTION_INTENSITY / VISUAL_DENSITY

*Folded in from taste-skill (MIT) — see ../NOTICE.md. Use alongside the shared design laws and the register reference; the dials make the "how bold / how kinetic / how dense" decision explicit and auditable instead of vibe-based.*

Three 1–10 dials gate every layout, motion, and density decision. Read the brief first, set the dials from that read, then **state the values you chose and why** before writing code. Do not silently fall back to the baseline, and do not ask the user to edit a config file — overrides happen conversationally.

- **`DESIGN_VARIANCE`** — 1 = perfect symmetry, 10 = artsy chaos
- **`MOTION_INTENSITY`** — 1 = static, 10 = cinematic / physics
- **`VISUAL_DENSITY`** — 1 = art gallery / airy, 10 = cockpit / packed data

**Baseline `8 / 6 / 4`** for a default marketing/landing build. Override from the design read. Use these exact variable names in any cross-reference; never invent aliases like `LAYOUT_VARIANCE`.

## Inference — design read → dial values

| Signal in the brief | VARIANCE | MOTION | DENSITY |
|---|---|---|---|
| minimalist / clean / calm / editorial / Linear-style | 5–6 | 3–4 | 2–3 |
| premium consumer / Apple-y / luxury / brand | 7–8 | 5–7 | 3–4 |
| playful / wild / Dribbble / Awwwards / experimental / agency | 9–10 | 8–10 | 3–4 |
| landing page / portfolio / marketing site (default) | 7–9 | 6–8 | 3–5 |
| trust-first / public-sector / regulated / accessibility-critical | 3–4 | 2–3 | 4–5 |
| redesign — preserve | match existing | +1 | match existing |
| redesign — overhaul | +2 | +2 | match existing |

## Use-case presets

| Use case | VARIANCE | MOTION | DENSITY |
|---|---|---|---|
| Landing (SaaS, mainstream) | 7 | 6 | 4 |
| Landing (agency / creative) | 9 | 8 | 3 |
| Landing (premium consumer) | 7 | 6 | 3 |
| Portfolio (designer / studio) | 8 | 7 | 3 |
| Portfolio (developer) | 6 | 5 | 4 |
| Editorial / blog | 6 | 4 | 3 |
| Public-sector service | 3 | 2 | 5 |
| Dashboard / dense product UI | 4–5 | 3–4 | 7–9 |

## What the levels mean

**DESIGN_VARIANCE**
- **1–3 (predictable):** symmetrical grid, equal padding, centered alignment.
- **4–7 (offset):** margin overlaps, varied image aspect ratios, left-aligned headers over centered data.
- **8–10 (asymmetric):** masonry, fractional grid tracks (`2fr 1fr 1fr`), large deliberate empty zones.
- **Mobile override:** levels 4–10 must collapse to strict single column (`w-full`, `px-4`) below `md` (768px).

**MOTION_INTENSITY**
- **1–3 (static):** `:hover` / `:active` only. Reduced-motion is effectively the default.
- **4–7 (fluid CSS):** transitions + `animation-delay` cascades on load. `transform` / `opacity` only.
- **8–10 (choreography):** scroll-triggered reveals, parallax, pinned/scrubbed sections via Motion or GSAP ScrollTrigger. Never `window.addEventListener('scroll')` — see [scroll-motion.md](scroll-motion.md).
- **"Motion claimed = motion shown":** if the dial is >4 the page must actually move (hero entry, scroll-reveal, CTA hover). If you can't ship working motion in scope, drop the dial to 3 and ship clean static rather than half-built motion.

**VISUAL_DENSITY**
- **1–3 (art gallery):** large section gaps (`py-32`–`py-48`), generous whitespace.
- **4–7 (daily app):** standard spacing (`py-16`–`py-24`).
- **8–10 (cockpit):** tight padding, 1px dividers instead of card boxes, `font-mono` for numbers.

Any motion above `MOTION_INTENSITY 3` must honor `prefers-reduced-motion`.
