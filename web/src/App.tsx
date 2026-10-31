import { useCallback, useEffect, useState } from 'react'
import { icons } from 'lucide-react'
import { ControlsCard, type ControlRow } from './ui/components/Hud/Hud'
import { Interact } from './ui/components/Interact/Interact'
import { Notification, NotificationStack } from './ui/components/Notification/Notification'
import type { Tone } from './ui/components/Panel/Panel'
import { fetchNui } from './ui/nui/fetchNui'
import { useNuiEvent } from './ui/nui/useNuiEvent'
import { usePresence } from './ui/nui/usePresence'

const LEAVE_MS = 150
const MAX_NOTES = 5

// Lua notification types -> the tone, and the icon a notification gets when it has no icon of its own.
const tones: Record<string, Tone> = { info: 'accent', success: 'success', error: 'danger', warning: 'warn' }
const typeIcons: Record<string, string> = { info: 'info', success: 'circle-check', error: 'circle-x', warning: 'triangle-alert' }

// 'door-open' -> the lucide DoorOpen icon. Unknown names show no icon.
function icon(name?: string) {
  if (!name) return undefined
  const pascal = name.replace(/(^|[-_ ])(\w)/g, (_, __, c: string) => c.toUpperCase())
  const Icon = icons[pascal as keyof typeof icons]
  return Icon ? <Icon size={15} strokeWidth={2.25} /> : undefined
}

interface NotifyData {
  id: number
  message: string
  type?: string
  title?: string
  icon?: string
  duration?: number
}

interface Note extends NotifyData {
  leaving?: boolean
}

function Notifications() {
  const [notes, setNotes] = useState<Note[]>([])

  const remove = useCallback((id: number) => {
    setNotes((all) => all.map((n) => (n.id === id ? { ...n, leaving: true } : n)))
    setTimeout(() => setNotes((all) => all.filter((n) => n.id !== id)), LEAVE_MS)
  }, [])

  useNuiEvent<NotifyData>('notify', (data) => {
    setNotes((all) => [...all, data].slice(-MAX_NOTES))
    setTimeout(() => remove(data.id), data.duration || 5000)
  })

  return (
    <NotificationStack>
      {notes.map((n) => {
        const type = n.type && tones[n.type] ? n.type : 'info'
        return (
          <Notification key={n.id} tone={tones[type]} title={n.title} icon={icon(n.icon || typeIcons[type])} leaving={n.leaving}>
            {n.message}
          </Notification>
        )
      })}
    </NotificationStack>
  )
}

interface InteractData {
  target: number
  options: { id: number; label: string; icon?: string }[]
  index: number
  key: string
  scrollLabel?: string
  x: number
  y: number
}

function Interaction() {
  const [state, setState] = useState<InteractData | null>(null)
  const [shown, leaving] = usePresence(state)

  useNuiEvent<InteractData>('interact:show', setState)
  // The anchor moves every frame: only x and y change.
  useNuiEvent<{ x: number; y: number }>('interact:move', (pos) => setState((s) => (s ? { ...s, ...pos } : s)))
  useNuiEvent('interact:hide', () => setState(null))

  if (!shown) return null

  return (
    <Interact
      key={shown.target}
      options={shown.options.map((o) => ({ id: o.id, label: o.label, icon: icon(o.icon) }))}
      index={Math.min(shown.index, shown.options.length) - 1} // Lua counts from 1, the component from 0
      keyName={shown.key}
      scrollLabel={shown.scrollLabel}
      x={shown.x}
      y={shown.y}
      leaving={leaving}
    />
  )
}

interface ControlsData {
  title?: string
  rows: ControlRow[]
}

function Controls() {
  const [state, setState] = useState<ControlsData | null>(null)
  const [shown, leaving] = usePresence(state)

  useNuiEvent<ControlsData>('controls:set', setState)
  useNuiEvent('controls:hide', () => setState(null))

  if (!shown) return null
  return <ControlsCard title={shown.title} rows={shown.rows} leaving={leaving} />
}

export default function App() {
  // Lua queues messages until the page says it is ready.
  useEffect(() => {
    fetchNui('ready')
  }, [])

  return (
    <>
      <Notifications />
      <Interaction />
      <Controls />
    </>
  )
}
