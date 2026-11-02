import assert from 'node:assert/strict'
import test from 'node:test'
import { triggerTapHaptic } from '../src/lib/haptics.ts'

test('tap haptics request ten milliseconds and fall back safely', () => {
  let received: number | number[] | undefined
  const supported = {
    vibrate(pattern: number | number[]) {
      received = pattern
      return true
    },
  }

  assert.equal(triggerTapHaptic(supported), true)
  assert.equal(received, 10)
  assert.equal(triggerTapHaptic({}), false)
  assert.equal(triggerTapHaptic({ vibrate: () => { throw new Error('blocked') } }), false)
})
