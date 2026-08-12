import { access, mkdir, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import { delay } from './e2e-support.mjs';

const target = process.env.E2E_HTTP_PROBE_URL;
const expectedStatus = Number(process.env.E2E_HTTP_EXPECTED_STATUS ?? 200);
const intervalMs = Number(process.env.E2E_PROBE_INTERVAL_MS ?? 200);
const maximumDurationMs = Number(process.env.E2E_PROBE_MAX_DURATION_MS ?? 120_000);
const resultPath = process.env.E2E_RESULT_PATH;
const readyPath = process.env.E2E_READY_PATH;
const stopPath = process.env.E2E_STOP_PATH;
if (!target) throw new Error('E2E_HTTP_PROBE_URL is required');
if (!stopPath) throw new Error('E2E_STOP_PATH is required');

const startedAt = Date.now();
const failures = [];
let attempts = 0;
let readyWritten = false;

while (true) {
  attempts += 1;
  try {
    const response = await fetch(target, { signal: AbortSignal.timeout(3_000) });
    if (response.status !== expectedStatus) {
      failures.push(`attempt=${attempts} status=${response.status}`);
    } else if (!readyWritten && readyPath) {
      await mkdir(dirname(readyPath), { recursive: true });
      await writeFile(readyPath, `${new Date().toISOString()}\n`);
      readyWritten = true;
    }
  } catch (error) {
    failures.push(`attempt=${attempts} error=${error instanceof Error ? error.message : String(error)}`);
  }
  try {
    await access(stopPath);
    break;
  } catch {
    // Continue until the orchestrator completes the protected operation.
  }
  if (Date.now() - startedAt >= maximumDurationMs) {
    failures.push(`probe stop marker was not observed within ${maximumDurationMs}ms`);
    break;
  }
  await delay(intervalMs);
}

const result = {
  scenario: 'continuous-http-probe',
  target,
  expectedStatus,
  startedAt: new Date(startedAt).toISOString(),
  endedAt: new Date().toISOString(),
  durationMs: Date.now() - startedAt,
  attempts,
  failures,
  passed: failures.length === 0,
};
if (resultPath) {
  await mkdir(dirname(resultPath), { recursive: true });
  await writeFile(resultPath, `${JSON.stringify(result, null, 2)}\n`);
}
if (failures.length > 0) throw new Error(`HTTP probe observed ${failures.length} failures`);
console.log(`${target} remained at ${expectedStatus} for ${attempts} probes.`);
