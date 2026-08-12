import { access, mkdir, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import { delay } from './e2e-support.mjs';

const proxy = process.env.E2E_PROXY ?? 'http://proxy:8080';
const durationMs = Number(process.env.E2E_PROBE_DURATION_MS ?? 30_000);
const intervalMs = Number(process.env.E2E_PROBE_INTERVAL_MS ?? 200);
const resultPath = process.env.E2E_RESULT_PATH;
const readyPath = process.env.E2E_READY_PATH;
const stopPath = process.env.E2E_STOP_PATH;
const maximumDurationMs = Number(process.env.E2E_PROBE_MAX_DURATION_MS ?? durationMs);
const startedAt = Date.now();
const startedAtIso = new Date(startedAt).toISOString();
const failures = [];
let attempts = 0;
let readyWritten = false;

while (true) {
  attempts += 1;
  try {
    const response = await fetch(`${proxy}/health/live`, { signal: AbortSignal.timeout(3_000) });
    if (response.status !== 200) {
      failures.push(`attempt=${attempts} status=${response.status}`);
    } else if (!readyWritten && readyPath) {
      await mkdir(dirname(readyPath), { recursive: true });
      await writeFile(readyPath, `${new Date().toISOString()}\n`);
      readyWritten = true;
    }
  } catch (error) {
    failures.push(`attempt=${attempts} error=${error instanceof Error ? error.message : String(error)}`);
  }
  const elapsedMs = Date.now() - startedAt;
  if (stopPath) {
    try {
      await access(stopPath);
      break;
    } catch {
      // The orchestrator has not completed the operation yet.
    }
    if (elapsedMs >= maximumDurationMs) {
      failures.push(`probe stop marker was not observed within ${maximumDurationMs}ms`);
      break;
    }
  } else if (elapsedMs >= durationMs) {
    break;
  }
  await delay(intervalMs);
}

const result = {
  scenario: 'rolling-proxy-probe',
  startedAt: startedAtIso,
  endedAt: new Date().toISOString(),
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
