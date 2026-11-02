import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const nowNote = readFileSync(new URL('../src/pages/NowNote.tsx', import.meta.url), 'utf8')

test('NowNote reuses the home mood planet image for identified moods', () => {
  assert.match(nowNote, /import \{ MoodPlanetImage \} from '\.\.\/components\/MoodPlanetImage'/)
  assert.match(
    nowNote,
    /mood\.emotionId \? \(\s*<MoodPlanetImage moodId=\{mood\.emotionId\} size=\{120\} \/>/,
  )
})

test('NowNote reliably falls back to the legacy rendered orb without an emotion id', () => {
  assert.match(
    nowNote,
    /mood\.emotionId \? \([\s\S]*\) : \(\s*<MoodOrb valence=\{mood\.valence\} size=\{120\} \/>/,
  )
  assert.doesNotMatch(nowNote, /<MoodOrb[^>]*emotionId=/)
})
