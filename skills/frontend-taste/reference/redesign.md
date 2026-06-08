# Redesign Protocol

*Folded in from taste-skill (MIT) — see ../NOTICE.md. Read this whenever the task is improving an **existing** site/app rather than greenfield. Misclassifying the mode is the single biggest source of bad redesign output — and the "what never changes silently" list prevents the most expensive mistakes (broken SEO, broken analytics, broken muscle memory). Pairs with the `audit` / `critique` commands.*

## 1. Detect the mode (first action)
- **Greenfield** — no existing site, or a full overhaul is approved. Dial baseline from [dials.md](dials.md).
- **Redesign — Preserve** — modernise without breaking the brand. Audit first, extract brand tokens, evolve gradually.
- **Redesign — Overhaul** — new visual language over existing content. Treat as greenfield for visuals; preserve content + IA.

If ambiguous, ask **once**: *"Should this redesign preserve the existing brand, or are we starting visually from scratch?"*

## 2. Audit before touching
Document the current state before proposing changes:
- **Brand tokens** — primary/accent colors, type stack, logo treatment, radii.
- **Information architecture** — page tree, primary nav, key conversion paths.
- **Content blocks** — what exists, what's doing work, what's filler.
- **Patterns to preserve** — signature interactions, recognisable hero, copy voice.
- **Patterns to retire** — AI-slop tells ([ai-tells.md](ai-tells.md)), broken layouts, dead links, generic stock imagery, perf traps.
- **Dial reading of the existing site** — infer its current VARIANCE / MOTION / DENSITY; that's your starting point, not the baseline.
- **SEO baseline** — ranking pages, meta titles, structured data, OG cards. **SEO migration is the #1 redesign risk.**

## 3. Preservation rules
- **Do not change information architecture** unless asked. Keep slugs, anchor IDs, nav labels stable for SEO + muscle memory.
- **Extract brand colors before applying any color strategy.** A brand that is already purple stays purple.
- **Preserve copy voice** unless a rewrite is requested. Visual modernisation ≠ content rewrite.
- **Honor existing a11y wins** — don't regress focus states, alt text, keyboard nav, contrast.
- **Respect existing analytics events** — don't rename buttons, fields, or section IDs downstream tracking depends on.

## 4. Modernisation levers (priority order — stop when the brief is satisfied)
1. **Typography refresh** — biggest visual lift per unit of risk.
2. **Spacing & rhythm** — increase section padding, fix vertical rhythm.
3. **Color recalibration** — desaturate, unify neutrals, keep the brand accent.
4. **Motion layer** — add `MOTION_INTENSITY`-appropriate micro-interactions to existing components.
5. **Hero & key-section recomposition** — restructure top-of-funnel.
6. **Full block replacement** — only when a block is unsalvageable.

## 5. Decision tree: targeted evolution vs full redesign
- IA, content, and SEO sound → **targeted evolution** (levers 1–4). ~70% of the value at ~40% of the risk.
- Visual debt is structural (broken IA, no design system, broken mobile) → **full redesign** with strict content preservation.
- The brand itself is changing → **greenfield**.

## 6. What never changes silently
Never modify without explicit user approval:
- URL structure / route slugs.
- Primary nav labels.
- Form field names or order (breaks analytics + autofill).
- Brand logo or wordmark.
- Existing legal / consent / cookie copy.
