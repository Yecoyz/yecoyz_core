import type { ReactNode } from 'react'
import { cx } from '../../nui/cx'
import type { Tone } from '../Panel/Panel'
import './notification.css'

// A small notification: a tinted icon tile on the left, an optional title and the message. The tone colours the tile
// (accent = info, success, warn, danger). It is only as wide as its text, up to 320px.
export function Notification({
  tone = 'accent',
  title,
  icon,
  leaving,
  children,
}: {
  tone?: Tone
  title?: ReactNode
  icon?: ReactNode
  leaving?: boolean
  children: ReactNode
}) {
  return (
    <div className={cx('notification', `notification-${tone}`, leaving && 'notification-leaving')}>
      {icon && <span className="notification-icon">{icon}</span>}
      <div className="notification-text">
        {title && <span className="notification-title">{title}</span>}
        <span className={cx('notification-message', !title && 'notification-message-solo')}>{children}</span>
      </div>
    </div>
  )
}

// Column of Notifications fixed to the top-right corner. Newest at the bottom. Remove each one after a few seconds
// (set `leaving` for the close animation first).
export function NotificationStack({ children }: { children: ReactNode }) {
  return <div className="notification-stack">{children}</div>
}
