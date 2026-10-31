import type { HTMLAttributes, ReactNode } from 'react'
import { cx } from '../../nui/cx'
import './panel.css'

export type Tone = 'accent' | 'danger' | 'success' | 'warn'

type DivProps = HTMLAttributes<HTMLDivElement>

// The core surface: zinc panel, hairline border, 8px radius and a 3px bar across the top in `tone`.
export function Panel({ tone = 'accent', className, ...props }: DivProps & { tone?: Tone }) {
  return <div className={cx('panel', tone !== 'accent' && `panel-${tone}`, className)} {...props} />
}

// Header row: icon tile + uppercase title on the left, label meta and icon buttons on the right.
// A string `meta` is rendered as a tabular label ("2 / 4 SLOTS").
export function PanelHeader({
  title,
  meta,
  icon,
  large,
  className,
  children,
  ...props
}: Omit<DivProps, 'title'> & { title: ReactNode; meta?: ReactNode; icon?: ReactNode; large?: boolean }) {
  return (
    <div className={cx('panel-header', large && 'panel-header-lg', className)} {...props}>
      <div className="panel-header-left">
        {icon}
        <h2 className="title">{title}</h2>
      </div>
      {(meta || children) && (
        <div className="panel-header-meta">
          {typeof meta === 'string' ? <span className="label num">{meta}</span> : meta}
          {children}
        </div>
      )}
    </div>
  )
}

// Strip under the header for filters, tabs or a segmented control.
export function PanelControls({ className, ...props }: DivProps) {
  return <div className={cx('panel-controls', className)} {...props} />
}

// Content area. `scroll` makes it fill the remaining height and scroll.
export function PanelBody({ scroll, className, ...props }: DivProps & { scroll?: boolean }) {
  return <div className={cx('panel-body', scroll && 'panel-body-scroll', className)} {...props} />
}

export function PanelFooter({ className, ...props }: DivProps) {
  return <div className={cx('panel-footer', className)} {...props} />
}
