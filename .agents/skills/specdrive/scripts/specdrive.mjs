#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const runnerPath = fileURLToPath(import.meta.url);
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const json = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const ignored = new Set(['.git', '.build', 'node_modules', '.specdrive', 'build', 'DerivedData']);
const fail = message => { throw new Error(message); };
const positive = (value, label) => Number.isSafeInteger(value) && value > 0 || fail(`${label} must be a positive integer`);

function inside(root, relative, label) {
  if (typeof relative !== 'string' || path.isAbsolute(relative)) fail(`${label} must be a relative path`);
  const resolved = path.resolve(root, relative);
  if (resolved !== root && !resolved.startsWith(root + path.sep)) fail(`${label} escapes the project`);
  let ancestor = root;
  for (const component of path.relative(root, resolved).split(path.sep).filter(Boolean)) {
    ancestor = path.join(ancestor, component);
    try {
      if (fs.lstatSync(ancestor).isSymbolicLink()) fail(`${label} contains an unsupported symlink: ${ancestor}`);
    } catch (error) {
      if (error.code === 'ENOENT' || error.code === 'ENOTDIR') break;
      throw error;
    }
  }
  return resolved;
}

function readState(directory) {
  const state = json(path.join(directory, 'state.json'));
  state.evidenceRoot = fs.realpathSync(state.evidenceRoot);
  if (state.evidenceRoot !== directory) fail('Evidence directory moved; initialize a new run instead');
  return state;
}

function normalize(config, project) {
  if (config.version !== 1 || !Array.isArray(config.checks) || !config.checks.length) fail('Expected version: 1 and a nonempty checks array');
  const ids = new Set();
  const checks = config.checks.map(check => {
    if (!/^[a-z0-9][a-z0-9_-]*$/.test(check.id || '') || ids.has(check.id)) fail('Check ids must be unique lowercase identifiers');
    if (!Array.isArray(check.argv) || !check.argv.length || check.argv.some(arg => typeof arg !== 'string') || !check.argv[0]) fail(`${check.id}: argv must be a nonempty string array`);
    const cwd = check.cwd ?? '.';
    inside(project, cwd, `${check.id}.cwd`);
    const kind = check.kind ?? 'verification';
    if (!['preflight', 'verification'].includes(kind)) fail(`${check.id}: invalid kind`);
    const inputs = check.inputs ?? [];
    if (!Array.isArray(inputs) || (!inputs.length && kind !== 'preflight')) fail(`${check.id}: verification requires input paths`);
    inputs.forEach(input => inside(project, input, `${check.id}.inputs`));
    const dependsOn = check.dependsOn ?? [];
    if (!Array.isArray(dependsOn) || dependsOn.some(id => !ids.has(id))) fail(`${check.id}: dependencies must refer to earlier checks`);
    const timeoutMs = check.timeoutMs ?? 120000;
    positive(timeoutMs, `${check.id}.timeoutMs`);
    if (check.maxAgeMs !== undefined) positive(check.maxAgeMs, `${check.id}.maxAgeMs`);
    const env = check.env ?? {};
    if (!env || typeof env !== 'object' || Array.isArray(env) || Object.values(env).some(value => typeof value !== 'string')) fail(`${check.id}: env must contain string values`);
    if (check.required !== undefined && typeof check.required !== 'boolean') fail(`${check.id}: required must be boolean`);
    ids.add(check.id);
    return { id: check.id, argv: check.argv, cwd, kind, inputs, dependsOn, timeoutMs, env, required: check.required ?? true, ...(check.maxAgeMs ? { maxAgeMs: check.maxAgeMs } : {}) };
  });
  if (!checks.some(check => check.required)) fail('At least one required check is needed');
  const limits = { maxAttemptsPerCheck: 3, maxNoProgress: 2, maxWallTimeMs: 900000, ...config.limits };
  for (const [key, value] of Object.entries(limits)) positive(value, `limits.${key}`);
  return { version: 1, checks, limits };
}

function atomic(file, value) {
  const temporary = `${file}.${process.pid}.${crypto.randomUUID()}.tmp`;
  try {
    fs.writeFileSync(temporary, JSON.stringify(value, null, 2) + '\n', { mode: 0o600 });
    fs.renameSync(temporary, file);
  } finally { fs.rmSync(temporary, { force: true }); }
}

