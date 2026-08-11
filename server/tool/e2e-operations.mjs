import { mkdir, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import { api1, assert, request, runId, token } from './e2e-support.mjs';

const proxy = process.env.E2E_PROXY ?? 'http://proxy:8080';
const resultPath = process.env.E2E_RESULT_PATH;
const startedAt = Date.now();
const adminToken = await token({ type: 'admin', sub: `ops-admin-${runId}` });
const unprivilegedToken = await token({
  type: 'admin',
  sub: `ops-unprivileged-${runId}`,
  scenario: 'missing-metrics-scope',
});
const userId = `ops-user-${runId}`;
const userToken = await token({ sub: userId, displayName: 'Operations Probe' });

async function status(path, accessToken, base = proxy) {
  const response = await fetch(`${base}${path}`, {
    headers: accessToken ? { authorization: `Bearer ${accessToken}` } : {},
    signal: AbortSignal.timeout(5_000),
  });
  return { response, text: await response.text() };
}

const live = await status('/health/live');
const ready = await status('/health/ready');
const denied = await status('/metrics', unprivilegedToken);
const anonymous = await status('/metrics');
const room = await request(api1, userToken, 'POST', '/v1/rooms', { title: `Metrics route ${runId}` });
await request(api1, userToken, 'GET', `/v1/rooms/${room.id}`);
const metrics = await status('/metrics', adminToken);
const api1Metrics = await status('/metrics', adminToken, api1);

assert(live.response.status === 200, `Liveness returned ${live.response.status}`);
assert(ready.response.status === 200, `Readiness returned ${ready.response.status}`);
assert(metrics.response.status === 200, `Authorized metrics returned ${metrics.response.status}`);
assert(metrics.text.includes('study_room_'), 'Metrics output does not contain Study Room metrics');
assert(api1Metrics.response.status === 200, `Direct API metrics returned ${api1Metrics.response.status}`);
assert(api1Metrics.text.includes('study_room_'), 'Direct API metrics output does not contain Study Room metrics');
assert([401, 403].includes(denied.response.status), `Unprivileged metrics returned ${denied.response.status}`);
assert(anonymous.response.status === 401, `Anonymous metrics returned ${anonymous.response.status}`);

const metricSamples = [metrics.text, api1Metrics.text].flatMap((body) => body.split(/\r?\n/).filter((line) => (
  /^study_room_http_(?:request_duration_seconds|errors_total)(?:_(?:bucket|sum|count))?\{/.test(line)
)));
assert(metricSamples.length > 0, 'HTTP metric samples are missing');
const observedRoutes = new Set();
for (const line of metricSamples) {
  const labelsText = line.slice(line.indexOf('{') + 1, line.indexOf('}'));
  const labels = new Map();
  const matcher = /(?:^|,)([A-Za-z_][A-Za-z0-9_]*)="((?:\\.|[^"])*)"/g;
  for (const match of labelsText.matchAll(matcher)) labels.set(match[1], match[2]);
  for (const required of ['method', 'route', 'status']) {
    assert(labels.has(required), `Metric sample is missing the ${required} label: ${line}`);
  }
  const allowed = line.startsWith('study_room_http_request_duration_seconds_bucket')
    ? new Set(['method', 'route', 'status', 'le'])
    : new Set(['method', 'route', 'status']);
  assert(
    [...labels.keys()].every((key) => allowed.has(key)),
    `Metric sample contains a high-cardinality label: ${line}`,
  );
  observedRoutes.add(labels.get('route'));
}
assert(observedRoutes.has('/v1/rooms/:roomId'), 'Metrics did not normalize the room UUID to the route template');
for (const sensitiveValue of [room.id, userId, runId]) {
  assert(!metrics.text.includes(sensitiveValue), `Proxy metrics leaked high-cardinality value ${sensitiveValue}`);
  assert(!api1Metrics.text.includes(sensitiveValue), `Direct API metrics leaked high-cardinality value ${sensitiveValue}`);
}

const result = {
  scenario: 'operations-endpoints',
  passed: true,
  startedAt: new Date(startedAt).toISOString(),
  endedAt: new Date().toISOString(),
  durationMs: Date.now() - startedAt,
  statuses: {
    live: live.response.status,
    ready: ready.response.status,
    metrics: metrics.response.status,
    unprivilegedMetrics: denied.response.status,
    anonymousMetrics: anonymous.response.status,
  },
  metrics: {
    httpSampleCount: metricSamples.length,
    observedRoutes: [...observedRoutes].sort(),
    labels: ['method', 'route', 'status'],
    leakedIdentifiers: false,
  },
};
if (resultPath) {
  await mkdir(dirname(resultPath), { recursive: true });
  await writeFile(resultPath, JSON.stringify(result, null, 2));
}
console.log('Liveness, readiness, and protected metrics operations checks passed.');
