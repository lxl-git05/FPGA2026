import { build } from 'esbuild';
import { mkdir } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
const dir = new URL('../../Claude_Temp/block-studio-tests/', import.meta.url);
await mkdir(dir, { recursive: true });
const output = new URL('model.test.mjs', dir);
await build({ entryPoints: ['tests/model.test.ts'], outfile: output.pathname.replace(/^\/([A-Z]:)/i, '$1'), bundle: true, platform: 'node', format: 'esm' });
const result = spawnSync(process.execPath, ['--test', output.pathname.replace(/^\/([A-Z]:)/i, '$1')], { stdio: 'inherit' });
process.exitCode = result.status ?? 1;