function fingerprint(state, check) {
  const digest = crypto.createHash('sha256');
  digest.update(JSON.stringify({ config: state.config, project: state.projectRoot, runner: hash(fs.readFileSync(runnerPath)) }));
  const visit = (absolute, relative) => {
    const stat = fs.lstatSync(absolute);
    if (stat.isSymbolicLink()) fail(`Input symlinks are unsupported: ${relative}`);
    if (stat.isDirectory()) {
      digest.update(`directory:${relative}\0`);
      for (const name of fs.readdirSync(absolute).sort()) {
        if (!ignored.has(name) && path.join(absolute, name) !== state.evidenceRoot) visit(path.join(absolute, name), path.join(relative, name));
      }
    } else if (stat.isFile()) {
      digest.update(`file:${relative}:${stat.mode & 0o777}\0`);
      digest.update(hash(fs.readFileSync(absolute)));
    } else fail(`Unsupported input: ${relative}`);
  };
  for (const input of [...check.inputs].sort()) visit(inside(state.projectRoot, input, 'input'), input);
  return digest.digest('hex');
}

function inspect(state) {
  const blockers = [];
  try {
    if (JSON.stringify(normalize(json(state.configPath), state.projectRoot)) !== JSON.stringify(state.config)) blockers.push('Configuration changed; initialize a new run to preserve prior evidence');
  } catch (error) { blockers.push(`Configuration unavailable: ${error.message}`); }
  const checks = [];
  for (const check of state.config.checks) {
    const record = state.checks[check.id];
    const last = record?.attempts?.at(-1);
    let status = record?.status ?? 'blocked';
    let reason = record?.reason ?? 'Not run';
    try {
      if (status === 'passed') {
        if (!last || last.status !== 'passed' || last.fingerprint !== fingerprint(state, check)) { status = 'blocked'; reason = 'Evidence is stale or missing'; }
        else if (!last.logHash || hash(fs.readFileSync(inside(state.evidenceRoot, last.log, 'log'))) !== last.logHash) { status = 'blocked'; reason = 'Evidence log is missing or changed'; }
        else if (check.maxAgeMs && Date.now() - Date.parse(last.finishedAt) > check.maxAgeMs) { status = 'blocked'; reason = 'Evidence expired'; }
      }
    } catch (error) { status = 'blocked'; reason = `Cannot hash inputs: ${error.message}`; }
    if (check.dependsOn.some(id => checks.find(item => item.id === id)?.status !== 'passed')) { status = 'blocked'; reason = 'Dependency has not passed with current evidence'; }
    checks.push({ id: check.id, required: check.required, status, reason, attempts: record?.attempts?.length ?? 0, log: last?.log });
  }
  const required = checks.filter(check => check.required);
  const status = blockers.length || required.some(check => check.status === 'blocked') ? 'blocked' : required.some(check => check.status === 'failed') ? 'failed' : 'passed';
  return { runId: state.runId, status, readyToArchive: status === 'passed', elapsedMs: state.elapsedMs, blockers, checks };
}

function alive(pid) {
  try { process.kill(pid, 0); return true; } catch (error) { return error.code !== 'ESRCH'; }
}

function lock(directory) {
  const file = path.join(directory, 'run.lock');
  const token = crypto.randomUUID();
  const create = () => fs.writeFileSync(file, JSON.stringify({ pid: process.pid, token }), { flag: 'wx', mode: 0o600 });
  try { create(); } catch (error) {
    if (error.code !== 'EEXIST') throw error;
    const recovery = path.join(directory, 'recovery.lock');
    // A separate exclusive recovery guard prevents two contenders from removing a new owner's lock.
    let guard;
    try { guard = fs.openSync(recovery, 'wx', 0o600); } catch { fail('Another process is recovering the lock; retry, or inspect recovery.lock if interrupted'); }
    try {
      let previous;
      try { previous = json(file); } catch { fail('Malformed run.lock; inspect and remove it before retrying'); }
      if (!Number.isSafeInteger(previous.pid) || previous.pid <= 0 || alive(previous.pid)) fail(`Run locked by PID ${previous.pid}`);
      if (previous.childPid && alive(previous.childPid)) fail(`Run owner exited but child PID ${previous.childPid} is still running; stop it before recovery`);
      fs.rmSync(file);
      create();
    } finally { fs.closeSync(guard); fs.rmSync(recovery, { force: true }); }
  }
  return {
    release: () => { if (fs.existsSync(file) && json(file).token === token) fs.rmSync(file); },
    child: childPid => atomic(file, { pid: process.pid, token, childPid })
  };
}

