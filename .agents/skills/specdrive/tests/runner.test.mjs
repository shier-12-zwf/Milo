import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const cli = fileURLToPath(new URL('../scripts/specdrive.mjs', import.meta.url));
const node = process.execPath;
const command = (code, extras = {}) => ({ id: 'core', argv: [node, '-e', code], inputs: ['source.txt'], timeoutMs: 3000, ...extras });

function fixture(t, checks, limits = {}) {
  const project = fs.mkdtempSync(path.join(os.tmpdir(), 'specdrive-test-'));
  t.after(() => fs.rmSync(project, { recursive: true, force: true }));
  fs.writeFileSync(path.join(project, 'source.txt'), 'one');
  const configPath = path.join(project, 'checks.json');
  fs.writeFileSync(configPath, JSON.stringify({ version: 1, checks, limits }));
  const state = path.join(project, '.specdrive', 'run');
  const invoke = (...args) => spawnSync(node, [cli, ...args], { cwd: project, encoding: 'utf8' });
  const initialized = invoke('init', configPath, '--state', state);
  assert.equal(initialized.status, 0, initialized.stderr);
  return { project, state, configPath, invoke, read: () => JSON.parse(fs.readFileSync(path.join(state, 'state.json'))), report: command => {
    const result = invoke(command, state);
    return { code: result.status, data: JSON.parse(result.stdout || result.stderr) };
  } };
}

test('initial missing checks block; successful evidence resumes; changed source invalidates gate and reruns', t => {
  const f = fixture(t, [command("require('fs').appendFileSync('counter','x'); console.log('saved')")]);
  assert.equal(f.report('gate').code, 78);
  assert.equal(f.report('run').code, 0);
  assert.equal(f.report('gate').data.readyToArchive, true);
  assert.equal(f.report('run').code, 0);
  assert.equal(fs.readFileSync(path.join(f.project, 'counter'), 'utf8'), 'x');
  fs.writeFileSync(path.join(f.project, 'source.txt'), 'two');
  assert.equal(f.report('gate').code, 78);
  assert.equal(f.report('run').code, 0);
  assert.equal(fs.readFileSync(path.join(f.project, 'counter'), 'utf8'), 'xx');
  assert.equal(f.read().checks.core.attempts.length, 2);
});

test('missing prerequisite blocks dependants but independent core tests still run; resume retries preflight', t => {
  const f = fixture(t, [
    command("process.exit(require('fs').existsSync('installed') ? 0 : 78)", { id: 'xcode', kind: 'preflight', inputs: [] }),
    command("require('fs').writeFileSync('build-ran','yes')", { id: 'build', dependsOn: ['xcode'] }),
    command('console.log("core passed")')
  ]);
  let result = f.report('run');
  assert.equal(result.code, 78);
  assert.equal(result.data.readyToArchive, false);
  assert.deepEqual(result.data.checks.map(check => check.status), ['blocked', 'blocked', 'passed']);
  assert.equal(fs.existsSync(path.join(f.project, 'build-ran')), false);
  assert.equal(f.read().checks.build.attempts.length, 0);
  fs.writeFileSync(path.join(f.project, 'installed'), 'yes');
  result = f.report('run');
  assert.equal(result.code, 0);
  assert.equal(f.read().checks.core.attempts.length, 1);
  assert.equal(f.read().checks.xcode.attempts.length, 2);
});

test('failed checks run once per invocation and stop at a no-progress cap', t => {
  const f = fixture(t, [command("console.error('assertion failed');process.exit(1)")], { maxAttemptsPerCheck: 5, maxNoProgress: 2 });
  assert.equal(f.report('run').code, 1);
  assert.equal(f.read().checks.core.attempts.length, 1);
  assert.equal(f.report('run').code, 1);
  assert.equal(f.report('run').code, 78);
  assert.equal(f.read().checks.core.attempts.length, 2);
  assert.match(f.read().checks.core.reason, /No-progress cap/);
});

