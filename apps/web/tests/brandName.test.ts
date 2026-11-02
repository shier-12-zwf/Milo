import assert from 'node:assert/strict'
import { existsSync, readFileSync } from 'node:fs'
import test from 'node:test'

const home = readFileSync(new URL('../src/pages/Home.tsx', import.meta.url), 'utf8')
const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8')

test('the home header uses the Milo-米洛 brand name', () => {
  assert.match(home, /<div className="eyebrow">Milo-米洛<\/div>/)
})

test('the browser tab uses the Milo-米洛 brand name', () => {
  assert.match(html, /<title>Milo-米洛<\/title>/)
})

test('the browser tab uses the Milo PNG favicon', () => {
  const faviconUrl = new URL('../public/favicon.png', import.meta.url)

  assert.match(html, /<link rel="icon" type="image\/png" href="\/favicon\.png" \/>/)
  assert.equal(existsSync(faviconUrl), true)
  assert.deepEqual(
    [...readFileSync(faviconUrl).subarray(0, 8)],
    [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
  )
})