function execute(state, check, logFile, timeoutMs, control, onSpawn) {
  return new Promise(resolve => {
    const temporary = `${logFile}.tmp`;
    const fd = fs.openSync(temporary, 'w', 0o600);
    let bytes = 0, timedOut = false, spawnError, killTimer;
    const write = chunk => {
      if (bytes >= 10 * 1024 * 1024) return;
      const output = Buffer.from(chunk).subarray(0, 10 * 1024 * 1024 - bytes);
      fs.writeSync(fd, output); bytes += output.length;
    };
    const child = spawn(check.argv[0], check.argv.slice(1), {
      cwd: inside(state.projectRoot, check.cwd, 'cwd'), env: { ...process.env, ...check.env },
      shell: false, detached: process.platform !== 'win32', stdio: ['ignore', 'pipe', 'pipe']
    });
    const kill = signal => {
      try { process.platform === 'win32' ? child.kill(signal) : process.kill(-child.pid, signal); } catch { /* Already exited. */ }
    };
    onSpawn(child.pid);
    control.cancel = () => { kill('SIGTERM'); killTimer = setTimeout(() => kill('SIGKILL'), 200); };
    if (control.signal) control.cancel();
    const timer = setTimeout(() => { timedOut = true; kill('SIGTERM'); killTimer = setTimeout(() => kill('SIGKILL'), 200); }, timeoutMs);
    child.stdout.on('data', write); child.stderr.on('data', write);
    child.on('error', error => { spawnError = error; write(error.message + '\n'); });
    child.on('close', (code, signal) => {
      clearTimeout(timer); clearTimeout(killTimer);
      if (timedOut || control.signal) kill('SIGKILL');
      control.cancel = null;
      fs.closeSync(fd); fs.renameSync(temporary, logFile);
      const status = timedOut || code === 78 || spawnError || control.signal ? 'blocked' : code === 0 ? 'passed' : 'failed';
      const reason = control.signal ? `Execution interrupted (${control.signal})` : timedOut ? 'Command timed out' : spawnError ? `Cannot start command: ${spawnError.message}` : code === 78 ? 'Prerequisite unavailable (exit 78)' : code === 0 ? 'Command passed' : `Command exited ${code ?? signal}`;
      resolve({ status, reason, exitCode: code, signal, timedOut, logHash: hash(fs.readFileSync(logFile)) });
    });
  });
}

function noProgress(attempts) {
  const last = attempts.at(-1);
  if (!last || last.status === 'passed') return 0;
  let count = 0;
  for (const attempt of [...attempts].reverse()) {
    if (attempt.status !== last.status || attempt.fingerprint !== last.fingerprint || attempt.exitCode !== last.exitCode || attempt.reason !== last.reason) break;
    count++;
  }
  return count;
}