test('a source fix resets no-progress detection without resetting the total attempt cap', t => {
  const f = fixture(t, [command("process.exit(require('fs').readFileSync('source.txt','utf8') === 'fixed' ? 0 : 1)")], { maxAttemptsPerCheck: 5 });
  assert.equal(f.report('run').code, 1);
  assert.equal(f.report('run').code, 1);
  assert.equal(f.report('run').code, 78);
  fs.writeFileSync(path.join(f.project, 'source.txt'), 'fixed');
  assert.equal(f.report('run').code, 0);
  assert.equal(f.read().checks.core.attempts.length, 3);
});

test('attempt cap applies to repeated source revisions', t => {
  const f = fixture(t, [command('process.exit(1)')], { maxAttemptsPerCheck: 2 });
  f.report('run');
  fs.writeFileSync(path.join(f.project, 'source.txt'), 'two');
  f.report('run');
  fs.writeFileSync(path.join(f.project, 'source.txt'), 'three');
  assert.equal(f.report('run').code, 78);
  assert.match(f.read().checks.core.reason, /Attempt cap/);
  assert.equal(f.read().checks.core.attempts.length, 2);
});

test('timeout is blocked and a cumulative wall-time cap prevents a further command', t => {
  const f = fixture(t, [command('setInterval(() => {}, 1000)', { timeoutMs: 100 }), command('process.exit(0)', { id: 'later' })], { maxWallTimeMs: 100 });
  const result = f.report('run');
  assert.equal(result.code, 78);
  assert.equal(f.read().checks.core.attempts[0].timedOut, true);
  assert.match(f.read().checks.later.reason, /Wall-time cap/);
  assert.equal(f.read().checks.later.attempts.length, 0);
});

test('changes during a successful command cannot become passing evidence', t => {
  const f = fixture(t, [command("require('fs').writeFileSync('source.txt','changed')")]);
  const result = f.report('run');
  assert.equal(result.code, 78);
  assert.match(result.data.checks[0].reason, /Inputs changed during execution/);
  assert.equal(f.report('gate').data.readyToArchive, false);
});

test('changed commands require a fresh run; a missing or modified log invalidates evidence', t => {
  const f = fixture(t, [command("console.log('proof')")]);
  assert.equal(f.report('run').code, 0);
  const evidence = path.join(f.state, f.read().checks.core.attempts[0].log);
  fs.writeFileSync(evidence, 'forged log');
  assert.equal(f.report('gate').code, 78);
  assert.equal(f.report('run').code, 0);
  fs.rmSync(path.join(f.state, f.read().checks.core.attempts[1].log));
  assert.equal(f.report('gate').code, 78);
  const config = JSON.parse(fs.readFileSync(f.configPath));
  config.checks[0].argv = [node, '-e', 'process.exit(1)'];
  fs.writeFileSync(f.configPath, JSON.stringify(config));
  assert.match(f.report('run').data.blockers[0], /Configuration changed/);
  assert.equal(f.read().checks.core.attempts.length, 2);
});

test('a stale PID lock is recovered and a live owner is rejected', async t => {
  const f = fixture(t, [command('setTimeout(() => {}, 500)')]);
  const lock = path.join(f.state, 'run.lock');
  fs.writeFileSync(lock, JSON.stringify({ pid: 99999999, token: 'dead' }));
  assert.equal(f.report('run').code, 0);
  assert.equal(fs.existsSync(lock), false);
  fs.writeFileSync(path.join(f.project, 'source.txt'), 'new');
  const running = spawn(node, [cli, 'run', f.state], { cwd: f.project, stdio: 'ignore' });
  const completion = new Promise(resolve => running.once('close', resolve));
  t.after(() => running.kill('SIGKILL'));
  const deadline = Date.now() + 3000;
  while (!fs.existsSync(lock) && Date.now() < deadline) await new Promise(resolve => setTimeout(resolve, 10));
  assert.equal(fs.existsSync(lock), true);
  const contender = f.invoke('run', f.state);
  assert.equal(contender.status, 2);
  assert.match(contender.stderr, /Run locked/);
  assert.equal(await completion, 0);
});

