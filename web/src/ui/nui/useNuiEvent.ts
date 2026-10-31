import { useEffect, useRef } from 'react'

interface NuiMessage<T> {
  action: string
  data: T
}

// Runs `handler` when client Lua sends SendNUIMessage({ action = action, data = ... }).
export function useNuiEvent<T = unknown>(action: string, handler: (data: T) => void) {
  const saved = useRef(handler)

  useEffect(() => {
    saved.current = handler
  }, [handler])

  useEffect(() => {
    const listener = (event: MessageEvent<NuiMessage<T>>) => {
      if (event.data?.action === action) saved.current(event.data.data)
    }
    window.addEventListener('message', listener)
    return () => window.removeEventListener('message', listener)
  }, [action])
}

// Browser only: fake a Lua message, e.g. debugNui('open', { ... }) in main.tsx.
export function debugNui<T>(action: string, data: T, delay = 0) {
  setTimeout(() => window.dispatchEvent(new MessageEvent('message', { data: { action, data } })), delay)
}
