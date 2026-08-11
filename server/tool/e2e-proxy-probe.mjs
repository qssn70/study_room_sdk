import { mkdir, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import { delay } from './e2e-support.mjs';

const proxy = process.env.E2E_PROXY ?? 'http://proxy:8080';
const durationMs = Number(process.env.E2E_PROBE_DURATION_MS ?? 30_000);
const intervalMs = Number(process.env.E2E_PROBE_INTERVAL_MS ?? 200);
const resultPath = process.env.E2E_RESULT_PATH;
const startedAt = Date.now();
const failures = [];
let attempts = 0;

while (Date.now() - startedAt < durationMs) {
  attempts += 1;
  try {
    const response = await fetch(`${proxy}/health/live`, { signal: AbortSignal.timeout(3_000) });
    if (response.status !== 200) failures.push(`attempt=${attempts} status=${response.status}`);
  } catch (error) {
    failures.push(`attempt=${attempts} error=${error instanceof Error ? error.message : String(error)}`);
  }
  await delay(intervalMs);
}

const result = {
  scenario: 'rolling-proxy-probe',
  durationMs: Date.now() - startedAt,
  attempts,
  failures,
  passed: failures.length === 0,
};
if (resultPath) {
  await mkdir(dirname(resultPath), { recursive: true });
  await writeFile(resultPath, JSON.stringify(result, null, 2));
}
if (failures.length > 0) throw new Error(`Proxy probe observed ${failures.length} failures`);
console.log(`Proxy remained available for ${attempts} rolling-restart probes.`);
