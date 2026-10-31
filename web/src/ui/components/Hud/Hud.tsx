import type { ReactNode } from 'react'
import { cx } from '../../nui/cx'
import './hud.css'

// Arrows and the backspace symbol are drawn in the sans font (the mono font has no glyphs for them).
const SYMBOL = /^[←-⇿⌫]$/

// Keyboard key cap: [E], [ENTER], [SHIFT], [←]. `accent` = the key that does the main thing.
export function Keycap({ children, accent }: { children: ReactNode; accent?: boolean }) {
  const symbol = typeof children === 'string' && SYMBOL.test(children)
  return <kbd className={cx('keycap', accent && 'keycap-accent', symbol && 'keycap-sym')}>{children}</kbd>
}

export interface ControlRow {
  keys: string[]
  label: ReactNode
  dim?: boolean
}

// All keys on one line: [LMB] Select  [N] New. Used by ControlsCard and inside panel footers (OfferBoard).
export function ControlsRow({ rows, className }: { rows: ControlRow[]; className?: string }) {
  return (
    <div className={cx('hud-controls-row', className)}>
      {rows.map((row) => (
        <div key={row.keys.join('+') + String(row.label)} className={cx('hud-control', row.dim && 'dim')}>
          {row.keys.map((key) => (
            <Keycap key={key}>{key}</Keycap>
          ))}
          <span>{row.label}</span>
        </div>
      ))}
    </div>
  )
}

// Controls card in the bottom-right corner, all keys on one line. Replaces GTA instructional buttons
// while a mode is active (editor, placement, minigame). `title` shows a label split off by a hairline.
export function ControlsCard({ rows, title, leaving }: { rows: ControlRow[]; title?: ReactNode; leaving?: boolean }) {
  return (
    <div className={cx('hud-controls', 'animate-fade-up', leaving && 'leaving')}>
      {title && <span className="label hud-controls-title">{title}</span>}
      <ControlsRow rows={rows} />
    </div>
  )
}

// "[E] Use jukebox" prompt, bottom-center. Shown when the player can interact with something.
// Without `keyName` it is plain text, which may hold Keycaps of its own ("Hold [E] to pass the envelope").
// `inline` makes it part of the layout instead of fixed to the bottom-center (stack it with other overlays).
export function Prompt({
  keyName,
  children,
  leaving,
  inline,
}: {
  keyName?: string
  children: ReactNode
  leaving?: boolean
  inline?: boolean
}) {
  return (
    <div className={cx('hud-prompt', !keyName && 'hud-prompt-plain', inline && 'hud-prompt-inline', leaving && 'leaving')}>
      {keyName && <Keycap accent>{keyName}</Keycap>}
      <span>{children}</span>
    </div>
  )
}

// Small floating info card (top-left editor panel, radar readout). A compact Panel without the shadow-heavy header.
export function HudCard({
  title,
  meta,
  children,
  className,
}: {
  title: ReactNode
  meta?: ReactNode
  children?: ReactNode
  className?: string
}) {
  return (
    <div className={cx('hud-card', className)}>
      <div className="hud-card-head">
        <span className="label">{title}</span>
        {meta && <span className="label num hud-card-meta">{meta}</span>}
      </div>
      {children}
    </div>
  )
}
