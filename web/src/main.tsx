import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './ui/styles/index.css'
import App from './App'
import { isBrowser } from './ui/nui/env'
import { debugNui } from './ui/nui/useNuiEvent'

// In a normal browser there is no Lua, so show sample data.
if (isBrowser) {
  const options = [
    { id: 1, label: 'Open door', icon: 'door-open' },
    { id: 2, label: 'Lock door', icon: 'lock' },
    { id: 3, label: 'Knock', icon: 'hand' },
  ]
  debugNui('notify', { message: 'Your phone is ringing.', type: 'info', duration: 8000 }, 100)
  debugNui('notify', { title: 'Bank', message: 'Transfer received: $1,500', type: 'success', duration: 8000 }, 400)
  debugNui('notify', { message: 'You dropped the package.', type: 'error', duration: 8000 }, 700)
  debugNui('interact:show', { target: 1, options, index: 0, key: 'E', scrollLabel: 'Scroll', x: 0.5, y: 0.5 }, 200)
  debugNui('interact:show', { target: 1, options, index: 1, key: 'E', scrollLabel: 'Scroll', x: 0.5, y: 0.5 }, 1500)
  debugNui(
    'controls:set',
    {
      title: 'Editor',
      rows: [
        { keys: ['LMB'], label: 'Select' },
        { keys: ['N'], label: 'New' },
        { keys: ['Del'], label: 'Delete', dim: true },
      ],
    },
    300,
  )
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