test('directory fingerprints include additions/deletions but ignore generated build files', t => {
  const f = fixture(t, [command('process.exit(0)', { inputs: ['.'] })]);
  assert.equal(f.report('run').code, 0);
  fs.mkdirSync(path.join(f.project, '.build'));
  fs.writeFileSync(path.join(f.project, '.build', 'generated'), 'cache');
  assert.equal(f.report('gate').code, 0);
  fs.writeFileSync(path.join(f.project, 'new-source'), 'new');
  assert.equal(f.report('gate').code, 78);
  fs.rmSync(path.join(f.project, 'new-source'));
  assert.equal(f.report('gate').code, 0);
});

test('review evidence must be produced by its configured command and bound to inputs', t => {
  const f = fixture(t, [command('process.exit(0)'), command("process.exit(require('fs').readFileSync('review.json','utf8').includes('pass') ? 0 : 1)", { id: 'review', inputs: ['source.txt', 'review.json'] })]);
  assert.equal(f.report('run').code, 78);
  fs.writeFileSync(path.join(f.project, 'review.json'), '{"verdict":"pass"}');
  assert.equal(f.report('run').code, 0);
  fs.writeFileSync(path.join(f.project, 'review.json'), '{"verdict":"fail"}');
  assert.equal(f.report('gate').code, 78);
  assert.equal(f.report('run').code, 1);
});

test('argument arrays are executed literally without shell expansion', t => {
  const f = fixture(t, [command("console.log(process.argv[1]);process.exit(process.argv[1] === '$(touch stolen)' ? 0 : 1)", { argv: [node, '-e', "console.log(process.argv[1]);process.exit(process.argv[1] === '$(touch stolen)' ? 0 : 1)", '$(touch stolen)'] })]);
  assert.equal(f.report('run').code, 0);
  assert.equal(fs.existsSync(path.join(f.project, 'stolen')), false);
});

test('a command not installed is a blocked preflight, not a product failure', t => {
  const f = fixture(t, [command('', { argv: ['specdrive-nonexistent-test-executable'], kind: 'preflight', inputs: [] })]);
  const result = f.report('run');
  assert.equal(result.code, 78);
  assert.match(result.data.checks[0].reason, /Cannot start command/);
});

test('SIGTERM cancels the running command, records blocked evidence and prevents subsequent work', async t => {
  const f = fixture(t, [command("require('fs').writeFileSync('child-started','yes');setInterval(() => {},1000)"), command("require('fs').writeFileSync('later-ran','yes')", { id: 'later' })]);
  const runner = spawn(node, [cli, 'run', f.state], { cwd: f.project, stdio: 'ignore' });
  const completion = new Promise(resolve => runner.once('close', resolve));
  t.after(() => runner.kill('SIGKILL'));
  const deadline = Date.now() + 3000;
  while (!fs.existsSync(path.join(f.project, 'child-started')) && Date.now() < deadline) await new Promise(resolve => setTimeout(resolve, 10));
  assert.equal(fs.existsSync(path.join(f.project, 'child-started')), true);
  runner.kill('SIGTERM');
  assert.equal(await completion, 78);
  const state = f.read();
  assert.match(state.checks.core.reason, /Execution interrupted/);
  assert.equal(state.checks.core.attempts.length, 1);
  assert.equal(state.checks.later.attempts.length, 0);
  assert.equal(fs.existsSync(path.join(f.project, 'later-ran')), false);
  assert.equal(fs.existsSync(path.join(f.state, 'run.lock')), false);
});

test('a stale parent lock is not reclaimed while its command is alive', t => {
  const f = fixture(t, [command('process.exit(0)')]);
  fs.writeFileSync(path.join(f.state, 'run.lock'), JSON.stringify({ pid: 99999999, childPid: process.pid, token: 'dead' }));
  const result = f.invoke('run', f.state);
  assert.equal(result.status, 2);
  assert.match(result.stderr, /child PID.*still running/);
  assert.equal(f.read().checks.core.attempts.length, 0);
});

