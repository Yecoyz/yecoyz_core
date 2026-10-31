import { useEffect, useState } from 'react'

const LEAVE_MS = 150

// Keeps a closed part mounted for its close animation. Returns [value to render, leaving].
// const [dialog, leaving] = usePresence(state.dialog); {dialog && <Dialog leaving={leaving} />}
export function usePresence<T>(value: T | null | undefined | false, ms = LEAVE_MS): [T | null, boolean] {
  const [last, setLast] = useState<T | null>(value || null)

  useEffect(() => {
    if (value) {
      setLast(value)
      return undefined
    }
    const timer = setTimeout(() => setLast(null), ms)
    return () => clearTimeout(timer)
  }, [value, ms])

  return [value || last, !value && !!last]
}
