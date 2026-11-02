import assert from 'node:assert/strict';
import { chmodSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const sdkRoot = '/Applications/DevEco-Studio.app/Contents/sdk';
const bundledSdk = join(sdkRoot, 'default');

function gatewayGuardFixture(t) {
  const temporary = mkdtempSync(join(tmpdir(), 'milo-release-guard-'));
  t.after(() => rmSync(temporary, { recursive: true, force: true }));
  const wrapper = join(temporary, 'hvigorw');
  writeFileSync(wrapper, readFileSync(join(projectRoot, 'hvigorw')));
  chmodSync(wrapper, 0o755);
  const fakeStudio = join(temporary, 'fake-studio');
  mkdirSync(join(fakeStudio, 'sdk', 'default'), { recursive: true });
  writeFileSync(join(fakeStudio, 'sdk', 'default', 'sdk-pkg.json'), '{}');
  mkdirSync(join(fakeStudio, 'tools', 'hvigor', 'bin'), { recursive: true });
  const fakeHvigor = join(fakeStudio, 'tools', 'hvigor', 'bin', 'hvigorw');
  writeFileSync(fakeHvigor, '#!/usr/bin/env bash\nprintf "FAKE_HVIGOR_INVOKED\\n"\n');
  chmodSync(fakeHvigor, 0o755);
  const rawfile = join(temporary, 'entry', 'src', 'main', 'resources', 'rawfile');
  mkdirSync(rawfile, { recursive: true });
  return {
    credential: join(rawfile, 'gateway-credentials.local.json'),
    localProperties: join(temporary, 'local.properties'),
    target: join(temporary, 'symlink-target.json'),
    run: (args) => spawnSync(wrapper, args, {
      cwd: temporary,
      env: { ...process.env, DEVECO_STUDIO_HOME: fakeStudio },
      encoding: 'utf8'
    })
  };
}

test('gateway release guard blocks public packaging before SDK initialization', (t) => {
  const fixture = gatewayGuardFixture(t);
  writeFileSync(fixture.credential, '{}');
  for (const args of [
    ['assembleApp'],
    ['entry:assembleApp'],
    ['assembleHap', '-p', 'product=release'],
    ['assembleHap', '-p', 'buildMode=release'],
    ['clean', 'assembleApp'],
    ['clean', 'assembleHap', '-p', 'product=release'],
    ['clean', 'compileArkTS', '-p', 'buildMode=release']
  ]) {
    const result = fixture.run(args);
    assert.notEqual(result.status, 0, args.join(' '));
    assert.match(result.stderr, /local device-test gateway credential.*not for public release; switch to user authentication before release/);
    assert.doesNotMatch(result.stdout, /FAKE_HVIGOR_INVOKED/);
    assert.equal(existsSync(fixture.localProperties), false);
  }
});

test('gateway release guard permits debug work and clean-only release cleanup', (t) => {
  const fixture = gatewayGuardFixture(t);
  writeFileSync(fixture.credential, '{}');
  for (const args of [
    ['assembleHap'],
    ['test'],
    ['--version'],
    ['clean', '-p', 'product=release'],
    ['--mode', 'project', 'clean', '-p', 'buildMode=release'],
    ['entry:clean', '-p', 'product=release', '--no-daemon']
  ]) {
    const result = fixture.run(args);
    assert.equal(result.status, 0, result.stderr || args.join(' '));
    assert.match(result.stdout, /FAKE_HVIGOR_INVOKED/);
  }
});

test('gateway release guard blocks valid and dangling credential symlinks', (t) => {
  const fixture = gatewayGuardFixture(t);
  symlinkSync(fixture.target, fixture.credential);
  const danglingResult = fixture.run(['clean', 'assembleApp']);
  assert.notEqual(danglingResult.status, 0);
  assert.equal(existsSync(fixture.target), false);
  writeFileSync(fixture.target, 'fixture-only');
  const validResult = fixture.run(['assembleHap', '-p', 'product=release']);
  assert.notEqual(validResult.status, 0);
  assert.equal(readFileSync(fixture.target, 'utf8'), 'fixture-only');
  assert.equal(lstatSync(fixture.credential).isSymbolicLink(), true);
  assert.equal(existsSync(fixture.localProperties), false);
});

test('gateway release guard allows release packaging without a local credential', (t) => {
  const fixture = gatewayGuardFixture(t);
  const result = fixture.run(['assembleApp', '-p', 'product=release']);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /FAKE_HVIGOR_INVOKED/);
});

test('hvigorw prepares the bundled API 24 SDK layout before invoking Hvigor', () => {
  const result = spawnSync(join(projectRoot, 'hvigorw'), ['--version'], {
    cwd: projectRoot,
    encoding: 'utf8'
  });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.equal(
    readFileSync(join(projectRoot, 'local.properties'), 'utf8'),
    `sdk.dir=${sdkRoot}\n`
  );
  const sdkPkg = JSON.parse(readFileSync(join(bundledSdk, 'sdk-pkg.json'), 'utf8'));
  assert.equal(sdkPkg.data.apiVersion, '24');
  assert.equal(sdkPkg.data.platformVersion, '6.1.1');
  for (const component of ['ets', 'js', 'native', 'previewer', 'toolchains']) {
    assert.ok(
      existsSync(join(bundledSdk, 'openharmony', component, 'oh-uni-package.json')),
      `Missing OpenHarmony API 24 component: ${component}`
    );
  }
});

test('root page wires the complete recall flow on the dark background', () => {
  const source = readFileSync(
    join(projectRoot, 'entry', 'src', 'main', 'ets', 'pages', 'Index.ets'),
    'utf8'
  );

  for (const contract of [
    'StageBackdrop',
    'LoginScreen({',
    'HomeScreen({',
    'ClassifyScreen({',
    'NowNoteScreen({',
    'PastTimeScreen({',
    'ChatScreen({',
    'DiaryScreen({',
    'TimelineScreen({',
    'DetailScreen({',
    'CardScreen({',
    ".width('100%')",
    ".height('100%')"
  ]) {
    assert.ok(source.includes(contract), `Missing smoke-shell contract: ${contract}`);
  }
});

test('start window matches the root background in every system color mode', () => {
  const moduleProfile = JSON.parse(
    readFileSync(join(projectRoot, 'entry', 'src', 'main', 'module.json5'), 'utf8')
  );
  assert.equal(
    moduleProfile.module.abilities[0].startWindowBackground,
    '$color:start_window_background'
  );

  const startWindowColors = ['base', 'dark'].map((variant) => {
    const resource = JSON.parse(
      readFileSync(
        join(
          projectRoot,
          'entry',
          'src',
          'main',
          'resources',
          variant,
          'element',
          'color.json'
        ),
        'utf8'
      )
    );
    return resource.color.find(({ name }) => name === 'start_window_background')?.value;
  });

  assert.deepEqual(startWindowColors, ['#050608', '#050608']);
  assert.ok(
    moduleProfile.module.requestPermissions.some(({ name }) => name === 'ohos.permission.INTERNET'),
    'The native AI gateway client requires the INTERNET permission'
  );
});