test('expired evidence is blocked and is refreshed by an explicit run', async t => {
  const f = fixture(t, [command('process.exit(0)', { maxAgeMs: 150 })]);
  assert.equal(f.report('run').code, 0);
  await new Promise(resolve => setTimeout(resolve, 170));
  assert.equal(f.report('gate').code, 78);
  assert.equal(f.report('run').code, 0);
  assert.equal(f.read().checks.core.attempts.length, 2);
});

test('input paths reject symlink ancestors at init and after initialization', t => {
  const f = fixture(t, [command('process.exit(0)', { inputs: ['nested/source.txt'] })]);
  const external = fs.mkdtempSync(path.join(os.tmpdir(), 'specdrive-external-'));
  t.after(() => fs.rmSync(external, { recursive: true, force: true }));
  fs.writeFileSync(path.join(external, 'source.txt'), 'outside');
  fs.symlinkSync(external, path.join(f.project, 'nested'), 'dir');
  const initialized = f.invoke('init', f.configPath, '--state', path.join(f.project, '.specdrive', 'second'));
  assert.equal(initialized.status, 2);
  assert.match(initialized.stderr, /unsupported symlink/);
  const result = f.report('run');
  assert.equal(result.code, 78);
  assert.match(result.data.blockers[0], /unsupported symlink/);
  assert.equal(f.read().checks.core.attempts.length, 0);
});

test('working directories reject symlink ancestors before executing commands', t => {
  const f = fixture(t, [command("require('fs').writeFileSync('executed','yes')", { cwd: 'nested/work' })]);
  const external = fs.mkdtempSync(path.join(os.tmpdir(), 'specdrive-external-'));
  t.after(() => fs.rmSync(external, { recursive: true, force: true }));
  fs.mkdirSync(path.join(external, 'work'));
  fs.symlinkSync(external, path.join(f.project, 'nested'), 'dir');
  assert.equal(f.report('run').code, 78);
  assert.equal(fs.existsSync(path.join(external, 'work', 'executed')), false);
  const initialized = f.invoke('init', f.configPath, '--state', path.join(f.project, '.specdrive', 'second'));
  assert.equal(initialized.status, 2);
  assert.match(initialized.stderr, /unsupported symlink/);
});

test('canonical project aliases exclude custom evidence directories from whole-project input hashes', t => {
  const base = fs.mkdtempSync(path.join(os.tmpdir(), 'specdrive-alias-'));
  t.after(() => fs.rmSync(base, { recursive: true, force: true }));
  const project = path.join(base, 'project'), alias = path.join(base, 'alias');
  fs.mkdirSync(project);
  fs.symlinkSync(project, alias, 'dir');
  fs.writeFileSync(path.join(project, 'source.txt'), 'one');
  fs.writeFileSync(path.join(project, 'checks.json'), JSON.stringify({ version: 1, checks: [command('process.exit(0)', { inputs: ['.'] })] }));
  const invoke = (...args) => spawnSync(node, [cli, ...args], { encoding: 'utf8' });
  const aliasedState = path.join(alias, 'evidence');
  const initialized = invoke('init', path.join(alias, 'checks.json'), '--project', alias, '--state', aliasedState);
  assert.equal(initialized.status, 0, initialized.stderr);
  const canonicalState = fs.realpathSync(aliasedState);
  assert.equal(JSON.parse(initialized.stdout).stateDirectory, canonicalState);
  assert.equal(invoke('run', aliasedState).status, 0);
  assert.equal(invoke('gate', canonicalState).status, 0);
  // An older state may have recorded the noncanonical alias; reads normalize it too.
  const stateFile = path.join(canonicalState, 'state.json');
  const state = JSON.parse(fs.readFileSync(stateFile));
  state.evidenceRoot = aliasedState;
  fs.writeFileSync(stateFile, JSON.stringify(state));
  assert.equal(invoke('gate', aliasedState).status, 0);
  assert.equal(invoke('run', canonicalState).status, 0);
  assert.equal(JSON.parse(fs.readFileSync(stateFile)).checks.core.attempts.length, 1);
});
