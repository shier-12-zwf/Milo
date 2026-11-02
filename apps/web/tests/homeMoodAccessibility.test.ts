import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const home = readFileSync(new URL('../src/pages/Home.tsx', import.meta.url), 'utf8')

test('echo mood chooser exposes slider semantics and keyboard controls', () => {
  assert.match(home, /role=\{echoVoid \? 'slider'/)
  assert.match(home, /tabIndex=\{echoVoid \? 0/)
  assert.match(home, /aria-label=\{echoVoid \? '沿圆环旋转切换此刻的感受'/)
  assert.match(home, /aria-valuetext=\{echoVoid \? echoMood\.label/)
  assert.match(home, /event\.key === 'ArrowLeft'/)
  assert.match(home, /event\.key === 'ArrowRight'/)
})
