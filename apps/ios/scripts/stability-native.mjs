#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawnSync, spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {fingerprint, hashBuild} from './parity-evidence.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const action = process.argv[2];
const evidence = path.join(root, 'apps/ios/evidence/stability');
const derived = 'apps/ios/DerivedData/stability';
const appPath = `${derived}/Build/Products/Debug-iphonesimulator/Milo.app`;
const products = path.dirname(path.join(root, appPath));
const inputs = ['App','tests','UITests','Resources','MiloCore','project.yml','Milo.xcodeproj','scripts','agc-sdk-lock.json'].map(p => `apps/ios/${p}`);
const stamp = new Date().toISOString().replace(/[:.]/g, '-');
fs.mkdirSync(evidence, {recursive:true});
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const source = () => fingerprint(root, inputs).sourceHash;
const run = (command, args) => spawnSync(command, args, {cwd:root, encoding:'utf8', maxBuffer:100*1024*1024});
const checked = (command, args) => {
  const result = run(command, args);
  if (result.status !== 0) throw new Error(`${command} exited ${result.status}: ${result.stderr || result.stdout}`);
  return result;
};
const save = (name, data) => fs.writeFileSync(path.join(evidence, name), JSON.stringify(data, null, 2)+'\n');
const read = name => JSON.parse(fs.readFileSync(path.join(evidence, name), 'utf8'));
const requireTrue = (value, message) => { if (!value) throw new Error(message); };
function testBinary(name) {
  const files = [];
  const visit = directory => {
    for (const item of fs.readdirSync(directory, {withFileTypes:true})) {
      if (!item.isDirectory()) continue;
      const full = path.join(directory, item.name);
      if (item.name === `${name}.xctest`) files.push(path.join(full, name));
      else visit(full);
    }
  };
  visit(products);
  requireTrue(files.length, `Missing ${name} binary`);
  const copies = files.map(file => ({path:path.relative(root,file), sha256:sha(fs.readFileSync(file))}));
  requireTrue(new Set(copies.map(item=>item.sha256)).size === 1, `Different ${name} binary copies`);
  return copies[0];
}
function prepared() {
  const receipt = read('build.json');
  requireTrue(receipt.sourceHash === source(), 'Source changed since the prepared build');
  requireTrue(receipt.app.sha256 === hashBuild(root,appPath), 'Prepared app bytes changed');
  return receipt;
}
function installed(device, receipt) {
  const full = checked('xcrun',['simctl','get_app_container',device,'com.milo.echoes.ios','app']).stdout.trim();
  // The installed bundle is outside the source workspace but is read-only here.
  const hashes = fingerprint(full,fs.readdirSync(full).sort(),{ignoreGenerated:false});
  requireTrue(hashes.sourceHash === receipt.app.sha256, 'Installed app does not match verified build');
  return {sha256:hashes.sourceHash, path:full};
}
function persistentFiles(container) {
  const files = {};
  for (const relative of ['Documents', 'Library/Application Support']) {
    const directory=path.join(container,relative);
    if (!fs.existsSync(directory)) continue;
    const walk = current => {
      for (const item of fs.readdirSync(current,{withFileTypes:true})) {
        const full=path.join(current,item.name);
        requireTrue(!item.isSymbolicLink(),'Unexpected symbolic link in persistent data');
        if(item.isDirectory()) walk(full);
        else if(item.isFile()) files[path.relative(container,full)]=sha(fs.readFileSync(full));
      }
    };
    walk(directory);
  }
  return Object.fromEntries(Object.entries(files).sort());
}
let device;
let video;
try {
  if (action === 'preflight') {
    const xcode = checked('xcodebuild',['-version']).stdout.trim();
    const sdk = checked('xcrun',['--sdk','iphonesimulator','--show-sdk-version']).stdout.trim();
    const all = JSON.parse(checked('xcrun',['simctl','list','devices','available','--json']).stdout).devices;
    const devices = Object.entries(all).filter(([runtime])=>runtime.includes('iOS')).flatMap(([runtime,items])=>items.map(item=>({...item,runtime})));
    const selected = devices.find(d=>d.state==='Booted' && /iPhone/.test(d.name)) || devices.find(d=>/iPhone.*17e|iPhone.*16e/.test(d.name)) || devices.find(d=>/iPhone/.test(d.name));
    if (!selected) { console.error('An available iPhone simulator is required.'); process.exit(78); }
    checked('xcrun',['simctl','bootstatus',selected.udid,'-b']);
    save('environment.json',{xcode,sdk,device:selected,capturedAt:new Date().toISOString()});
    console.log(`${xcode}; iOS SDK ${sdk}; ${selected.name}`);
  } else if (action === 'build') {
    checked('python3',['apps/ios/scripts/install-agc-sdk.py','--verify']);
    device = read('environment.json').device.udid;
    const before = source();
    const resultBundle = path.join(evidence,`build-${stamp}.xcresult`);
    const args = ['-project','apps/ios/Milo.xcodeproj','-scheme','Milo','-configuration','Debug','-destination',`platform=iOS Simulator,id=${device}`,'-derivedDataPath',derived,'-resultBundlePath',resultBundle,'CODE_SIGNING_ALLOWED=YES','CODE_SIGN_IDENTITY=-','-parallel-testing-enabled','NO','-jobs','2','build-for-testing'];
    const result = run('xcodebuild',args);
    const log = result.stdout+result.stderr;
    fs.writeFileSync(path.join(evidence,`build-${stamp}.log`),log);
    requireTrue(result.status === 0, `Build failed (${result.status}):\n${log.slice(-16000)}`);
    requireTrue(source() === before, 'Source changed during build');
    const plist = JSON.parse(checked('plutil',['-convert','json','-o','-',path.join(root,appPath,'Info.plist')]).stdout);
    requireTrue(plist.CFBundleIdentifier === 'com.milo.echoes.ios' && plist.CFBundlePackageType === 'APPL' && plist.DTPlatformName === 'iphonesimulator', 'Invalid simulator bundle identity');
    requireTrue(plist.CFBundleIcons?.CFBundlePrimaryIcon?.CFBundleIconName === 'AppIcon', 'Compiled AppIcon is missing');
    requireTrue(fs.existsSync(path.join(root,appPath,'Assets.car')), 'Compiled asset catalog is missing');
    const signature = checked('codesign',['-d','--entitlements','-',path.join(root,appPath)]);
    const hostEntitlements = signature.stdout+signature.stderr;
    requireTrue(!/application-identifier|keychain-access-groups/.test(hostEntitlements), 'Restricted iOS permissions in host ad-hoc signature');
    checked('codesign',['--verify','--deep','--strict',path.join(root,appPath)]);
    const segments = ['Milo','Milo.debug.dylib'].filter(name=>fs.existsSync(path.join(root,appPath,name))).map(name=>({name,output:checked('otool',['-l',path.join(root,appPath,name)]).stdout}));
    requireTrue(segments.some(item=>item.output.includes('sectname __entitlements')), 'Xcode simulated entitlement section is missing');
    fs.writeFileSync(path.join(evidence,`signing-${stamp}.txt`),hostEntitlements+'\n'+segments.map(item=>item.name+'\n'+item.output).join('\n'));
    const receipt = {sourceHash:before,app:{path:appPath,sha256:hashBuild(root,appPath)},tests:{unit:testBinary('MiloAccountTests'),ui:testBinary('MiloUITests')},device,command:['xcodebuild',...args],logHash:sha(log),builtAt:new Date().toISOString(),icon:plist.CFBundleIcons.CFBundlePrimaryIcon};
    save('build.json',receipt);save(`build-${stamp}.json`,receipt);
    console.log('Xcode-signed simulator build, icon and simulated permissions verified.');
  } else if (action === 'install') {
    const receipt = prepared();device=receipt.device;
    // No uninstall: replacing only the application preserves its data container.
    const oldContainer = run('xcrun',['simctl','get_app_container',device,'com.milo.echoes.ios','data']).stdout.trim();
    const beforeFiles=oldContainer?persistentFiles(oldContainer):{};
    const backup=path.join(evidence,`data-backup-${stamp}`);
    if(oldContainer) {
      fs.mkdirSync(backup,{recursive:true});
      for(const relative of ['Documents','Library/Application Support']) {
        const original=path.join(oldContainer,relative);
        if(fs.existsSync(original))fs.cpSync(original,path.join(backup,relative),{recursive:true,preserveTimestamps:true});
      }
      requireTrue(JSON.stringify(persistentFiles(backup))===JSON.stringify(beforeFiles),'Data backup verification failed');
    }
    save(`install-before-${stamp}.json`,{sourceHash:receipt.sourceHash,oldContainer,files:beforeFiles,backup:path.relative(root,backup)});
    checked('xcrun',['simctl','install',device,path.join(root,appPath)]);
    const actual = installed(device,receipt);
    const newContainer = checked('xcrun',['simctl','get_app_container',device,'com.milo.echoes.ios','data']).stdout.trim();
    // CoreSimulator may rename/migrate the data container during an update.
    // Verify every persisted byte rather than requiring the UUID to stay fixed.
    const afterFiles=persistentFiles(newContainer);
    requireTrue(Object.entries(beforeFiles).every(([file,hash])=>afterFiles[file]===hash),'Existing persisted data changed; verified backup retained');
    const launched = checked('xcrun',['simctl','launch','--terminate-running-process',device,'com.milo.echoes.ios']);
    save(`install-${stamp}.json`,{sourceHash:receipt.sourceHash,app:actual,oldContainer,newContainer,dataContainerRenamed:!!oldContainer&&oldContainer!==newContainer,persistedFilesPreserved:Object.keys(beforeFiles).length,files:beforeFiles,backup:path.relative(root,backup),launch:launched.stdout.trim(),at:new Date().toISOString()});
    console.log('Verified app replaced the broken installation; original data container retained; normal launch accepted. UI checks must still prove visible stability.');
  } else if (['unit','launch','accounts','journeys','motion','capture','speech','keyboard','voice'].includes(action)) {
    const receipt = prepared();device=receipt.device;
    run('xcrun',['simctl','terminate',device,'com.milo.echoes.ios.uitests.xctrunner']);
    run('xcrun',['simctl','uninstall',device,'com.milo.echoes.ios.uitests.xctrunner']);
    run('xcrun',['simctl','terminate',device,'com.milo.echoes.ios']);
    if (action!=='unit') checked('xcrun',['simctl','status_bar',device,'override','--time','09:41','--batteryState','charged','--batteryLevel','100']);
    const selection = {unit:'MiloAccountTests',launch:'MiloUITests/LaunchStabilityTests',accounts:'MiloUITests/AccountFunctionalTests',journeys:'MiloUITests/MiloUITests',motion:'MiloUITests/GalaxyMotionTests',capture:'MiloUITests/ParityCaptureTests',speech:'MiloUITests/SpeechInputUITests',keyboard:'MiloUITests/SpeechInputUITests/testCVisibleKeyboardAppendAndSend',voice:'MiloUITests/SpeechInputUITests/testDRealRecordingRemainsActive'}[action];
    const resultBundle=path.join(evidence,`${action}-${stamp}.xcresult`);
    let videoPath;
    if (action==='motion') {
      videoPath=path.join(evidence,`motion-${stamp}.mp4`);
      video=spawn('xcrun',['simctl','io',device,'recordVideo','--codec=h264',videoPath],{stdio:'ignore'});
    }
    const args=['-project','apps/ios/Milo.xcodeproj','-scheme','Milo','-configuration','Debug','-destination',`platform=iOS Simulator,id=${device}`,'-derivedDataPath',derived,'-resultBundlePath',resultBundle,'CODE_SIGNING_ALLOWED=YES','CODE_SIGN_IDENTITY=-','-parallel-testing-enabled','NO',`-only-testing:${selection}`,'test-without-building'];
    const result=run('xcodebuild',args);
    if(video) {const end=new Promise(resolve=>video.once('exit',resolve));video.kill('SIGINT');await end;video=undefined;}
    const log=result.stdout+result.stderr;
    const logPath=path.join(evidence,`${action}-${stamp}.log`);fs.writeFileSync(logPath,log);
    const hashes=[...log.matchAll(/MILO_LOADED_TEST_BUNDLE_SHA256=([a-f0-9]{64})/g)].map(match=>match[1]);
    const expected=receipt.tests[action==='unit'?'unit':'ui'].sha256;
    const provenanceOK=hashes.length>0&&hashes.every(value=>value===expected);
    const report={action,sourceHash:receipt.sourceHash,app:receipt.app,expectedTestHash:expected,loadedTestHashes:hashes,provenanceOK,exitCode:result.status,log:path.relative(root,logPath),logHash:sha(log),resultBundle:path.relative(root,resultBundle),device,finishedAt:new Date().toISOString()};
    if(videoPath&&fs.existsSync(videoPath))report.video={path:path.relative(root,videoPath),sha256:sha(fs.readFileSync(videoPath))};
    save(`${action}-${stamp}.json`,report);save(`${action}.json`,report);
    console.log(`${action}: exit ${result.status}, current test bundle ${provenanceOK}, ${report.log}`);
    requireTrue(result.status===0,log.slice(-16000));
    requireTrue(provenanceOK,'No current loaded-test provenance');
    requireTrue(source()===receipt.sourceHash&&hashBuild(root,appPath)===receipt.app.sha256,'Source/build changed during tests');
    report.installed=installed(device,receipt);save(`${action}-${stamp}.json`,report);save(`${action}.json`,report);
  } else throw new Error('Expected preflight/build/install/unit/launch/accounts/journeys/motion/capture/speech');
} catch(error) {console.error(error.message);process.exitCode=1;}
finally {
  if(video)video.kill('SIGINT');
  if(device)run('xcrun',['simctl','status_bar',device,'clear']);
}
