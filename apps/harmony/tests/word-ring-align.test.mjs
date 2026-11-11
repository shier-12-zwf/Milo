import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const home = join(projectRoot, 'entry', 'src', 'main', 'ets', 'features', 'home');
const screen = readFileSync(join(home, 'HomeScreen.ets'), 'utf8');
const layout = readFileSync(join(home, 'WordRingLayout.ets'), 'utf8');
const list = readFileSync(join(projectRoot, 'entry', 'src', 'test', 'List.test.ets'), 'utf8');

test('word ring labels are positioned by the row-aligned WordRingLayout (AGC align review)', () => {
  assert.match(screen, /import \{ wordRingPoint, wordRingStepAngle \} from '\.\/WordRingLayout';/);
  assert.match(screen, /private wordY\(index: number\): number \{\s*return wordRingPoint\(/);
  assert.match(screen, /private wordX\(index: number\): number \{\s*return wordRingPoint\(/);
  assert.doesNotMatch(screen, /Math\.sin\(angle\) \* WORD_RADIUS/);
});

test('top and bottom words are capped at their neighbours\' row', () => {
  assert.match(layout, /Math\.cos\(wordRingStepAngle\(count\) \* Math\.PI \/ 180\) \* radius/);
  assert.match(layout, /if \(dy > limit\) \{\s*dy = limit;\s*\} else if \(dy < -limit\) \{\s*dy = -limit;/);
  assert.match(list, /wordRingLayoutTest\(\);/);
});
