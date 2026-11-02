import assert from 'node:assert/strict'
import test from 'node:test'
import { isInteractiveRotaryTarget } from '../src/lib/useRotary.ts'

test('rotary gestures leave buttons in control of their pointer clicks', () => {
  const button = {
    closest(selector: string) {
      return selector.includes('button') ? {} : null
    },
  }
  const surface = { closest: () => null }

  assert.equal(isInteractiveRotaryTarget(button as unknown as EventTarget), true)
  assert.equal(isInteractiveRotaryTarget(surface as unknown as EventTarget), false)
})
