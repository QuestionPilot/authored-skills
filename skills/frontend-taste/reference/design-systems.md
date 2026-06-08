# Brief → Design System Map

*Folded in from taste-skill (MIT) — see ../NOTICE.md. Read this when a brief reads like an established product family (enterprise, public-sector, Shopify/Atlassian/GitHub surfaces) — reaching for the official package beats hand-rolling its look.*

Once you have the design read and dials, pick the right foundation. **Do not invent CSS for something that has an official package, and do not pretend an aesthetic trend is an official system.**

## When to reach for a real design system (use the official package)

| Brief reads as… | Reach for | Why |
|---|---|---|
| Microsoft / enterprise SaaS / dashboards | `@fluentui/react-components` or `@fluentui/web-components` | Official Fluent UI, MS tokens, a11y done |
| Google-ish, Material-flavored product | `@material/web` + Material 3 tokens | Official, theme-able via Material Theming |
| IBM-style B2B / enterprise analytics | `@carbon/react` + `@carbon/styles` | Mature data-density patterns |
| Shopify app surfaces | Polaris web components / Polaris React | Required for Shopify admin UI |
| Atlassian / Jira-style product | `@atlaskit/*` + `@atlaskit/tokens` | Official Atlassian DS |
| GitHub-style devtool / community page | `@primer/css` or `@primer/react-brand` | Official Primer; Brand variant for marketing |
| Public-sector UK service | `govuk-frontend` | Legally / regulatorily expected |
| US public-sector / trust-first | `uswds` | Same |
| Fast local-business / agency MVP | Bootstrap 5.3 | Boring, fast, works |
| Modern accessible React foundation | `@radix-ui/themes` | Primitives + polished theme |
| Modern SaaS where you own the components | shadcn/ui (`npx shadcn@latest add …`) | You own the code; never ship default state |
| Tailwind-based modern SaaS / AI marketing | Tailwind v4 utilities + `dark:` | Default for indie + small-team builds |

**Honesty rule:** if the brief matches one of these, install and use the **official** package. Do not recreate its CSS by hand. Do not import its tokens then override 90% of them. **One system per project** — don't mix Fluent with Carbon, or import shadcn into a Material 3 app.

## When the brief is an aesthetic, not a system

No single official package exists for these. Build with native CSS + Tailwind + a maintained component library, and be honest in comments about borrowed inspiration vs. official material.

| Aesthetic | Honest implementation |
|---|---|
| Glassmorphism / frosted glass | `backdrop-filter`, layered borders, highlight overlays. Solid-fill fallback for `prefers-reduced-transparency`. |
| Bento (Apple-style tile grids) | CSS Grid with mixed cell sizes. No library owns this. |
| Brutalism | Native CSS, monospace, raw borders. No library. |
| Editorial / magazine | Serif type, asymmetric grid, generous whitespace. No library. |
| Dark tech / hacker | Mono + accent neon, terminal motifs. No library. |
| Aurora / mesh gradients | SVG or layered radial gradients. No library. |
| Kinetic typography | Native CSS + scroll-driven animations, GSAP for hijacks. No library. |
| Apple "Liquid Glass" | Apple-platform-only material. **There is no official `liquid-glass.css`.** Web is an approximation (`backdrop-filter` + layered borders + highlights). Label it as an approximation. |

## Install commands

```bash
npm install @material/web                                  # Material Web (M3)
npm install @fluentui/react-components                     # Fluent UI React v9
npm install @fluentui/web-components @fluentui/tokens       # Fluent Web Components
npm install @carbon/react @carbon/styles                   # IBM Carbon
npm install @radix-ui/themes                               # Radix Themes
npx shadcn@latest init && npx shadcn@latest add button card # shadcn/ui
npm install --save @primer/css                             # Primer CSS
npm install @primer/react-brand                            # Primer Brand
npm install govuk-frontend                                 # GOV.UK Frontend
npm install uswds                                          # USWDS
npm install bootstrap                                      # Bootstrap 5.3
yarn add @atlaskit/css-reset @atlaskit/tokens @atlaskit/button # Atlassian
```

## Canonical sources (read before reinventing)

- **Material**: m3.material.io/develop/web · material-web.dev/theming/material-theming
- **Fluent**: fluent2.microsoft.design · learn.microsoft.com/fluent-ui/web-components
- **Carbon**: carbondesignsystem.com
- **Polaris**: shopify.dev/docs/api/app-home/web-components
- **Atlassian**: atlassian.design · atlassian.design/tokens/design-tokens
- **Primer**: primer.style
- **GOV.UK**: design-system.service.gov.uk
- **USWDS**: designsystem.digital.gov
- **Radix**: radix-ui.com/themes/docs
- **shadcn/ui**: ui.shadcn.com/docs
- **Tailwind**: tailwindcss.com/docs/dark-mode · tailwindcss.com/blog/tailwindcss-v4
