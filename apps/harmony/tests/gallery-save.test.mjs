import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const main = join(projectRoot, 'entry', 'src', 'main');
const card = readFileSync(join(main, 'ets', 'features', 'timeline', 'CardScreen.ets'), 'utf8');
const moduleJson = readFileSync(join(main, 'module.json5'), 'utf8');

test('card gallery save does not need the restricted WRITE_IMAGEVIDEO permission', () => {
  assert.doesNotMatch(moduleJson, /WRITE_IMAGEVIDEO/);
  assert.doesNotMatch(card, /createImageAssetRequest|applyChanges/);
  assert.match(card, /showAssetsCreationDialog\(\[fileUri\.getUriFromPath\(path\)\], \[config\]\)/);
  assert.match(card, /fileNameExtension: 'png'/);
  assert.match(card, /photoType: photoAccessHelper\.PhotoType\.IMAGE/);
});

test('cancelling the system save dialog clears the status instead of reporting failure', () => {
  assert.match(card, /if \(targets\.length === 0\) \{[\s\S]*?this\.saveState = '';[\s\S]*?return;/);
  assert.match(card, /fs\.copyFileSync\(source\.fd, target\.fd\)/);
  assert.match(card, /finally \{\s*try \{ fs\.unlinkSync\(path\); \}/);
});
