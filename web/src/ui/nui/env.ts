// True in a normal browser (npm run dev), false inside the FiveM NUI frame.
export const isBrowser = typeof window !== 'undefined' && !(window as { invokeNative?: unknown }).invokeNative

// The resource name, so the same code works in every script. Falls back to `fallback` in the browser.
export function resourceName(fallback = 'yecoyz_resource'): string {
  const fn = (window as { GetParentResourceName?: () => string }).GetParentResourceName
  return typeof fn === 'function' ? fn() : fallback
}
