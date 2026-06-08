# NOTICE — frontend-taste

`frontend-taste` is an operator-local Claude Code skill that consolidates three lineages into one. It was renamed in place from the `impeccable` skill.

## Attribution

**1. Anthropic `frontend-design` skill** — Apache License 2.0.
The base skill (`impeccable`, this skill's predecessor) was derived from Anthropic's `frontend-design` skill. The design-thinking spine, the "avoid generic AI aesthetics" stance, and several shared design laws originate there.
- Source: Anthropic Agent Skills (`frontend-design`).
- License: Apache 2.0.

**2. `impeccable` skill** — Apache License 2.0.
The command system (`craft` / `shape` / `audit` / `critique` / `polish` / `live` / etc.), the register model (brand vs product), the PRODUCT.md / DESIGN.md context loaders, the live-browser iteration mode, the anti-pattern detector, and the 30+ reference files are carried forward unchanged from `impeccable` v3.1.1.

**3. `taste-skill`** — MIT License. Copyright (c) 2026 Leonxlnx.
The following mechanics were folded in from `taste-skill` and adapted into this skill's reference files:
- The three dials (`DESIGN_VARIANCE` / `MOTION_INTENSITY` / `VISUAL_DENSITY`) — `reference/dials.md`
- The brief → design-system routing map + install commands + canonical docs — `reference/design-systems.md`
- The canonical GSAP scroll skeletons + forbidden animation patterns — `reference/scroll-motion.md`
- The granular landing-page AI-tell catalog (incl. the total em-dash ban) — `reference/ai-tells.md`
- The redesign protocol + "what never changes silently" — `reference/redesign.md`
- The mechanical, countable pre-flight checklist — `reference/pre-flight.md`
- Source: https://github.com/Leonxlnx/taste-skill
- License: MIT.

```
MIT License — Copyright (c) 2026 Leonxlnx

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Note on internal identifiers

This skill ships under the name `frontend-taste`, but its internal machinery (the `npx impeccable` CLI entry point, the `.impeccable/` project data directory, and `IMPECCABLE_*` / `window.__IMPECCABLE_*__` runtime identifiers) intentionally retains the `impeccable` name. Those are invisible to the user and the skill router; renaming them across the bundled scripts would carry breakage risk for no user-facing benefit.
