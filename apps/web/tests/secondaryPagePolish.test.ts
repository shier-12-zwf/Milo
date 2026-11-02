import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const home = readFileSync(new URL('../src/pages/Home.tsx', import.meta.url), 'utf8')
const pastTime = readFileSync(new URL('../src/pages/PastTime.tsx', import.meta.url), 'utf8')
const css = readFileSync(new URL('../src/index.css', import.meta.url), 'utf8')

test('descriptor words expose pressed state and selection feedback', () => {
  assert.match(home, /<button[\s\S]*className=\{cls\}[\s\S]*aria-pressed=\{labels\.includes\(w\)\}/)
  assert.match(home, /triggerTapHaptic\(\)/)
})

test('time presets expose pressed state and selection feedback', () => {
  assert.match(pastTime, /aria-pressed=\{picked === p && !custom\.trim\(\)\}/)
  assert.match(pastTime, /triggerTapHaptic\(\)/)
})

test('both home steps reuse the latest dark-glass action dimensions', () => {
  assert.match(home, /const primaryActionClass = echoVoid \? 'btn btn-primary echo-confirm' : 'btn btn-primary'/)
  assert.equal(home.match(/className=\{primaryActionClass\}/g)?.length, 2)
  assert.match(css, /\.screen--echo-void \.echo-confirm\s*\{[^}]*width:\s*min\(52vw, 260px\);[^}]*min-height:\s*50px/s)
})

test('secondary copy is readable while the focused word stays brightest', () => {
  assert.match(css, /--ink-dim:\s*rgba\(234, 230, 255, 0\.72\)/)
  assert.match(css, /--ink-faint:\s*rgba\(234, 230, 255, 0\.60\)/)
  assert.match(css, /\.screen--echo-void \.eyebrow\s*\{[^}]*color:\s*rgba\(205, 208, 218, 0\.68\)/s)
  assert.match(css, /\.screen--echo-void \.back-link\s*\{[^}]*color:\s*rgba\(205, 208, 218, 0\.72\)/s)
  assert.match(css, /\.word-item\.focus\s*\{[^}]*color:\s*#fff/s)
})

test('pressed controls change color and move with tactile restraint', () => {
  assert.match(css, /\.word-item:active\s*\{[^}]*color:\s*var\(--accent-soft\);[^}]*scale:\s*0\.94/s)
  assert.match(css, /\.chip\.on\s*\{[^}]*color:\s*var\(--accent-soft\)/s)
  assert.match(css, /\.chip\.on:hover\s*\{[^}]*color:\s*var\(--accent-soft\)/s)
  assert.match(css, /\.back-link:active\s*\{[^}]*color:\s*var\(--accent-soft\);[^}]*scale:\s*0\.97/s)
})

test('the custom time field uses transparent shimmering glass instead of browser white', () => {
  assert.match(pastTime, /className="note-input past-time-input"/)
  assert.match(css, /(?:^|\n)\.note-input\s*\{[^}]*background:[^}]*rgba\(8, 7, 23, 0\.58\)/s)
  assert.match(css, /@keyframes note-shimmer\s*\{/)
  assert.match(css, /\.note-input:focus\s*\{[^}]*border-color:/s)
})

test('page entry motion keeps buttons and options opaque from the first frame', () => {
  const screenIn = css.match(/@keyframes screen-in\s*\{([\s\S]*?)\n\}/)?.[1] ?? ''

  assert.match(screenIn, /from\s*\{\s*transform:\s*translateY\(12px\)/)
  assert.doesNotMatch(screenIn, /opacity|filter/)
})
