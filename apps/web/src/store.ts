import { useCallback, useSyncExternalStore } from 'react'
import type { Entry } from './types'

const KEY = 'echoes.entries.v1'

let cache: Entry[] | null = null
const listeners = new Set<() => void>()

function read(): Entry[] {
  if (cache) return cache
  try {
    cache = JSON.parse(localStorage.getItem(KEY) ?? '[]') as Entry[]
  } catch {
    cache = []
  }
  return cache
}

function write(entries: Entry[]) {
  cache = entries
  localStorage.setItem(KEY, JSON.stringify(entries))
  listeners.forEach((l) => l())
}

export function addEntry(entry: Entry) {
  write([entry, ...read()])
}

export function updateEntry(id: string, patch: Partial<Entry>) {
  write(read().map((e) => (e.id === id ? { ...e, ...patch } : e)))
}

export function removeEntry(id: string) {
  write(read().filter((e) => e.id !== id))
}

export function getEntry(id: string): Entry | undefined {
  return read().find((e) => e.id === id)
}

export function useEntries(): Entry[] {
  return useSyncExternalStore(
    useCallback((cb) => {
      listeners.add(cb)
      return () => listeners.delete(cb)
    }, []),
    read,
  )
}

export function uid(): string {
  return Math.random().toString(36).slice(2, 10) + Date.now().toString(36)
}
