import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

// 仓库根：apps/web/tests/ → ../../../ → milo/
const repoRoot = new URL('../../../', import.meta.url)

test('GitHub Pages builds assets for the renamed Milo repository', () => {
  const workflow = readFileSync(new URL('.github/workflows/deploy-pages.yml', repoRoot), 'utf8')

  assert.match(workflow, /--base=\/Milo\//)
  assert.doesNotMatch(workflow, /echoes-cosmic-mood/)
})
