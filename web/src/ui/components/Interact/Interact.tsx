import type { ReactNode } from 'react'
import { cx } from '../../nui/cx'
import { Keycap } from '../Hud/Hud'
import './interact.css'

export interface InteractOption {
  id: string | number
  label: ReactNode
  icon?: ReactNode
}

// An interaction menu pinned to a spot in the world (a prop, a door handle). A sand marker sits on the spot and the
// card hangs beside it. The selected option carries the key, the player scrolls to move it through the others.
// `x` and `y` are the screen position of the spot as a fraction (0-1); update them every frame from the game.
// The card flips to the left side of the marker near the right edge. Show it without NUI focus.
export function Interact({
  options,
  index,
  keyName,
  scrollLabel = 'Scroll',
  x,
  y,
  rows = 5,
  leaving,
}: {
  options: InteractOption[]
  index: number
  keyName: string
  scrollLabel?: ReactNode
  x: number
  y: number
  rows?: number
  leaving?: boolean
}) {
  const many = options.length > 1
  // A window of `rows` options that keeps the selected one in view.
  const start = Math.min(Math.max(0, index - Math.floor(rows / 2)), Math.max(0, options.length - rows))
  const visible = options.slice(start, start + rows)

  return (
    <div
      className={cx('interact', x > 0.72 && 'interact-flip', leaving && 'interact-leaving')}
      style={{ left: `${x * 100}%`, top: `${y * 100}%` }}
    >
      <span className="interact-marker" />
      <span className="interact-line" />
      <div className="interact-card">
        <ul className="interact-list">
          {visible.map((option, i) => {
            const active = start + i === index
            return (
              <li key={option.id} className={cx('interact-option', active && 'active')}>
                {option.icon && <span className="interact-icon">{option.icon}</span>}
                <span className="interact-label">{option.label}</span>
                {active && <Keycap accent>{keyName}</Keycap>}
              </li>
            )
          })}
        </ul>
        {many && (
          <div className="interact-foot">
            <span className="label">{scrollLabel}</span>
            <span className="label num interact-count">
              {index + 1} / {options.length}
            </span>
          </div>
        )}
      </div>
    </div>
  )
}
