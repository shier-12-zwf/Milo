import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { extractLegalText, packageLegalSite, renderLegalPage } from '../tools/package-legal-site.mjs';

function fixture(t) {
  const root = mkdtempSync(join(realpathSync(tmpdir()), 'milo-legal-package-test-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const source = join(root, 'source');
  const destination = join(root, 'destination');
  mkdirSync(join(source, '.vercel/output/static'), { recursive: true });
  writeFileSync(join(source, '.vercel/output/static/index.html'), '<h1>Unchanged old homepage</h1>\n');
  writeFileSync(join(source, '.vercel/output/config.json'), '{"version":3,"routes":[{"handle":"filesystem"}]}\n');
  writeFileSync(join(source, '.vercel/project.json'), '{"projectId":"test-project","orgId":"test-org"}\n');
  return { root, source, destination };
}

test('legal HTML preserves canonical text exactly and escapes markup without scripts', () => {
  const text = 'MILO 隐私政策\n\n一、说明\n\n测试 <script> & "内容"\nhttps://example.test/policy?a=1&b=2\nhelp@example.test\n';
  const html = renderLegalPage(text, 'MILO 隐私政策');
  assert.equal(extractLegalText(html), text);
  assert.doesNotMatch(html, /<script\b|<iframe\b|<form\b/i);
  assert.match(html, /href="https:\/\/example.test\/policy\?a=1&amp;b=2"/);
  assert.match(html, /href="mailto:help@example.test"/);
  assert.match(html, /charset="utf-8"/);
});

test('package adds exactly two public pages and reruns without changing original files', (t) => {
  const options = fixture(t);
  const first = packageLegalSite(options);
  assert.equal(first.preservedOriginalFiles, 3);
  assert.equal(first.addedPublicPages, 2);
  assert.equal(first.status, 'prepared-not-deployed');
  const firstHtml = readFileSync(join(options.destination, '.vercel/output/static/harmony-privacy.html'), 'utf8');
  const second = packageLegalSite(options);
  assert.equal(second.originalsByteIdentical, true);
  assert.equal(readFileSync(join(options.destination, '.vercel/output/static/harmony-privacy.html'), 'utf8'), firstHtml);
  assert.equal(readFileSync(join(options.source, '.vercel/output/static/index.html'), 'utf8'), '<h1>Unchanged old homepage</h1>\n');
});

test('refuses to replace a modified old homepage', (t) => {
  const options = fixture(t);
  packageLegalSite(options);
  const homepage = join(options.destination, '.vercel/output/static/index.html');
  writeFileSync(homepage, 'Another worker edited this');
  assert.throws(() => packageLegalSite(options), /will not overwrite/);
  assert.equal(readFileSync(homepage, 'utf8'), 'Another worker edited this');
});

test('refuses source symlinks instead of copying outside data', (t) => {
  const options = fixture(t);
  const outside = join(options.root, 'outside');
  writeFileSync(outside, 'test-only external data');
  symlinkSync(outside, join(options.source, '.vercel/output/static/extra.txt'));
  assert.throws(() => packageLegalSite(options), /non-regular/);
});

test('refuses unmanaged output and symbolic-link destinations', (t) => {
  const options = fixture(t);
  mkdirSync(options.destination);
  writeFileSync(join(options.destination, 'unrelated.txt'), 'Keep me');
  assert.throws(() => packageLegalSite(options));
  assert.equal(readFileSync(join(options.destination, 'unrelated.txt'), 'utf8'), 'Keep me');
  const link = join(options.root, 'destination-link');
  symlinkSync(options.destination, link);
  assert.throws(() => packageLegalSite({ source: options.source, destination: link }), /symbolic link/);
});
