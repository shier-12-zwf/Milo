import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const component = readFileSync(new URL('../src/components/MoodExpression.tsx', import.meta.url), 'utf8')
const orb = readFileSync(new URL('../src/components/MoodOrb.tsx', import.meta.url), 'utf8')
const css = readFileSync(new URL('../src/index.css', import.meta.url), 'utf8')

test('expression overlay keeps the sphere geometry separate from its safe outer accents', () => {
  assert.match(component, /viewBox="-24 -24 248 248"/)
  assert.match(component, /aria-hidden="true"/)
  assert.match(component, /mood-expression__\$\{name\}/)
  assert.match(component, /name="face"/)
  assert.match(component, /name="hands"/)
  assert.match(component, /name="accents"/)
  assert.match(component, /mood-expression--exit/)
  assert.match(orb, /<MoodExpression/)
  assert.match(orb, /leavingMood/)
})

test('expression styling is crisp, pointer inert, motion-safe, and never elliptically squashes the orb', () => {
  assert.match(css, /\.mood-expression\s*\{[^}]*pointer-events:\s*none/s)
  assert.match(css, /\.mood-stroke\s*\{[^}]*vector-effect:\s*non-scaling-stroke/s)
  assert.match(css, /@media \(prefers-reduced-motion: reduce\)[\s\S]*\.mood-expression/)

  const bounce = css.match(/@keyframes echo-orb-drop\s*\{([\s\S]*?)\n\}/)?.[1] ?? ''
  assert.doesNotMatch(bounce, /scale\([^)]*,/)
})

test('expression styling matches the readable navy hand-drawn reference treatment', () => {
  assert.match(css, /filter:\s*brightness\(1\.08\) saturate\(1\.02\) contrast\(1\.04\)/)
  assert.match(css, /\.mood-stroke\s*\{[^}]*color:\s*#071a4a/s)
  assert.match(css, /\.mood-stroke\s*\{[^}]*stroke-width:\s*3\.2/s)
  assert.match(css, /\.mood-stroke--hand\s*\{[^}]*stroke-width:\s*3\.05/s)
  assert.match(css, /\.mood-expression__face\s*\{[^}]*scale:\s*1\.2/s)
  assert.match(css, /\.mood-expression__hands\s*\{[^}]*scale:\s*1\.12/s)
  assert.match(css, /\.mood-stroke--accent\s*\{[^}]*stroke-width:\s*2\.45/s)
})
