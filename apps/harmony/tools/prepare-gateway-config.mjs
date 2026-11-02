#!/usr/bin/env node
import { closeSync, constants, fchmodSync, fstatSync, fsyncSync, ftruncateSync, lstatSync, mkdirSync, openSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const GATEWAY_BASE_URL = 'https://milomood.xyz';
const OUTPUT_FILE = fileURLToPath(new URL('../entry/src/main/resources/rawfile/gateway-credentials.local.json', import.meta.url));

/** Read only the gateway bearer token; provider keys are never copied. */
export function gatewayCredentialFromEnv(source) {
  const matches = source.split(/\r?\n/)
    .map((line) => line.match(/^\s*(?:export\s+)?GATEWAY_BEARER_TOKEN\s*=\s*(.*?)\s*$/))
    .filter(Boolean);
  if (matches.length !== 1) {
    throw new Error('The env file must define GATEWAY_BEARER_TOKEN exactly once.');
  }
  let token = matches[0][1];
  if (token.startsWith('"') || token.startsWith("'")) {
    const quote = token[0];
    const end = token.indexOf(quote, 1);
    if (end < 0 || !/^\s*(?:#.*)?$/.test(token.slice(end + 1))) {
      throw new Error('GATEWAY_BEARER_TOKEN has invalid quoting.');
    }
    token = token.slice(1, end);
  } else {
    token = token.replace(/\s+#.*$/, '').trim();
  }
  if (token.length < 32 || token.length > 4096 || !/^[A-Za-z0-9._~+\/-]+=*$/.test(token)) {
    throw new Error('GATEWAY_BEARER_TOKEN must contain 32–4096 valid bearer-token characters.');
  }
  return { schemaVersion: 1, gatewayBaseUrl: GATEWAY_BASE_URL, gatewayBearerToken: token };
}

export function writeGatewayCredential(outputFile, credential) {
  const content = `${JSON.stringify(credential, null, 2)}\n`;
  try {
    // lstat sees dangling links too; existsSync follows them and would miss them.
    if (!lstatSync(outputFile).isFile()) {
      throw new Error('Refusing to overwrite a non-regular file at the credential resource path.');
    }
  } catch (error) {
    if (error?.code !== 'ENOENT') throw error;
  }
  mkdirSync(dirname(outputFile), { recursive: true });
  let descriptor;
  try {
    // Also prevent a link substitution between lstat and open. Do not truncate first.
    descriptor = openSync(outputFile, constants.O_WRONLY | constants.O_CREAT | constants.O_NOFOLLOW | constants.O_NONBLOCK, 0o600);
    if (!fstatSync(descriptor).isFile()) {
      throw new Error('Refusing to overwrite a non-regular file at the credential resource path.');
    }
    fchmodSync(descriptor, 0o600);
    ftruncateSync(descriptor, 0);
    writeFileSync(descriptor, content);
    fsyncSync(descriptor);
  } catch (error) {
    if (error?.code === 'ELOOP') {
      throw new Error('Refusing to overwrite a symbolic link at the credential resource path.');
    }
    throw error;
  } finally {
    if (descriptor !== undefined) closeSync(descriptor);
  }
}

function main(args) {
  if (args.length === 1 && args[0] === '--help') {
    console.log('Usage: node tools/prepare-gateway-config.mjs --env-file /absolute/path/to/gateway.env');
    console.log('Creates a gitignored credential resource for local device-test builds. Never copies MINIMAX_API_KEY.');
    return;
  }
  if (args.length !== 2 || args[0] !== '--env-file' || !args[1]) {
    throw new Error('Pass the credential file explicitly with --env-file. Use --help for usage.');
  }
  let source;
  try { source = readFileSync(resolve(args[1]), 'utf8'); }
  catch { throw new Error('Could not read the supplied env file.'); }
  const credential = gatewayCredentialFromEnv(source);
  writeGatewayCredential(OUTPUT_FILE, credential);
  console.log(`Prepared local device-test gateway configuration for ${GATEWAY_BASE_URL}.`);
  console.log('The gateway token is bundled in this local test build; use user authentication before public distribution.');
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try { main(process.argv.slice(2)); }
  catch (error) {
    // Print only our fixed validation messages, never env content or raw I/O errors.
    if (error instanceof Error && /^(The env file|GATEWAY_BEARER_TOKEN|Pass the credential|Could not read|Refusing to overwrite)/.test(error.message)) {
      console.error(error.message);
    } else {
      console.error('Could not prepare the local gateway credential resource.');
    }
    process.exitCode = 1;
  }
}
