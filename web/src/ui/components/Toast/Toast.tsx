import type { ReactNode } from 'react'
import { cx } from '../../nui/cx'
import { Panel, type Tone } from '../Panel/Panel'
import './toast.css'

// A short message in a small panel. The top bar shows the meaning: accent = info, success, warn, danger.
// `title` is an optional small label above the message.
export function Toast({
  tone = 'accent',
  title,
  leaving,
  children,
}: {
  tone?: Tone
  title?: ReactNode
  leaving?: boolean
  children: ReactNode
}) {
  return (
    <Panel tone={tone} className={cx('toast', leaving && 'toast-leaving')}>
      <div className="toast-body">
        {title && <span className="label toast-title">{title}</span>}
        {children}
      </div>
    </Panel>
  )
}

// Column of Toasts, fixed at the top-centre of the screen. Newest at the bottom. Remove each Toast after a few
// seconds (set `leaving` for the close animation first).
export function ToastStack({ children }: { children: ReactNode }) {
  return <div className="toast-stack">{children}</div>
}
