import assert from 'node:assert/strict'
import test from 'node:test'

import { ECHO_MOODS } from '../src/components/moodEmotionModel.ts'
import { moodOrbitTextPose, moodTickAngle } from '../src/components/moodSwipeModel.ts'
import {
  DEFAULT_ECHO_SELECTOR_INDEX,
  ECHO_SELECTOR_MOOD_IDS,
  ECHO_SELECTOR_MOODS,
  getMoodDescriptorWords,
  moodPolarity,
  polarityFromValence,
} from '../src/components/moodTaxonomyModel.ts'

test('first-page selector is an explicit seven-level subset while the registry keeps all fifteen moods', () => {
  const registryIds = ECHO_MOODS.map(({ id }) => id)

  assert.equal(registryIds.length, 15)
  assert.deepEqual(ECHO_SELECTOR_MOOD_IDS, [
    'joyful',
    'bright',
    'okay',
    'calm',
    'heavy',
    'low',
    'very-low',
  ])
  assert.deepEqual(ECHO_SELECTOR_MOODS.map(({ id }) => id), ECHO_SELECTOR_MOOD_IDS)
  assert.equal(ECHO_SELECTOR_MOODS.length, 7)
  assert.equal(DEFAULT_ECHO_SELECTOR_INDEX, 3)
  assert.equal(ECHO_SELECTOR_MOODS[DEFAULT_ECHO_SELECTOR_INDEX]?.id, 'calm')
  assert.equal(Object.isFrozen(ECHO_SELECTOR_MOOD_IDS), true)
  assert.equal(Object.isFrozen(ECHO_SELECTOR_MOODS), true)
  assert.ok(registryIds.includes('angry'))
  assert.ok(!ECHO_SELECTOR_MOOD_IDS.includes('angry'))
})

test('default rotating poses place three negative levels left, calm at focus, and three positive levels right', () => {
  for (const [index, mood] of ECHO_SELECTOR_MOODS.entries()) {
    const pose = moodOrbitTextPose(
      index,
      DEFAULT_ECHO_SELECTOR_INDEX,
      ECHO_SELECTOR_MOODS.length,
      true,
    )
    const x = Math.sin(pose.angle * Math.PI / 180)

    if (mood.valence < 0) {
      assert.ok(x < -0.01, `${mood.id} must render left of the vertical boundary`)
    } else if (mood.valence > 0) {
      assert.ok(x > 0.01, `${mood.id} must render right of the vertical boundary`)
    } else {
      assert.equal(mood.id, 'calm')
      assert.equal(pose.angle, 180)
      assert.equal(pose.distance, 0)
    }
  }
})

test('selector labels and ticks share the same continuously rotating angle', () => {
  const before = ECHO_SELECTOR_MOODS.map((_, index) => (
    moodOrbitTextPose(index, DEFAULT_ECHO_SELECTOR_INDEX, ECHO_SELECTOR_MOODS.length, true)
  ))
  const after = ECHO_SELECTOR_MOODS.map((_, index) => (
    moodOrbitTextPose(index, DEFAULT_ECHO_SELECTOR_INDEX + 0.5, ECHO_SELECTOR_MOODS.length, true)
  ))
  const expectedDelta = -0.5 * (360 / ECHO_SELECTOR_MOODS.length)

  for (let index = 0; index < ECHO_SELECTOR_MOODS.length; index++) {
    assert.ok(Math.abs(after[index].angle - before[index].angle - expectedDelta) < 1e-9)
    assert.equal(
      after[index].angle,
      moodTickAngle(index, DEFAULT_ECHO_SELECTOR_INDEX + 0.5, ECHO_SELECTOR_MOODS.length),
    )
  }
})

test('polarity uses a discrete emotion when present and keeps valence-only records compatible', () => {
  assert.equal(polarityFromValence(-0.01), 'negative')
  assert.equal(polarityFromValence(0), 'neutral')
  assert.equal(polarityFromValence(0.01), 'positive')

  assert.equal(moodPolarity({ valence: -2 }), 'negative')
  assert.equal(moodPolarity({ valence: 0 }), 'neutral')
  assert.equal(moodPolarity({ valence: 2 }), 'positive')
  assert.equal(moodPolarity({ valence: 3, emotionId: 'angry' }), 'negative')
  assert.equal(moodPolarity({ valence: -3, emotionId: 'joyful' }), 'positive')
})

test('valence-only descriptor rings use distinct twelve-word vocabularies by polarity', () => {
  const negative = getMoodDescriptorWords({ valence: -1 })
  const neutral = getMoodDescriptorWords({ valence: 0 })
  const positive = getMoodDescriptorWords({ valence: 1 })

  assert.equal(negative.length, 12)
  assert.equal(neutral.length, 12)
  assert.equal(positive.length, 12)
  assert.notDeepEqual(negative, positive)
  assert.notDeepEqual(negative, neutral)
  assert.notDeepEqual(neutral, positive)
  assert.ok(negative.includes('失落'))
  assert.ok(neutral.includes('平静'))
  assert.ok(positive.includes('喜悦'))
})

test('all fifteen discrete emotions can refine the second-page descriptor ring', () => {
  for (const mood of ECHO_MOODS) {
    const words = getMoodDescriptorWords({ valence: mood.valence, emotionId: mood.id })
    assert.equal(words.length, 12, mood.id)
    assert.equal(new Set(words).size, words.length, mood.id)
    assert.equal(Object.isFrozen(words), true, mood.id)
    assert.strictEqual(
      words,
      getMoodDescriptorWords({ valence: mood.valence, emotionId: mood.id }),
      mood.id,
    )
  }

  const angry = getMoodDescriptorWords({ valence: -2, emotionId: 'angry' })
  const sad = getMoodDescriptorWords({ valence: -3, emotionId: 'sad' })
  const joyful = getMoodDescriptorWords({ valence: 3, emotionId: 'joyful' })

  assert.ok(angry.includes('恼火'))
  assert.ok(sad.includes('心碎'))
  assert.ok(joyful.includes('兴奋'))
  assert.notDeepEqual(angry, sad)
  assert.notDeepEqual(angry, joyful)
})
