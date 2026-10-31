// Joins class names and drops falsy ones: cx('btn', active && 'active')
export const cx = (...parts: (string | false | null | undefined | 0)[]) => parts.filter(Boolean).join(' ')
