import { mkdir, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import { api1, api2, assert, delay, runId, token } from './e2e-support.mjs';

const limit = Number(process.env.STUDY_ROOM_IP_RATE_LIMIT ?? 120);
const resultPath = process.env.E2E_RESULT_PATH;
const startedAt = Date.now();
assert(Number.isSafeInteger(limit) && limit > 0, 'STUDY_ROOM_IP_RATE_LIMIT must be a positive integer');

const accessToken = await token({
  sub: `rate-limit-${runId}`,
  displayName: 'Rate Limit Probe',
});

const windowMs = 60_000;
const initialRemainderMs = Date.now() % windowMs;
const alignmentWaitMs = initialRemainderMs <= 5_000
  ? Math.max(0, 250 - initialRemainderMs)
  : windowMs - initialRemainderMs + 250;
if (alignmentWaitMs > 0) await delay(alignmentWaitMs);
const requestPhaseStartedAt = Date.now();
const alignedWindow = Math.floor(requestPhaseStartedAt / windowMs);

for (let index = 0; index < limit; index += 1) {
  const base = index % 2 === 0 ? api1 : api2;
  const response = await fetch(`${base}/v1/rooms`, {
    headers: { authorization: `Bearer ${accessToken}` },
  });
  assert(response.status === 200, `Distributed IP quota rejected request ${index + 1}: ${response.status}`);
  await response.arrayBuffer();
}

const exceeded = await fetch(`${limit % 2 === 0 ? api1 : api2}/v1/rooms`, {
  headers: { authorization: `Bearer ${accessToken}` },
});
assert(exceeded.status === 429, `Expected request ${limit + 1} to return 429, received ${exceeded.status}`);
const retryAfter = Number(exceeded.headers.get('retry-after'));
assert(Number.isSafeInteger(retryAfter) && retryAfter > 0, '429 response did not include a valid Retry-After header');
const body = await exceeded.json();
assert(body.code === 'rate_limited', '429 response did not use the rate_limited error code');
assert(
  Math.floor(Date.now() / windowMs) === alignedWindow,
  'Rate-limit probe crossed a fixed-window boundary; retry the isolated scenario',
);

const result = {
  scenario: 'distributed-ip-rate-limit',
  passed: true,
  startedAt: new Date(startedAt).toISOString(),
  endedAt: new Date().toISOString(),
  durationMs: Date.now() - startedAt,
  alignmentWaitMs,
  alignedWindow,
  requestPhaseStartedAt: new Date(requestPhaseStartedAt).toISOString(),
  sharedAcrossInstances: true,
  successfulRequests: limit,
  rejectedRequest: limit + 1,
  rejectedStatus: exceeded.status,
  retryAfterSeconds: retryAfter,
  errorCode: body.code,
};
if (resultPath) {
  await mkdir(dirname(resultPath), { recursive: true });
  await writeFile(resultPath, JSON.stringify(result, null, 2));
}

console.log(`Shared IP quota passed across two instances: ${limit} successes, then 429 with Retry-After=${retryAfter}.`);
