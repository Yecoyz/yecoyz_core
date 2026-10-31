import { isBrowser, resourceName } from './env'

type Mock = (data: unknown) => unknown

const mocks: Record<string, Mock> = {}

// Register browser responses so the UI can be built without the game: mockNui('getData', () => ({ ... })).
export function mockNui(event: string, response: Mock) {
  mocks[event] = response
}

// POST to a RegisterNUICallback in client Lua and return its cb(...) value.
// In the browser it returns the registered mock (or {}), so nothing throws.
export async function fetchNui<T = unknown>(event: string, data: unknown = {}): Promise<T> {
  if (isBrowser) return (mocks[event]?.(data) ?? {}) as T

  const response = await fetch(`https://${resourceName()}/${event}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data),
  })
  return response.json()
}
