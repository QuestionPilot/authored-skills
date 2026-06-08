# Scroll Motion — Canonical Skeletons & Forbidden Patterns

*Folded in from taste-skill (MIT) — see ../NOTICE.md. Read this when a build needs scroll-driven motion (pinned/scrubbed sections, horizontal hijack, reveal-on-enter). These are the patterns that most often break in AI output — the canonical fixes are `start: "top top"` + `pin: true` + the right scrub. Complements [motion-design.md](motion-design.md) (motion philosophy) with concrete working code.*

## Library choice
- **Motion (`motion/react`)** — default for UI / state-change / reveal motion. Import `{ motion } from "motion/react"`.
- **GSAP + ScrollTrigger** — for full-page scrolltelling and scroll hijacks. Isolate in dedicated leaf components with `useEffect` cleanup.
- **Three.js / WebGL** — canvas backgrounds, 3D scenes. Same isolation rule.
- **Never mix GSAP / Three.js with Motion in the same component tree** — they fight over the same frames.
- Continuous values (mouse, scroll progress, pointer physics) use Motion's `useMotionValue` / `useTransform` / `useScroll`, **never `useState`** (re-renders every frame, collapses on mobile).

## Sticky-Stack (cards pin and physically stack)

```tsx
"use client";
import { useRef, useEffect } from "react";
import { gsap } from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { useReducedMotion } from "motion/react";

gsap.registerPlugin(ScrollTrigger);

export function StickyStack({ cards }: { cards: React.ReactNode[] }) {
  const ref = useRef<HTMLDivElement>(null);
  const reduce = useReducedMotion();
  useEffect(() => {
    if (reduce || !ref.current) return;
    const ctx = gsap.context(() => {
      const cardEls = gsap.utils.toArray<HTMLElement>(".stack-card");
      cardEls.forEach((card, i) => {
        if (i === cardEls.length - 1) return;
        ScrollTrigger.create({
          trigger: card,
          start: "top top",                       // pin at viewport top — not "top center"/"top 80%"
          endTrigger: cardEls[cardEls.length - 1],
          end: "top top",
          pin: true,
          pinSpacing: false,
        });
        gsap.to(card, {
          scale: 0.92, opacity: 0.55, ease: "none",
          scrollTrigger: { trigger: cardEls[i + 1], start: "top bottom", end: "top top", scrub: true },
        });
      });
    }, ref);
    return () => ctx.revert();
  }, [reduce]);
  return (
    <div ref={ref} className="relative">
      {cards.map((card, i) => (
        <div key={i} className="stack-card sticky top-0 min-h-[100dvh] flex items-center justify-center">{card}</div>
      ))}
    </div>
  );
}
```

Every card except the last is pinned; the shrink transform is driven by the **next** card's trigger.

## Horizontal-Pan (vertical scroll → horizontal travel)

```tsx
"use client";
import { useRef, useEffect } from "react";
import { gsap } from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { useReducedMotion } from "motion/react";

gsap.registerPlugin(ScrollTrigger);

export function HorizontalPan({ children }: { children: React.ReactNode }) {
  const wrap = useRef<HTMLDivElement>(null);
  const track = useRef<HTMLDivElement>(null);
  const reduce = useReducedMotion();
  useEffect(() => {
    if (reduce || !wrap.current || !track.current) return;
    const ctx = gsap.context(() => {
      const distance = track.current!.scrollWidth - window.innerWidth;
      gsap.to(track.current, {
        x: -distance, ease: "none",
        scrollTrigger: {
          trigger: wrap.current,
          start: "top top",                       // pin when section top hits viewport top
          end: () => `+=${distance}`,             // scroll length = horizontal travel
          pin: true, scrub: 1, invalidateOnRefresh: true,
        },
      });
    }, wrap);
    return () => ctx.revert();
  }, [reduce]);
  return (
    <section ref={wrap} className="relative overflow-hidden">
      <div ref={track} className="flex h-[100dvh] items-center">{children}</div>
    </section>
  );
}
```

## Scroll-Reveal Stagger (lighter — prefer over GSAP for plain reveals)

```tsx
"use client";
import { motion, useReducedMotion } from "motion/react";

export function RevealStagger({ items }: { items: string[] }) {
  const reduce = useReducedMotion();
  return (
    <ul className="grid gap-6">
      {items.map((item, i) => (
        <motion.li key={item}
          initial={reduce ? false : { opacity: 0, y: 24 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, amount: 0.3 }}
          transition={{ duration: 0.6, delay: i * 0.06, ease: [0.16, 1, 0.3, 1] }}>
          {item}
        </motion.li>
      ))}
    </ul>
  );
}
```

Use for feature lists, testimonial grids, logo walls — anything that just needs "enter on scroll." Save GSAP for real pin/scrub work.

## Forbidden animation patterns (hard bans)
- **`window.addEventListener("scroll", …)`** — runs every frame, jank-prone. Use `useScroll()`, `ScrollTrigger`, `IntersectionObserver`, or CSS `animation-timeline: view()`.
- **Custom scroll-progress math via `window.scrollY` in React state.** Same reason.
- **`requestAnimationFrame` loops that touch React state.** Use motion values.
- Wrapping static content in Motion `layout` "for safety" — it costs measurement work; use `layout`/`layoutId` only for real visible state changes (reorder, expand, shared element).

## Performance & a11y guardrails
- Animate **only `transform` and `opacity`**; never `top` / `left` / `width` / `height`. `will-change: transform` sparingly.
- **Reduced motion (mandatory):** anything `MOTION_INTENSITY > 3` honors `prefers-reduced-motion` — `useReducedMotion()` in Motion, or `@media (prefers-reduced-motion: reduce)` in CSS. Infinite loops, parallax, scroll-hijack, magnetic physics collapse to static.
- Grain/noise filters only on fixed `pointer-events-none` pseudo-elements — never on scrolling containers.
- **Core Web Vitals:** LCP < 2.5s (hero image `priority`/preloaded), INP < 200ms, CLS < 0.1. Lazy-load below-the-fold; Motion + Three.js are not small.
- **Z-index restraint:** no arbitrary `z-50` spam — reserve for systemic layers (sticky nav, modal, overlay, grain) and document the scale.
