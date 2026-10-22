# Yecoyz design language

The website looks like the in-game UIs (`yecoyz_radar`, `yecoyz_jukebox`, the minigames): dark zinc panels, hairline borders, one sand accent, and bold uppercase titles. Anything new on the site, and any new in-game UI, should look like it came from the same HUD.

The source of truth is `src/app/globals.css` (`@theme` tokens) and `src/components/ui.tsx` (primitives). If this file and the code disagree, the code wins. Update this file.

## Principles

1. **Dark and flat.** Zinc surfaces stacked by lightness. No gradients on surfaces and no glassmorphism. The only gradients are the faint glows on the page background.
2. **One accent.** Sand `#e8d9b0` marks what matters: primary actions, the active item, the top bar of a panel, the total price. If everything is sand, nothing is.
3. **Hairlines, not shadows.** Structure comes from 1px borders. Shadows only separate floating layers (cards on hover, drawers, popovers).
4. **Loud titles, quiet labels.** Titles are heavy and uppercase. Labels are small, wide-tracked and muted. This pairing is the signature look.
5. **Compact and legible.** Small radii, tight padding, tabular numbers. It should feel like a HUD, not a landing-page template.

## Color

Use the tokens. Never hard-code a hex in a component, except the chart color noted below.

| Token | Value | Use |
|---|---|---|
| `bg` | `#0e0e10` | Page background |
| `panel` | `#18181b` | Cards, panels, drawers, navbar |
| `panel-2` | `#202024` | Inputs, ghost buttons, inset cards, hover fill |
| `panel-3` | `#29292f` | Image placeholders, inline code, neutral badges |
| `line` | `#27272a` | Default 1px border and dividers |
| `line-strong` | `#3f3f46` | Hover border, outer edge of floating layers |
| `fg` | `#f4f4f5` | Primary text |
| `muted` | `#a1a1aa` | Body copy, labels |
| `dim` | `#71717a` | Placeholders, fine print, strike-through prices |
| `accent` | `#e8d9b0` | Sand accent |
| `accent-strong` | `#f5ecd2` | Accent hover |
| `accent-ink` | `#18181b` | Text on a sand background |
| `accent-soft` | sand at 10% | Tinted backgrounds, blockquotes |
| `success` | `#4ade80` | Free, applied, completed |
| `warn` | `#fb923c` | Warnings (orange on purpose; amber looked too close to sand) |
| `danger` | `#ef4444` | Sale, destructive, errors |

Rules:

- **Text on sand is always `accent-ink`**, never white.
- **Body text is `muted`, headings and values are `fg`.** Don't use pure white.
- **Status colors carry meaning**: green is free or success, red is sale or destructive, orange is warning. Don't use them as decoration.
- **Per-script accent**: each script has one of `accent`, `danger`, `success` or `warn` (`accentVar` in `src/lib/format.ts`). It colors the 3px top bar, the placeholder art glow and the card hover.
- **Charts** use `#b98c2e`, a darker sand. Plain sand fails the contrast and lightness checks on dark surfaces. Run the dataviz validator before adding chart colors.

## Typography

- **Sans: Inter**, mono: the project mono face (`font-mono`).
- **`title`**: weight 800, uppercase, `0.04em` tracking. Used for panel titles, card names, drawer headings. Size `0.95rem` for card titles, `text-2xl` to `text-3xl` for section headings.
- **`label`**: `0.6875rem`, weight 600, uppercase, `0.14em` tracking, `muted`. Used for categories, field names, "Price", "Subtotal", counts.
- **`plate`**: mono, weight 700, uppercase, `0.12em` tracking. Used for resource names (`yecoyz_duty`), codes and plate-like values.
- **Buttons**: `text-xs`, weight 700, uppercase, `0.12em` tracking.
- **Numbers**: always `tabular-nums`. Big stats are `text-4xl font-extrabold`.
- **Body**: `text-sm` to `text-lg` in `muted`. Docs prose is `0.95rem` with `1.75` line height.
- Don't use italics or light weights. Keep sentence case for body copy and uppercase only for titles, labels and buttons.

## Shape, spacing and elevation

- **Radius**: panels and cards 8px (`--radius-panel`), buttons, inputs and insets `rounded-md`, badges 4px. Nothing is pill-shaped. Icon tiles are `rounded-md`, not circles.
- **Borders**: 1px `line` by default. Raise to `line-strong` on hover or for floating layers.
- **Panel padding**: `p-4` (cards) or `p-5` (drawer). Gaps between stacked items: `space-y-2` for lists, `gap-1.5` for badges.
- **Page width**: `max-w-7xl`, `px-4 sm:px-6`. Sections are separated by about `pt-24`.
- **Elevation**: resting cards have none. Hover lifts a card (`-translate-y-1`) and adds a deep, soft black shadow. Drawers and modals get the same black shadow and a `bg-black/60` backdrop with a 2px blur.
- **Motion**: 150 to 200ms for color and border changes, 300ms ease-out for the drawer, 500ms for image zoom on hover (`scale-[1.04]`). Buttons press down 1px on `:active`. Don't add bounces or long animations.

