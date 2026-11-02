#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const script = fileURLToPath(import.meta.url);
const ios = path.resolve(path.dirname(script), '..');
const reviewChecks = ['keyboardReachable', 'longChineseText', 'accessibilityText', 'lightAppearance', 'darkAppearance'];
const sha256 = data => crypto.createHash('sha256').update(data).digest('hex');

function recordedPath(root, relative, directory = false) {
  if (typeof relative !== 'string' || !relative || path.isAbsolute(relative)) throw new Error('Evidence paths must be relative');
  const absolute = path.resolve(root, relative);
  if (!absolute.startsWith(root + path.sep)) throw new Error('Evidence path escapes the evidence directory');
  const real = fs.realpathSync(absolute);
  if (!real.startsWith(root + path.sep)) throw new Error('Evidence symlink escapes the evidence directory');
  const stat = fs.statSync(real);
  if (directory ? !stat.isDirectory() : !stat.isFile()) throw new Error('Evidence has an unexpected file type');
  return real;
}

/** Bind a real external review to this exact CI run and its unchanged image bytes. */
export function validateReceipt(receipt, context) {
  const { runId, headSha, ui, evidenceDirectory } = context;
  if (receipt?.version !== 1 || receipt.runId !== runId || receipt.headSha !== headSha || receipt.sourceHash !== ui.sourceHash) {
    throw new Error('Receipt belongs to a different run, revision, or source hash');
  }
  if (receipt.verdict !== 'pass' || typeof receipt.reviewer !== 'string' || !receipt.reviewer.trim() ||
      typeof receipt.reviewedAt !== 'string' || !Number.isFinite(Date.parse(receipt.reviewedAt))) {
    throw new Error('An identified independent reviewer must provide a dated pass verdict');
  }
  for (const key of reviewChecks) if (receipt.checks?.[key] !== true) throw new Error(`Review incomplete: ${key}`);
  const root = fs.realpathSync(evidenceDirectory);
  const bundle = recordedPath(root, receipt.bundle, true);
  if (!receipt.bundle.endsWith('.xcresult') || bundle !== fs.realpathSync(ui.bundle)) throw new Error('Receipt names a different UI result bundle');
  if (!Array.isArray(receipt.screenshots) || receipt.screenshots.length < 2) throw new Error('At least two reviewed screenshots are required');
  const seen = new Set();
  const screenshots = receipt.screenshots.map(item => {
    if (!/^[a-f0-9]{64}$/.test(item?.sha256 ?? '')) throw new Error('Screenshot SHA-256 is missing or invalid');
    const file = recordedPath(root, item.path);
    if (seen.has(file)) throw new Error('Reviewed screenshots must be distinct files');
    seen.add(file);
    if (sha256(fs.readFileSync(file)) !== item.sha256) throw new Error('Reviewed screenshot bytes do not match this run');
    return file;
  });
  return {
    version: 1, runId, headSha, sourceHash: ui.sourceHash,
    bundle, reviewer: receipt.reviewer, reviewedAt: receipt.reviewedAt, verdict: 'pass',
    checks: Object.fromEntries(reviewChecks.map(key => [key, true])), screenshots,
    reviewedScreenshots: receipt.screenshots,
  };
}

/** Injectable timing keeps the bounded polling behavior testable without network or sleeps. */
export async function awaitReceipt({ readReceipt, acceptReceipt, timeoutMs = 600000, intervalMs = 10000,
  now = Date.now, sleep = ms => new Promise(resolve => setTimeout(resolve, ms)), report = console.log }) {
  if (!Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 600000) throw new Error('Review wait must be between 1 ms and 10 minutes');
  if (!Number.isSafeInteger(intervalMs) || intervalMs < 1) throw new Error('Review polling interval must be positive');
  const deadline = now() + timeoutMs;
  let previousReason;
  while (now() < deadline) {
    try {
      const value = await readReceipt(Math.max(1, Math.min(15000, deadline - now())));
      if (now() >= deadline) break;
      const accepted = acceptReceipt(value);
      if (now() >= deadline) break;
      return accepted;
    } catch (error) {
      const reason = error.message || 'Review is not available';
      if (reason !== previousReason) { report(`Waiting for this run's independent visual review: ${reason}`); previousReason = reason; }
    }
    const remaining = deadline - now();
    if (remaining > 0) await sleep(Math.min(intervalMs, remaining));
  }
  return null;
}

async function main() {
  const { GITHUB_REPOSITORY: repository, GITHUB_TOKEN: token, GITHUB_RUN_ID: runId, GITHUB_SHA: headSha } = process.env;
  if (!/^[a-zA-Z0-9_.-]+\/[a-zA-Z0-9_.-]+$/.test(repository ?? '') || !/^\d+$/.test(runId ?? '') || !/^[a-f0-9]{40,64}$/.test(headSha ?? '') || !token) {
    throw new Error('GitHub repository, run ID, revision, and read token are required');
  }
  const evidenceDirectory = path.join(ios, 'evidence');
  const ui = JSON.parse(fs.readFileSync(path.join(evidenceDirectory, 'ui-test.json'), 'utf8'));
  const endpoint = `https://api.github.com/repos/${repository}/contents/receipt.json?ref=codex%2Fios-visual-receipts`;
  const receipt = await awaitReceipt({
    readReceipt: async timeoutMs => {
      const response = await fetch(endpoint, {
        headers: { Accept: 'application/vnd.github+json', Authorization: `Bearer ${token}`, 'X-GitHub-Api-Version': '2022-11-28' },
        signal: AbortSignal.timeout(timeoutMs), cache: 'no-store',
      });
      if (!response.ok) throw new Error(`Receipt is unavailable (HTTP ${response.status})`);
      const file = await response.json();
      if (file.type !== 'file' || file.encoding !== 'base64' || typeof file.content !== 'string') throw new Error('Receipt must be a JSON file');
      return JSON.parse(Buffer.from(file.content, 'base64').toString('utf8'));
    },
    acceptReceipt: value => validateReceipt(value, { runId, headSha, ui, evidenceDirectory }),
  });
  if (!receipt) {
    console.error('BLOCKED: No valid independent visual review arrived within 10 minutes. Existing native evidence is preserved.');
    process.exitCode = 78;
    return;
  }
  const output = path.join(evidenceDirectory, 'visual-review.json');
  const temporary = `${output}.${process.pid}.tmp`;
  try {
    fs.writeFileSync(temporary, JSON.stringify(receipt, null, 2) + '\n', { mode: 0o600 });
    fs.renameSync(temporary, output);
  } finally { fs.rmSync(temporary, { force: true }); }
  console.log(`Accepted independent visual review for run ${runId}; verified ${receipt.screenshots.length} screenshot hashes.`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === script) {
  main().catch(() => { console.error('BLOCKED: Visual review could not be retrieved or validated. No approval was written.'); process.exitCode = 78; });
}
