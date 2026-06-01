import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

/** @typedef {{ env: string, file: string, ascName: string, bundleId: string, exportProfileName: string }} ProfileConfig */

/**
 * @param {string} [repoRoot]
 */
export function loadIosAppConfig(repoRoot) {
  const root =
    repoRoot ||
    path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
  const configPath = path.join(root, 'ios-app.config.json');
  if (!fs.existsSync(configPath)) {
    throw new Error(
      `Missing ${configPath}. Run: .\\ios-build\\sync-to-repos.ps1 from Desktop`
    );
  }
  return JSON.parse(fs.readFileSync(configPath, 'utf8'));
}

export function repoRootFromScript(importMetaUrl) {
  return path.join(path.dirname(fileURLToPath(importMetaUrl)), '..');
}
