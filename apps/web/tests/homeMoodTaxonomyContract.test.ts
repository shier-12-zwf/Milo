import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const home = readFileSync(new URL('../src/pages/Home.tsx', import.meta.url), 'utf8')
const carousel = readFileSync(new URL('../src/components/MoodOrbitCarousel.tsx', import.meta.url), 'utf8')
const css = readFileSync(new URL('../src/index.css', import.meta.url), 'utf8')
const types = readFileSync(new URL('../src/types.ts', import.meta.url), 'utf8')
const swipe = readFileSync(new URL('../src/lib/useMoodSwipe.ts', import.meta.url), 'utf8')

test('the first-page orbit uses the explicit selector list and dynamic rotating poses', () => {
  assert.match(carousel, /ECHO_SELECTOR_MOODS\.map/)
  assert.match(carousel, /moodOrbitTextPose\(index, position, ECHO_SELECTOR_MOODS\.length, expanded\)/)
  assert.match(carousel, /rotate\(\$\{textPose\.angle\}deg\)/)
  assert.match(carousel, /rotate\(\$\{-textPose\.angle\}deg\)/)
  assert.match(carousel, /moodTickAngle\(index, position, ECHO_SELECTOR_MOODS\.length\)/)
  assert.doesNotMatch(carousel, /getMoodTaxonomyPosition/)
  assert.doesNotMatch(carousel, /taxonomyPosition\.angle/)
  assert.match(css, /\.mood-orbit-text\[data-polarity='negative'\]/)
  assert.match(css, /\.mood-orbit-text\[data-polarity='positive'\]/)
  assert.match(css, /\.mood-orbit-text\[data-polarity='neutral'\]/)
})

test('Home and the swipe hook share the selector count contract', () => {
  assert.match(home, /activeMoodIndex\(echoPosition, ECHO_SELECTOR_MOODS\.length\)/)
  assert.match(home, /nearestMoodPosition\(echoPosition, index, ECHO_SELECTOR_MOODS\.length\)/)
  assert.match(home, /useMoodSwipe\([\s\S]*ECHO_SELECTOR_MOODS\.length/)
  assert.match(home, /aria-valuemax=\{echoVoid \? ECHO_SELECTOR_MOODS\.length/)
  assert.match(swipe, /count: number/)
  assert.match(swipe, /disabled \|\| count < 2/)
})

test('the descriptor ring is selected from the current valence and optional discrete mood', () => {
  assert.match(home, /getMoodDescriptorWords\(selectedMood\)/)
  assert.match(home, /moodPolarity\(selectedMood\)/)
  assert.match(home, /descriptorWords\.map/)
  assert.match(home, /data-descriptor-polarity=\{descriptorPolarity\}/)
  assert.ok((home.match(/setLabels\(\[\]\)/g) ?? []).length >= 2)
  assert.doesNotMatch(home, /const WORDS\s*=/)
})

test('the second page artwork and submitted MoodState preserve the first-page discrete mood', () => {
  assert.match(home, /const echoMood = ECHO_SELECTOR_MOODS\[echoMoodIndex\]/)
  assert.match(home, /emotionId: echoMood\.id/)
  assert.match(home, /<MoodPlanetImage[\s\S]*moodId=\{echoMood\.id\}/)
  assert.match(home, /valence: selectedMood\.valence/)
  assert.match(home, /emotionId: selectedMood\.emotionId/)
  assert.match(types, /emotionId\?: MoodId/)
})
