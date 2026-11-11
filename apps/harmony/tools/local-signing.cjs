'use strict';

const fs = require('fs');
const path = require('path');

function resolveSigningFile(projectDir, env = process.env) {
  const override = env.MILO_HARMONY_SIGNING_FILE;
  if (typeof override === 'string' && override.trim().length > 0) {
    return path.isAbsolute(override) ? override : path.join(projectDir, override);
  }
  return path.join(projectDir, 'signing-configs.local.json');
}

function loadSigningConfigs(filePath) {
  if (!fs.existsSync(filePath)) return undefined;
  const parsed = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  const configs = Array.isArray(parsed) ? parsed : parsed && parsed.signingConfigs;
  if (!Array.isArray(configs) || configs.length === 0) {
    throw new Error(`MILO signing file ${filePath} must contain a non-empty signingConfigs array.`);
  }
  for (const config of configs) {
    if (!config || typeof config.name !== 'string' || config.name.length === 0) {
      throw new Error(`MILO signing file ${filePath} has a signing config without a name.`);
    }
  }
  return configs;
}

function applySigningConfigs(buildProfileOpt, configs) {
  if (!buildProfileOpt.app) buildProfileOpt.app = {};
  buildProfileOpt.app.signingConfigs = configs;
  const products = buildProfileOpt.app.products;
  if (!Array.isArray(products)) return buildProfileOpt;
  const names = new Set(configs.map((config) => config.name));
  for (const product of products) {
    if (!product || typeof product !== 'object') continue;
    let preferred = names.has('default') ? 'default' : configs[0].name;
    if (product.name === 'release' && names.has('release')) preferred = 'release';
    product.signingConfig = preferred;
  }
  return buildProfileOpt;
}

module.exports = {
  resolveSigningFile,
  loadSigningConfigs,
  applySigningConfigs,
};