## Components

### Panel (`Panel` in `ui.tsx`)
The core surface. `panel` background, 1px `line` border, 8px radius, a **3px colored bar across the top** and an optional header row: uppercase `title` on the left, muted `label` meta on the right. Use `Inset` (`panel-2` at 70%, 1px border, `rounded-md`) for a card inside a panel, like the CURRENT / MAX split in the radar.

### Buttons
All buttons share the same base: 40px high, uppercase, wide-tracked.

| Variant | Look | Use |
|---|---|---|
| `primary` | Sand fill, ink text, faint sand ring and glow | The one main action per view (Add to cart, Checkout, Get it on GitHub) |
| `ghost` | `panel-2` fill, 1px `line` border | Secondary actions (Apply coupon) |
| `outline` | 1px `line-strong` border, turns sand on hover | Tertiary actions |
| `danger` | Red fill, white text | Destructive actions |

Only one `primary` per view. Full-width checkout buttons are 44px high (`h-11`).

### Badges
4px radius, `0.625rem`, uppercase, `0.12em` tracking. Neutral (framework names) uses `panel-3` with a `line-strong` border. Colored badges use the accent at 40% for the border and 12% for the fill. Standard ones: **New** (sand), **Free** (green), **Sale** (red).

### Product card
Panel with the 3px accent bar, a 16:9 image with a `border-b`, badges top-left over the image, then a `title` + category `label` row, a two-line muted description, framework badges and a footer split by a `border-t`: price on the left, a 36px arrow tile on the right. The arrow tile is vertically centered with the price (`items-center`). On hover it fills with the card's accent and the arrow nudges right.

### Prices
`Price`: `text-xl` (card) or `text-4xl` (product page), `font-extrabold`, tabular. Sale shows the new price in `fg` and the old price small, `dim` and struck through. Free scripts show **Free** in `success` green and link to GitHub instead of a buy button.

### Cart drawer
Slides in **from the right**, `max-w-[420px]`, `panel` background, `border-l` in `line-strong`, 3px sand bar on top, a 64px header with the title and an item count, a 36px square close button. Items are `Inset` rows with a 56px thumbnail, bold name, mono resource name and price. The footer holds the coupon field, subtotal/tax/total rows (total in sand, `text-lg font-extrabold`) and the checkout button. Esc and the backdrop close it.

### Section headings (`SectionHeading`)
Eyebrow `label` in sand with a 24px sand rule before it, then an uppercase `title`, then one muted line.

### Docs prose
Headings: h2 uppercase with a top hairline, h3 bold. Links are sand and underlined. Inline code sits in a `panel-3` chip. Code blocks are `#111113` with a small uppercase language label in the corner. Callouts use a 3px left border and a 9% tint of their color: note and tip use sand or green, warning uses orange, caution uses red.

### Backgrounds
Page: `bg` with a faint sand glow top-left and a fainter red glow top-right. The `grid-bg` utility (48px grid at 3.5% white, masked to fade out toward the edges) is for hero and placeholder art only.

### Logo
`yecoyz-black-sand.png`: black and sand. In the navbar it sits in a 32px rounded square with a `line-strong` border, next to the wordmark `YECOYZ` followed by a sand period.

## Imagery

- Script thumbnails and videos should show the **new sand UI**. The Appearance and Characters ones still show the old blue UI and need to be re-recorded.
- Placeholder art (when there is no thumbnail) is the grid, a glow in the script's accent color, the name as a `title` and the resource name as a mono `plate`.
- Use `next/image`. New external hosts go in `next.config.ts` `remotePatterns`.

## Do and don't

**Do**
- Reuse `Panel`, `Inset`, `Badge`, `Button`, `ButtonLink`, `Stat` and `SectionHeading` before writing new markup.
- Put the top bar on every panel or card, in the accent that fits.
- Use `label` for anything that names a field and `title` for anything that names a thing.
- Keep one sand element per area that draws the eye.

**Don't**
- Don't add new colors or hard-coded hex values. Add a token first.
- Don't use blue. The old blue look is retired.
- Don't use pill buttons, large radii, drop shadows on resting elements, or gradients on surfaces.
- Don't use sentence-case buttons or lowercase titles.
- Don't put colored text on a colored background, and don't use sand text on light surfaces.
- Don't show a number without `tabular-nums`.

## Using this for the in-game UIs

The same rules apply in NUI: `#18181b` panel, `#27272a` hairline border, 8px radius, a 3px top bar in the accent, uppercase 800-weight titles, muted wide-tracked labels, mono uppercase for plates and codes, and sand `#e8d9b0` as the single accent. Keep the website and the in-game UIs in sync so the store previews match what players see.
