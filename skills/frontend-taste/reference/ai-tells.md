# AI-Tell Catalog (landing-page-specific)

*Folded in from taste-skill (MIT) — see ../NOTICE.md. This is the granular extension of the **absolute bans** + **AI slop test** in SKILL.md. Those are cross-register laws; this is the production-tested catalog of specific signatures that mark a marketing/landing/portfolio build as AI-made. Each is a default ban — overridable only when the brief explicitly calls for it. The pre-flight ([pre-flight.md](pre-flight.md)) turns the countable ones into a literal check.*

## The em-dash ban (the single most-violated tell)
**`—` and `–` are completely banned in anything visible** — headlines, eyebrows, labels, pills, button text, captions, nav, body copy, quote text, attribution. No "limited use," no "natural frequency" allowance. Restructure: period, comma, colon, parentheses, or a regular hyphen `-`. Date/number ranges use a hyphen (`2018-2026`, `€40-80k`), not an en-dash. The only permitted dashes are the regular hyphen and the math minus. One `—`/`–` anywhere visible = pre-flight fail. (This is binary on purpose; "use sparingly" has historically been ignored.)

## Hero & top-of-page
- **No version labels in the hero** (`V0.6`, `BETA`, `INVITE-ONLY PREVIEW`, `EARLY ACCESS`, `ALPHA`) unless the brief is explicitly a launch/preview.
- **No "Brand · No. 01"-style sub-eyebrows** (`Marrow · No. 01 · The 6-quart`).
- **No decoration text strip at hero bottom** (`BRAND. MOTION. SPATIAL.`, `TYPE / FORM / MOTION`, `ESTD. 2018 · LISBON`) unless it carries real nav links or real status.
- **Hero needs a real visual** — text + gradient blob is a placeholder, not a hero.

## Section numbering & micro-labels
- **No section-number eyebrows** (`00 / INDEX`, `001 · Capabilities`, `06 · how it works`). Eyebrows name the topic in plain language or are dropped entirely.
- **Eyebrow restraint** — max 1 eyebrow per 3 sections (hero counts as 1). Count `uppercase tracking` labels; if > `ceil(sectionCount/3)` it fails. What to do instead: drop it — the headline alone is enough.
- **No `01 / 4` pagination** on images/tiles; **no `Scroll · 001` scroll cues**; **no "Index of Work, 2018-2026" range labels** as eyebrows.
- **No micro-meta-sentences under eyebrows** ("Each of these is a feature we ship today, not a roadmap promise.").

## Separators, dots, flourishes
- **Middle-dot (`·`) rationed** — max 1 per metadata line; not the default separator for everything.
- **Zero decorative status dots by default** — a colored dot before nav items / list rows / badges is a tell. Only for real semantic state (live server status, availability), sparingly.
- **No `<br>`-broken-and-italicized headlines** as a default move (`for thirty<br>*years.*`).
- **No vertical rotated text**, **no crosshair/hairline grid lines as decoration**.

## Fake product previews
- **No div-based fake product UI** (fake task list, fake terminal, fake dashboard from styled divs) — the #1 design tell. Use a real screenshot, generated image, real mini-component, or nothing.
- **No fake version footers** inside fake screenshots (`v0.6.2-rc.1`, `last sync 4s ago · main`).

## Marketing-copy tells
- **No "Quietly in use at" / "Quietly trusted by"** — use "Trusted by", "Used at", or skip.
- **No "From the field" / "Field notes" / "Currently on the bench" / "On our desks"** performative-craftsman labels — use plain functional labels or none.
- **No "We respect the French ones"-style** mock-humble references.
- **No generic step labels** (`Stage 1/2/3`, `Phase 01/02/03`, `Pass One/Two`) — the step content is the label ("Install", "Configure", "Ship").
- **No filler verbs** ("Elevate", "Seamless", "Unleash", "Next-Gen", "Revolutionize") — concrete verbs only.
- **No generic names / brands / numbers** — not "John Doe", "Acme", "Nexus", "SmartFlow", `99.99%`, `50%`. Use realistic, locale-appropriate, organic values.

## Pills, labels, version stamps
- **No pills/labels/tags overlaid on images** (`Plate · Brand`, `Field notes - journal`) — let the image speak, or caption below it.
- **No photo-credit captions as decoration** (`Field study no. 12 · Ines Caetano`) unless a real photographer is credited for a real photo.
- **No version footers** (`v1.4.2`, `Build 0048`) on marketing pages.
- **No "Reservation 412 of 800"-style live-stock counters** unless real limited-run data.

## Locale, time, scroll cues
- **No locale / city-name / time / weather strips** (`Lisbon 14:23 · 18°C`, `1200-690 Lisbon, Portugal` in the nav) for ~99% of briefs — allowed only for genuinely globally-distributed studios / travel brands / real venues. A single footer address is fine.
- **Scroll cues banned** (`Scroll`, `↓ scroll`, `Scroll to explore`, animated mouse-wheel icons) — if the user hasn't scrolled, they're on the hero; they know.

## Lists, dividers, scoring
- **No `border-t` + `border-b` on every row** of a long list / spec table — see SKILL.md long-list guidance for the right component.
- **No scoring/progress bars with filled background tracks** as comparison visuals on a landing page (dashboard-UI clutter).

## Color & typography (extends the absolute bans)
- **Premium-consumer palette ban** — for cookware/wellness/artisan/luxury briefs, the AI default is warm beige/cream + brass/clay/oxblood + espresso text (`#f5f1ea`/`#b08947`/`#1a1714` families). Banned as the default reach; rotate to a different family (cold luxury, forest, black-and-tan, cobalt+cream, terracotta+slate, olive+brick, monochrome+pop). Override only on explicit brand direction.
- **Serif discipline** — serif is *very* discouraged as a default; "feels creative/premium" is not a reason. Banned defaults: `Fraunces`, `Instrument_Serif`. Default to a sans display (Geist Display, Cabinet Grotesk, PP Neue Montreal). If serif is genuinely justified, rotate the choice; don't reuse across consecutive projects.
- **No AI-purple / blue-glow** as default; **no neon outer glows**; **no excessive gradient text** on large headers.