async function run(directory) {
  const owner = lock(directory);
  const control = { signal: null, cancel: null };
  const interrupt = signal => { control.signal = signal; control.cancel?.(); };
  const term = () => interrupt('SIGTERM'), int = () => interrupt('SIGINT');
  process.on('SIGTERM', term); process.on('SIGINT', int);
  try {
    const stateFile = path.join(directory, 'state.json');
    const state = readState(directory);
    if (inspect(state).blockers.length) return inspect(state);
    const started = Date.now(), previousElapsed = state.elapsedMs;
    const save = () => { state.elapsedMs = previousElapsed + Date.now() - started; state.updatedAt = new Date().toISOString(); atomic(stateFile, state); };
    for (const check of state.config.checks) {
      const record = state.checks[check.id];
      const current = inspect(state).checks.find(item => item.id === check.id);
      if (current.status === 'passed' && check.kind !== 'preflight') continue;
      const block = reason => { record.status = 'blocked'; record.reason = reason; save(); };
      if (control.signal) { block(`Run interrupted (${control.signal})`); continue; }
      if (check.dependsOn.some(id => inspect(state).checks.find(item => item.id === id)?.status !== 'passed')) { block('Dependency has not passed with current evidence'); continue; }
      if (record.attempts.length >= state.config.limits.maxAttemptsPerCheck) { block('Attempt cap reached; initialize a new run after reviewing evidence'); continue; }
      const remaining = state.config.limits.maxWallTimeMs - (previousElapsed + Date.now() - started);
      if (remaining <= 0) { block('Wall-time cap reached'); continue; }
      let before;
      try { before = fingerprint(state, check); } catch (error) { block(`Cannot hash inputs: ${error.message}`); continue; }
      if (record.attempts.at(-1)?.fingerprint === before && noProgress(record.attempts) >= state.config.limits.maxNoProgress) { block('No-progress cap reached; initialize a new run after reviewing evidence'); continue; }
      const number = record.attempts.length + 1;
      const log = `logs/${check.id}-${number}.log`;
      const attempt = { number, fingerprint: before, startedAt: new Date().toISOString(), status: 'blocked', reason: 'Execution interrupted or still running', log };
      record.attempts.push(attempt); record.status = attempt.status; record.reason = attempt.reason; save();
      const result = await execute(state, check, path.join(directory, log), Math.min(check.timeoutMs, remaining), control, owner.child);
      try {
        if (before !== fingerprint(state, check)) { result.status = 'blocked'; result.reason = 'Inputs changed during execution; rerun to obtain consistent evidence'; }
      } catch (error) { result.status = 'blocked'; result.reason = `Inputs unavailable after execution: ${error.message}`; }
      Object.assign(attempt, result, { finishedAt: new Date().toISOString() });
      record.status = result.status; record.reason = result.reason; save();
    }
    const report = inspect(state);
    state.status = report.status; state.readyToArchive = report.readyToArchive; save();
    atomic(path.join(directory, 'report.json'), report);
    return report;
  } finally { process.removeListener('SIGTERM', term); process.removeListener('SIGINT', int); owner.release(); }
}

function init(args) {
  const configPath = path.resolve(args.shift() ?? fail('init requires a config file'));
  let project = process.cwd(), directory;
  while (args.length) {
    const flag = args.shift(), value = args.shift();
    if (!value) fail(`Missing value for ${flag}`);
    if (flag === '--project') project = path.resolve(value);
    else if (flag === '--state') directory = path.resolve(value);
    else fail(`Unknown option: ${flag}`);
  }
  project = fs.realpathSync(project);
  const config = normalize(json(configPath), project);
  const runId = new Date().toISOString().replace(/[:.]/g, '-') + '-' + crypto.randomUUID().slice(0, 8);
  directory ??= path.join(project, '.specdrive', runId);
  fs.mkdirSync(path.dirname(directory), { recursive: true });
  fs.mkdirSync(directory);
  directory = fs.realpathSync(directory);
  fs.mkdirSync(path.join(directory, 'logs'));
  const state = { version: 1, runId, projectRoot: project, evidenceRoot: directory, configPath, config, createdAt: new Date().toISOString(), elapsedMs: 0, status: 'blocked', readyToArchive: false, checks: Object.fromEntries(config.checks.map(check => [check.id, { status: 'blocked', reason: 'Not run', attempts: [] }])) };
  atomic(path.join(directory, 'state.json'), state);
  return { stateDirectory: directory, ...inspect(state) };
}

async function main() {
  const [command, ...args] = process.argv.slice(2);
  if (command === '--help' || command === '-h' || !command) {
    console.log('Usage: specdrive init <config.json> [--project <dir>] [--state <dir>]\n       specdrive run|status|gate <state-dir>\nExit: 0 passed, 1 failed, 78 blocked, 2 usage/error. init/status exit 0.\nCheck argv runs directly (no shell). Exit 78 reports an unavailable prerequisite.');
    return;
  }
  let report;
  if (command === 'init') report = init(args);
  else {
    if (!['run', 'status', 'gate'].includes(command) || args.length !== 1) fail('Expected run|status|gate <state-dir>; use --help');
    const directory = fs.realpathSync(path.resolve(args[0]));
    report = command === 'run' ? await run(directory) : inspect(readState(directory));
  }
  console.log(JSON.stringify(report, null, 2));
  if (command === 'run' || command === 'gate') process.exitCode = report.status === 'passed' ? 0 : report.status === 'failed' ? 1 : 78;
}

main().catch(error => { console.error(JSON.stringify({ status: 'blocked', readyToArchive: false, error: error.message })); process.exitCode = 2; });
