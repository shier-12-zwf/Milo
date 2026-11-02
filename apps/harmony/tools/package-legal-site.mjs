#!/usr/bin/env node
// Build-only: preserve the previously published Vercel output and add two legal pages.
// This script never invokes Vercel, builds the web app, or reads an environment file.
import { createHash } from 'node:crypto';
import { copyFileSync, lstatSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join, parse, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const repository = fileURLToPath(new URL('../../../', import.meta.url));
const defaultSource = join(repository, '.artifacts/vercel-web-release/deploy');
const defaultDestination = join(repository, '.artifacts/harmony-store-2026-10-11/vercel-deploy');
const markerName = '.milo-legal-package.json';
const legalDocuments = [
  { input: 'privacy-policy.txt', output: 'harmony-privacy.html', title: 'MILO 隐私政策' },
  { input: 'user-agreement.txt', output: 'harmony-agreement.html', title: 'MILO 用户协议' },
];

const sha256 = (content) => createHash('sha256').update(content).digest('hex');
const escapeHtml = (text) => text.replace(/&/g, '&amp;').replace(/</g, '&lt;')
  .replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');

function statIfPresent(path) {
  try { return lstatSync(path); }
  catch (error) { if (error.code === 'ENOENT') return undefined; throw error; }
}

function rejectSymlinkAncestors(path) {
  let current = parse(resolve(path)).root;
  for (const part of resolve(path).slice(current.length).split(sep).filter(Boolean)) {
    current = join(current, part);
    const stat = statIfPresent(current);
    if (stat?.isSymbolicLink()) throw new Error(`Refusing symbolic link: ${current}`);
  }
}

function regularFiles(directory) {
  rejectSymlinkAncestors(directory);
  if (!lstatSync(directory).isDirectory()) throw new Error(`Not a directory: ${directory}`);
  const files = [];
  for (const name of readdirSync(directory).sort()) {
    const path = join(directory, name);
    const stat = lstatSync(path);
    if (stat.isDirectory()) {
      for (const nested of regularFiles(path)) files.push(join(name, nested));
    } else if (stat.isFile()) files.push(name);
    else throw new Error(`Refusing non-regular source or output: ${path}`);
  }
  return files;
}

function linkedText(text) {
  const links = /https:\/\/[^\s<>]+|[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/giu;
  let result = '';
  let offset = 0;
  for (const match of text.matchAll(links)) {
    result += escapeHtml(text.slice(offset, match.index));
    const label = match[0];
    const href = label.startsWith('https://') ? label : `mailto:${label}`;
    result += `<a href="${escapeHtml(href)}" rel="noreferrer">${escapeHtml(label)}</a>`;
    offset = match.index + label.length;
  }
  return result + escapeHtml(text.slice(offset));
}

export function renderLegalPage(text, title) {
  if (!text.startsWith(`${title}\n`) || /\{\{|\}\}|YOUR_|待填写/.test(text)) {
    throw new Error(`Unexpected or unfinished canonical legal text: ${title}`);
  }
  const content = text.split('\n\n').map((paragraph, index) => {
    const tag = index === 0 ? 'h1' : /^[一二三四五六七八九十]+、[^\n]+$/.test(paragraph) ? 'h2' : 'p';
    return `<${tag}>${linkedText(paragraph)}</${tag}>`;
  }).join('\n\n');
  return `<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="referrer" content="no-referrer">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
<meta name="milo-legal-source-sha256" content="${sha256(text)}">
<title>${escapeHtml(title)} · 鸿蒙应用</title>
<style>
:root{color-scheme:light;font-family:-apple-system,BlinkMacSystemFont,"HarmonyOS Sans SC","PingFang SC","Microsoft YaHei",sans-serif;color:#242137;background:#f6f5fa;line-height:1.85}
*{box-sizing:border-box}body{margin:0}header,main,footer{width:min(100% - 40px,820px);margin:auto}header{padding:32px 0 22px}header strong{letter-spacing:.16em;color:#5c4794;font-size:23px}header span{display:block;color:#6d667e;font-size:14px;margin-top:4px}nav{display:flex;flex-wrap:wrap;gap:12px 24px;margin-top:20px}a{color:#563c91;text-decoration:underline;text-underline-offset:3px;overflow-wrap:anywhere}a:hover{color:#2d1b54}a:focus-visible{outline:3px solid #907ac5;outline-offset:5px}main{background:#fff;border:1px solid #e7e2ee;border-radius:16px;padding:32px 36px;box-shadow:0 8px 32px #30204507}h1{font-size:28px;line-height:1.5;margin:0 0 24px;letter-spacing:.02em}h2{font-size:20px;line-height:1.65;margin:32px 0 12px;color:#443564}p{white-space:pre-wrap;overflow-wrap:anywhere;margin:0 0 18px;font-size:16px}footer{font-size:13px;color:#716a7b;padding:22px 0 36px}@media(max-width:540px){header,main,footer{width:calc(100% - 28px)}main{padding:24px 20px}h1{font-size:25px}h2{font-size:19px}p{font-size:15px}}
@media print{body{background:#fff}header nav,footer{display:none}main{border:0;box-shadow:none;width:100%;padding:0}a{color:inherit}}
</style>
</head>
<body>
<header><strong>MILO</strong><span>鸿蒙应用 · 协议与隐私</span><nav aria-label="协议导航"><a href="/harmony-privacy.html">隐私政策</a><a href="/harmony-agreement.html">用户协议</a></nav></header>
<main><article id="legal-text">${content}</article></main>
<footer>全文与 MILO 鸿蒙应用内文档同源。本页无脚本、统计代码或第三方字体。</footer>
</body>
</html>
`;
}

export function extractLegalText(html) {
  const match = html.match(/<article id="legal-text">([\s\S]*?)<\/article>/);
  if (!match) throw new Error('Missing legal text article');
  return match[1].replace(/<[^>]*>/g, '')
    .replace(/&#39;/g, "'").replace(/&quot;/g, '"').replace(/&gt;/g, '>')
    .replace(/&lt;/g, '<').replace(/&amp;/g, '&');
}

export function packageLegalSite({ source = defaultSource, destination = defaultDestination } = {}) {
  source = resolve(source);
  destination = resolve(destination);
  if (destination === source || destination.startsWith(`${source}${sep}`) || source.startsWith(`${destination}${sep}`)) {
    throw new Error('Source and destination must be separate, non-nested directories');
  }
  rejectSymlinkAncestors(source);
  rejectSymlinkAncestors(destination);
  const originalFiles = regularFiles(join(source, '.vercel/output')).map((path) => join('.vercel/output', path));
  originalFiles.push('.vercel/project.json');
  const baseline = {};
  for (const path of originalFiles) {
    rejectSymlinkAncestors(join(source, path));
    if (!lstatSync(join(source, path)).isFile()) throw new Error(`Not a regular source file: ${path}`);
    baseline[path] = sha256(readFileSync(join(source, path)));
  }
  const outputConfig = JSON.parse(readFileSync(join(source, '.vercel/output/config.json'), 'utf8'));
  if (outputConfig.version !== 3 || !outputConfig.routes?.some((route) => route.handle === 'filesystem')) {
    throw new Error('Expected a Vercel v3 output with filesystem routing');
  }
  const pages = legalDocuments.map((document) => {
    const canonical = join(repository, 'apps/harmony/entry/src/main/resources/rawfile', document.input);
    rejectSymlinkAncestors(canonical);
    const bytes = readFileSync(canonical);
    const text = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
    const html = renderLegalPage(text, document.title);
    if (extractLegalText(html) !== text || /<script\b|<iframe\b|<form\b/i.test(html)) {
      throw new Error(`Legal page failed content validation: ${document.output}`);
    }
    const path = join('.vercel/output/static', document.output);
    if (path in baseline) throw new Error(`Refusing to replace an existing website page: ${path}`);
    return { path, text, html, sourceSha256: sha256(bytes) };
  });
  const allowed = new Set([...originalFiles, ...pages.map((page) => page.path), markerName]);
  const existing = statIfPresent(destination);
  if (existing) {
    const files = regularFiles(destination);
    if (files.length > 0) {
      const marker = JSON.parse(readFileSync(join(destination, markerName), 'utf8'));
      if (marker.schemaVersion !== 1 || marker.source !== source) throw new Error('Unrecognized existing package');
      for (const path of files) if (!allowed.has(path)) throw new Error(`Unexpected existing file: ${path}`);
      for (const path of originalFiles) {
        if (sha256(readFileSync(join(destination, path))) !== baseline[path]) {
          throw new Error(`Existing original file differs; will not overwrite: ${path}`);
        }
      }
    }
  }
  mkdirSync(destination, { recursive: true });
  for (const path of originalFiles) {
    const target = join(destination, path);
    mkdirSync(dirname(target), { recursive: true });
    if (!statIfPresent(target)) copyFileSync(join(source, path), target);
    if (sha256(readFileSync(target)) !== baseline[path]) throw new Error(`Copy hash mismatch: ${path}`);
  }
  for (const page of pages) {
    const target = join(destination, page.path);
    rejectSymlinkAncestors(target);
    if (statIfPresent(target) && !lstatSync(target).isFile()) throw new Error(`Not a regular output: ${page.path}`);
    writeFileSync(target, page.html, { encoding: 'utf8', mode: 0o644 });
  }
  for (const path of originalFiles) {
    if (sha256(readFileSync(join(source, path))) !== baseline[path] || sha256(readFileSync(join(destination, path))) !== baseline[path]) {
      throw new Error(`Original changed during packaging: ${path}`);
    }
  }
  for (const page of pages) {
    if (extractLegalText(readFileSync(join(destination, page.path), 'utf8')) !== page.text) {
      throw new Error(`Saved document differs from canonical text: ${page.path}`);
    }
  }
  const report = {
    schemaVersion: 1, source, destination, packagedAt: new Date().toISOString(),
    status: 'prepared-not-deployed', originalFiles: baseline,
    legalPages: pages.map((page) => ({ path: page.path, sourceSha256: page.sourceSha256, htmlSha256: sha256(page.html) })),
  };
  writeFileSync(join(destination, markerName), `${JSON.stringify(report, null, 2)}\n`, { encoding: 'utf8', mode: 0o644 });
  return { destination, preservedOriginalFiles: originalFiles.length, addedPublicPages: pages.length,
    canonicalTextVerified: true, originalsByteIdentical: true, status: report.status };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.argv.length !== 2) throw new Error('No CLI arguments: use the approved original backup and package destination.');
  process.stdout.write(`${JSON.stringify(packageLegalSite(), null, 2)}\n`);
}
