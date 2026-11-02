#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const ios = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const evidence = path.join(ios, 'evidence');
fs.mkdirSync(evidence, { recursive: true });
const blocked = reason => { console.error(`BLOCKED: ${reason}`); process.exit(78); };
const execute = (command, args, options = {}) => {
  const result = spawnSync(command, args, { cwd: ios, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024, ...options });
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} exited ${result.status ?? result.signal}`);
  return result.stdout;
};
const readJSON = file => JSON.parse(fs.readFileSync(file, 'utf8'));

function toolEnvironment() {
  const env = { ...process.env };
  if (!env.DEVELOPER_DIR && fs.existsSync('/Applications/Xcode.app/Contents/Developer')) {
    env.DEVELOPER_DIR = '/Applications/Xcode.app/Contents/Developer';
  }
  return env;
}

function xcodePreflight() {
  const env = toolEnvironment();
  try {
    const version = execute('xcodebuild', ['-version'], { env }).trim();
    const compiler = execute('swift', ['--version'], { env }).trim();
    const swiftVersion = compiler.match(/Swift version (\d+)\.(\d+)/);
    if (!swiftVersion || Number(swiftVersion[1]) < 6 || (Number(swiftVersion[1]) === 6 && Number(swiftVersion[2]) < 1)) blocked('The pinned test framework requires Swift 6.1 or later. Select a compatible Xcode.');
    const sdk = execute('xcrun', ['--sdk', 'iphonesimulator', '--show-sdk-version'], { env }).trim();
    const list = JSON.parse(execute('xcrun', ['simctl', 'list', 'devices', 'available', '--json'], { env }));
    const devices = Object.entries(list.devices).filter(([runtime]) => Number(runtime.match(/\.iOS-(\d+)/)?.[1] ?? 0) >= 17)
      .flatMap(([runtime, rows]) => rows.filter(row => row.isAvailable && row.name.includes('iPhone')).map(row => ({ ...row, runtime })));
    const requested = process.env.MILO_SIMULATOR_UDID;
    const device = requested ? devices.find(row => row.udid === requested) : [...devices].sort((a, b) => {
      const small = row => /mini|SE|16e|17e/.test(row.name) ? 0 : 1;
      return small(a) - small(b) || a.name.localeCompare(b.name);
    })[0];
    if (!device) blocked('No available iPhone simulator. Install an iOS runtime in Xcode and rerun.');
    const metadata = { version, compiler, sdk, device: { name: device.name, udid: device.udid, runtime: device.runtime }, developerDir: env.DEVELOPER_DIR ?? null };
    fs.writeFileSync(path.join(evidence, 'environment.json'), JSON.stringify(metadata, null, 2) + '\n');
    console.log(`Selected simulator: ${device.name} (${device.runtime})`);
  } catch (error) {
    blocked(`Full Xcode and an iOS simulator are required. ${error.message}`);
  }
}

function native(action) {
  const environmentFile = path.join(evidence, 'environment.json');
  if (!fs.existsSync(environmentFile)) blocked('Run xcode-preflight first.');
  const metadata = readJSON(environmentFile);
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const bundle = path.join(evidence, `${action}-${stamp}.xcresult`);
  const args = ['-project', 'Milo.xcodeproj', '-scheme', 'Milo', '-configuration', 'Debug', '-destination', `platform=iOS Simulator,id=${metadata.device.udid}`, '-derivedDataPath', 'DerivedData', '-resultBundlePath', bundle, 'CODE_SIGNING_ALLOWED=NO'];
  const env = { ...toolEnvironment(), ...(metadata.developerDir ? { DEVELOPER_DIR: metadata.developerDir } : {}) };
  if (action === 'ui-test') {
    // Finish simulator initialization before XCTest connects to accessibility services.
    // Use this recorded device, rather than a separately booted parallel-test clone.
    try {
      execute('xcrun', ['simctl', 'bootstatus', metadata.device.udid, '-b'], { env, timeout: 120000 });
      const developerDir = env.DEVELOPER_DIR ?? execute('xcode-select', ['-p'], { env }).trim();
      execute('open', ['-a', path.join(developerDir, 'Applications/Simulator.app'), '--args', '-CurrentDeviceUDID', metadata.device.udid], { env, timeout: 30000 });
    } catch (error) {
      blocked(`The selected simulator did not become ready for UI testing. ${error.message}`);
    }
    args.push('-parallel-testing-enabled', 'NO');
  }
  execute('xcodebuild', [...args, action === 'ui-test' ? 'test' : 'build'], { env });
  fs.writeFileSync(path.join(evidence, `${action}.json`), JSON.stringify({ bundle, environment: metadata, sourceHash: sourceHash(), finishedAt: new Date().toISOString() }, null, 2) + '\n');
}

function sourceHash() {
  const hash = crypto.createHash('sha256');
  const visit = relative => {
    const absolute = path.join(ios, relative);
    if (fs.statSync(absolute).isDirectory()) {
      for (const name of fs.readdirSync(absolute).sort()) {
        if (!['.build', '.swiftpm', 'xcuserdata'].includes(name)) visit(path.join(relative, name));
      }
    } else { hash.update(relative + '\0'); hash.update(fs.readFileSync(absolute)); }
  };
  for (const item of ['App', 'MiloCore', 'UITests', 'Resources', 'project.yml', 'Milo.xcodeproj/project.pbxproj', 'scripts/verify.mjs']) visit(item);
  return hash.digest('hex');
}

function visualReview() {
  const receipt = path.join(evidence, 'visual-review.json');
  if (!fs.existsSync(receipt)) blocked('No visual review receipt. Inspect actual simulator screenshots from xcresult; do not infer visual acceptance from source.');
  const value = readJSON(receipt);
  const ui = readJSON(path.join(evidence, 'ui-test.json'));
  if (value.sourceHash !== sourceHash() || ui.sourceHash !== sourceHash()) blocked('Visual/UI evidence is stale.');
  if (value.verdict !== 'pass' || !value.reviewer || !value.reviewedAt || value.bundle !== ui.bundle) blocked('Visual receipt must identify an independent reviewer, time, pass verdict and the actual UI result bundle.');
  for (const key of ['keyboardReachable', 'longChineseText', 'accessibilityText', 'lightAppearance', 'darkAppearance']) {
    if (value.checks?.[key] !== true) blocked(`Visual review incomplete: ${key}`);
  }
  const evidenceRoot = fs.realpathSync(evidence) + path.sep;
  const recordedFile = (file, isDirectory = false) => {
    try {
      if (typeof file !== 'string' || !path.isAbsolute(file)) return false;
      const real = fs.realpathSync(file);
      if (!real.startsWith(evidenceRoot)) return false;
      return isDirectory ? fs.statSync(real).isDirectory() : fs.statSync(real).isFile();
    } catch { return false; }
  };
  if (!Array.isArray(value.screenshots) || value.screenshots.length < 2 || value.screenshots.some(file => !recordedFile(file))) blocked('Actual exported screenshot files must be inside the fingerprinted evidence directory.');
  if (!recordedFile(ui.bundle, true)) blocked('UI result bundle must be inside the fingerprinted evidence directory.');
  console.log(`Visual review passed by ${value.reviewer}; ${value.screenshots.length} images, ${ui.bundle}`);
}

try {
  switch (process.argv[2]) {
    case 'xcode-preflight': xcodePreflight(); break;
    case 'build': native('build'); break;
    case 'ui-test': native('ui-test'); break;
    case 'visual-review': visualReview(); break;
    case 'source-hash': console.log(sourceHash()); break;
    default: throw new Error('Usage: node scripts/verify.mjs xcode-preflight|build|ui-test|visual-review|source-hash');
  }
} catch (error) { console.error(error.message); process.exitCode = 1; }
