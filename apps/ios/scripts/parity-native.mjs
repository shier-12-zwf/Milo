#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync, spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { hashIOSSource, hashBuild, fingerprint } from './parity-evidence.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const action = process.argv[2];
const evidence = path.join(root, 'apps/ios/evidence/parity');
fs.mkdirSync(evidence, { recursive: true });
const stamp = new Date().toISOString().replace(/[:.]/g, '-');
const sha = data => crypto.createHash('sha256').update(data).digest('hex');
const blocked = reason => { console.error(`BLOCKED: ${reason}`); process.exit(78); };
const run = (command, args, cwd = root) => {
    const result = spawnSync(command, args, { cwd, encoding: 'utf8', maxBuffer: 80 * 1024 * 1024 });
    if (result.error) throw result.error;
    return result;
};
const json = file => JSON.parse(fs.readFileSync(file, 'utf8'));
try {
    if (action === 'preflight') {
        const version = run('xcodebuild', ['-version']);
        const compiler = run('swift', ['--version']);
        const devices = run('xcrun', ['simctl', 'list', 'devices', 'available', '--json']);
        const runtimes = run('xcrun', ['simctl', 'list', 'runtimes', '--json']);
        if ([version, compiler, devices, runtimes].some(result => result.status !== 0)) blocked('Full Xcode and an available iOS Simulator are required.');
        const available = Object.entries(JSON.parse(devices.stdout).devices).filter(([runtime]) => runtime.includes('iOS')).flatMap(([runtime, list]) => list.filter(d => d.isAvailable && d.name.startsWith("iPhone")).map(d => ({ ...d, runtime })));
        const device = available.sort((a, b) => Number(!/17e|16e|SE|mini/.test(a.name)) - Number(!/17e|16e|SE|mini/.test(b.name)) || a.name.localeCompare(b.name))[0];
        if (!device) blocked('Install an iOS runtime before native checks.');
        fs.writeFileSync(path.join(evidence, 'environment.json'), JSON.stringify({ capturedAt: new Date().toISOString(), version: version.stdout.trim(), compiler: compiler.stdout.trim(), device, runtimes: JSON.parse(runtimes.stdout).runtimes }, null, 2) + '\n');
        console.log(`${version.stdout.trim()}; ${device.name} (${device.runtime})`);
        process.exit(0);
    }
    if (action === 'parity-gate') {
        const result = run(process.execPath, ['apps/ios/scripts/parity-evidence.mjs', 'validate']);
        process.stdout.write(result.stdout); process.stderr.write(result.stderr);
        if (result.status !== 0) blocked('All required paired screenshots, source-bound build receipts and independent reviews must be complete.');
        process.exit(0);
    }
    if (action === 'external-auth') {
        blocked('Bundle-matching iOS AGC configuration and owner-driven account verification have not been evidenced. The real SDK adapter is implemented. Local owner/DEBUG fixtures are not remote authentication.');
    }
    if (!['build', 'journeys', 'capture', 'motion', 'harmony-build'].includes(action)) throw new Error('Expected preflight/build/journeys/capture/harmony-build/parity-gate/external-auth');
    let buildRoot = root, command, args, buildPath, before, sourceManifest, priorBuild;
    if (action === 'harmony-build') {
        sourceManifest = json(path.join(root, 'docs/visual-parity/harmony-source.json'));
        buildRoot = sourceManifest.referenceRoot;
        before = fingerprint(buildRoot, ['apps/harmony/entry/src/main', 'apps/harmony/AppScope']).sourceHash;
        buildPath = sourceManifest.build.path;
        command = './hvigorw'; args = ['assembleHap'];
    } else {
        const environmentFile = path.join(evidence, 'environment.json');
        if (!fs.existsSync(environmentFile)) blocked('Run preflight first.');
        const env = json(environmentFile);
        const boot = run('xcrun', ['simctl', 'bootstatus', env.device.udid, '-b']);
        if (boot.status !== 0) blocked('Selected iOS simulator did not boot.');
        if (action !== 'build') {
            const statusBar = run('xcrun', ['simctl', 'status_bar', env.device.udid, 'override', '--time', '09:41', '--dataNetwork', 'wifi', '--wifiMode', 'active', '--wifiBars', '3', '--cellularMode', 'active', '--cellularBars', '4', '--batteryState', 'charged', '--batteryLevel', '100']);
            if (statusBar.status !== 0) blocked('Could not establish the deterministic screenshot status bar.');
        }
        before = hashIOSSource(root).sourceHash;
        buildPath = 'apps/ios/DerivedData/Build/Products/Debug-iphonesimulator/Milo.app';
        if (action !== 'build') {
            const priorFile = path.join(evidence, 'build.json');
            if (!fs.existsSync(priorFile)) blocked('Build the current app and test runner before executing native tests.');
            priorBuild = json(priorFile);
            if (priorBuild.sourceHash !== before || priorBuild.build.sha256 !== hashBuild(root, buildPath)) {
                blocked('The prepared test build is stale; rebuild before capturing current screenshots.');
            }
        }
        command = 'xcodebuild';
        args = ['-project', 'apps/ios/Milo.xcodeproj', '-scheme', 'Milo', '-configuration', 'Debug', '-destination', `platform=iOS Simulator,id=${env.device.udid}`, '-derivedDataPath', 'apps/ios/DerivedData', '-resultBundlePath', path.join(evidence, `${action}-${stamp}.xcresult`), 'CODE_SIGNING_ALLOWED=YES', 'CODE_SIGN_IDENTITY=-', '-parallel-testing-enabled', 'NO', '-jobs', '2'];
        if (action !== 'build') args.push('-only-testing:MiloUITests/' + (action === 'capture' ? 'ParityCaptureTests' : action === 'motion' ? 'GalaxyMotionTests' : 'MiloUITests'));
        args.push(action === 'build' ? 'build-for-testing' : 'test-without-building');
    }
    let video;
    let videoPath;
    if (action === 'motion') {
        const env = json(path.join(evidence, 'environment.json'));
        videoPath = path.join(evidence, `motion-${stamp}.mp4`);
        video = spawn('xcrun', ['simctl', 'io', env.device.udid, 'recordVideo', '--codec=h264', videoPath], { stdio: 'ignore' });
    }
    const startedAt = new Date().toISOString();
    const result = run(command, args, action === 'harmony-build' ? path.join(buildRoot, 'apps/harmony') : buildRoot);
    if (video) {
        const stopped = new Promise(resolve => video.once('exit', resolve));
        video.kill('SIGINT');
        await stopped;
    }
    const finishedAt = new Date().toISOString();
    const logText = result.stdout + result.stderr;
    const logRelative = action === 'harmony-build' ? `apps/harmony/entry/build/parity-logs/${action}-${stamp}.log` : `apps/ios/evidence/parity/${action}-${stamp}.log`;
    fs.mkdirSync(path.dirname(path.join(buildRoot, logRelative)), { recursive: true });
    fs.writeFileSync(path.join(buildRoot, logRelative), logText);
    console.log(`Native ${action}: exit ${result.status}; log ${path.join(buildRoot, logRelative)}`);
    if (result.status !== 0) { console.error(logText.slice(-18000)); process.exit(result.status || 1); }
    const after = action === 'harmony-build' ? fingerprint(buildRoot, ['apps/harmony/entry/src/main', 'apps/harmony/AppScope']).sourceHash : hashIOSSource(root).sourceHash;
    if (before !== after) blocked('Source changed while native verification ran; preserving this log without approving stale evidence.');
    const buildHash = hashBuild(buildRoot, buildPath);
    if (priorBuild && buildHash !== priorBuild.build.sha256) blocked('The tested app differs from the prepared build.');
    const receipt = { sourceHashBefore: before, sourceHashAfter: after, buildHash, command: [command, ...args], startedAt, finishedAt, exitCode: 0, log: { path: logRelative, sha256: sha(Buffer.from(logText)) } };
    if (videoPath && fs.existsSync(videoPath)) receipt.video = {path: path.relative(root, videoPath), sha256: sha(fs.readFileSync(videoPath))};
    if (action === 'harmony-build') {
        if (before !== sourceManifest.sourceHash) blocked('Harmony reference changed; review and refresh the baseline before capture.');
        sourceManifest.build.sha256 = buildHash;
        sourceManifest.buildReceipt = receipt;
        fs.writeFileSync(path.join(root, 'docs/visual-parity/harmony-source.json'), JSON.stringify(sourceManifest, null, 2) + '\n');
    } else {
        // Screenshots are made during tests, after the prepared build completed.
        // A test-completion timestamp must never be presented as their build time.
        const provenance = priorBuild
            ? { ...priorBuild, verificationReceipt: receipt }
            : { version: 1, sourceHash: after, build: { path: buildPath, sha256: buildHash }, buildReceipt: receipt };
        fs.writeFileSync(path.join(evidence, `${action}.json`), JSON.stringify(provenance, null, 2) + '\n');
        fs.writeFileSync(path.join(root, 'docs/visual-parity/ios-source-build.json'), JSON.stringify(provenance, null, 2) + '\n');
    }
} catch (error) { console.error(error.message); process.exitCode = 1; }
