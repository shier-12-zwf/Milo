#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { fingerprint, hashBuild } from './parity-evidence.mjs';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const action = process.argv[2];
const evidence = path.join(root, 'apps/ios/evidence/functional');
fs.mkdirSync(evidence, {recursive:true});
const stamp = new Date().toISOString().replace(/[:.]/g,'-');
const inputPaths = ['App','tests','UITests','Resources','MiloCore','project.yml','Milo.xcodeproj','scripts','agc-sdk-lock.json'].map(p=>'apps/ios/'+p);
const source = () => fingerprint(root,inputPaths).sourceHash;
const sha = data => crypto.createHash('sha256').update(data).digest('hex');
const run = (cmd,args) => spawnSync(cmd,args,{cwd:root,encoding:'utf8',maxBuffer:100*1024*1024});
const fail = message => {throw new Error(message);};
const appPath = 'apps/ios/DerivedData/Build/Products/Debug-iphonesimulator/Milo.app';
const productPath = path.join(root,'apps/ios/DerivedData/Build/Products/Debug-iphonesimulator');
function testBinary(name, directory=productPath) {
  const matches=[];
  function visit(dir) {
    for(const item of fs.readdirSync(dir,{withFileTypes:true})) {
      if(!item.isDirectory()) continue;
      const p=path.join(dir,item.name);
      if(item.name===name+'.xctest') { const binary=path.join(p,name); if(fs.existsSync(binary))matches.push(binary); }
      else visit(p);
    }
  }
  visit(directory);
  if(!matches.length) fail('Missing compiled test binary: '+name);
  const values=matches.map(p=>({path:path.relative(root,p),sha256:sha(fs.readFileSync(p))}));
  if(new Set(values.map(v=>v.sha256)).size!==1)fail('Compiled test copies disagree: '+name);
  return values[0];
}
let device;
try {
  const before=source();
  const receiptFile=path.join(evidence,'build.json');
  if(action==='build') {
    const install=run('python3',['apps/ios/scripts/install-agc-sdk.py','--verify']);
    if(install.status!==0)fail('Pinned SDK verification failed: '+install.stderr);
    const result=run(process.execPath,['apps/ios/scripts/parity-native.mjs','build']);
    const log=result.stdout+result.stderr;
    fs.writeFileSync(path.join(evidence,`build-${stamp}.log`),log);
    process.stdout.write(log);
    if(result.status!==0)process.exit(result.status||1);
    const bundle=run('plutil',['-extract','CFBundleIdentifier','raw','-o','-',path.join(root,appPath,'Info.plist')]);
    const kind=run('plutil',['-extract','CFBundlePackageType','raw','-o','-',path.join(root,appPath,'Info.plist')]);
    if(bundle.stdout.trim()!=='com.milo.echoes.ios'||kind.stdout.trim()!=='APPL')fail('Built application has wrong bundle identity/type.');
    if(source()!==before)fail('Inputs changed during build.');
    const receipt={sourceHash:before,app:{path:appPath,sha256:hashBuild(root,appPath)},tests:{unit:testBinary('MiloAccountTests'),ui:testBinary('MiloUITests')},builtAt:new Date().toISOString(),bundleIdentifier:bundle.stdout.trim(),bundleType:kind.stdout.trim()};
    fs.writeFileSync(receiptFile,JSON.stringify(receipt,null,2)+'\n');
    fs.writeFileSync(path.join(evidence,`build-${stamp}.json`),JSON.stringify(receipt,null,2)+'\n');
    console.log('Built the actual AGC-linked app and both current test binaries.');
  } else if(action==='account-tests'||action==='account-ui') {
    const receipt=JSON.parse(fs.readFileSync(receiptFile,'utf8'));
    if(receipt.sourceHash!==before||receipt.app.sha256!==hashBuild(root,appPath))fail('Current source or app does not match the prepared build.');
    const env=JSON.parse(fs.readFileSync(path.join(root,'apps/ios/evidence/parity/environment.json'),'utf8'));
    device=env.device.udid;
    // Only the dedicated test runner is removed. Product data stays in place.
    run('xcrun',['simctl','terminate',device,'com.milo.echoes.ios.uitests.xctrunner']);
    run('xcrun',['simctl','uninstall',device,'com.milo.echoes.ios.uitests.xctrunner']);
    run('xcrun',['simctl','terminate',device,'com.milo.echoes.ios']);
    if(action==='account-ui')run('xcrun',['simctl','status_bar',device,'override','--time','09:41','--batteryState','charged','--batteryLevel','100']);
    const resultBundle=path.join(evidence,`${action}-${stamp}.xcresult`);
    const args=['-project','apps/ios/Milo.xcodeproj','-scheme','Milo','-configuration','Debug','-destination',`platform=iOS Simulator,id=${device}`,'-derivedDataPath','apps/ios/DerivedData','-resultBundlePath',resultBundle,'CODE_SIGNING_ALLOWED=YES', 'CODE_SIGN_IDENTITY=-','-parallel-testing-enabled','NO','-only-testing:'+(action==='account-tests'?'MiloAccountTests':'MiloUITests/AccountFunctionalTests'),'test-without-building'];
    const result=run('xcodebuild',args);
    const log=result.stdout+result.stderr;
    const logPath=path.join(evidence,`${action}-${stamp}.log`);
    fs.writeFileSync(logPath,log);
    const actual=[...log.matchAll(/MILO_LOADED_TEST_BUNDLE_SHA256=([a-f0-9]{64})/g)].map(m=>m[1]);
    const expected=receipt.tests[action==='account-tests'?'unit':'ui'].sha256;
    const provenanceOK=actual.length>0&&actual.every(h=>h===expected);
    const report={action,sourceHash:before,app:receipt.app,expectedTestHash:expected,loadedTestHashes:actual,provenanceOK,exitCode:result.status,log:path.relative(root,logPath),logHash:sha(log),resultBundle:path.relative(root,resultBundle),device,finishedAt:new Date().toISOString()};
    fs.writeFileSync(path.join(evidence,`${action}-${stamp}.json`),JSON.stringify(report,null,2)+'\n');
    console.log(`${action}: exit ${result.status}; loaded test provenance ${provenanceOK}; ${path.relative(root,logPath)}`);
    if(result.status!==0) {console.error(log.slice(-14000));process.exitCode=result.status||1;}
    else if(!provenanceOK)fail('Loaded test binary was missing or did not match the compiled binary.');
    else if(source()!==before||receipt.app.sha256!==hashBuild(root,appPath))fail('Source/app changed during verification.');
    else console.log('Actual test bundle matches current build; tests passed.');
  } else fail('Expected build/account-tests/account-ui');
} catch(error) {console.error(error.message);process.exitCode=1;}
finally {if(device)run('xcrun',['simctl','status_bar',device,'clear']);}
