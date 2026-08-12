import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import { assert } from './e2e-support.mjs';

const tracesPath = process.env.E2E_OTEL_TRACES_PATH ?? '/artifacts/otel-traces.jsonl';
const resultPath = process.env.E2E_RESULT_PATH;
const expectedService = process.env.E2E_OTEL_SERVICE_NAME ?? 'study-room-server';
const minimumInstanceSpanCounts = JSON.parse(process.env.E2E_OTEL_MINIMUM_INSTANCE_SPANS ?? '{}');
const expectedInstances = (process.env.E2E_OTEL_INSTANCE_IDS ?? 'api-1,api-2')
  .split(',')
  .map((value) => value.trim())
  .filter(Boolean);
const expectedTraceId = process.env.E2E_OTEL_EXPECTED_TRACE_ID;
const expectedTraceInstance = process.env.E2E_OTEL_EXPECTED_TRACE_INSTANCE ?? 'api-1';
const forbiddenTraceId = process.env.E2E_OTEL_FORBIDDEN_TRACE_ID;
const forbiddenTraceInstance = process.env.E2E_OTEL_FORBIDDEN_TRACE_INSTANCE ?? 'api-1';
const expectedMarker = process.env.E2E_OTEL_EXPECTED_MARKER;
const expectedMarkerInstance = process.env.E2E_OTEL_EXPECTED_MARKER_INSTANCE ?? 'api-1';
const forbiddenMarker = process.env.E2E_OTEL_FORBIDDEN_MARKER;
const forbiddenMarkerInstance = process.env.E2E_OTEL_FORBIDDEN_MARKER_INSTANCE ?? 'api-1';
const traceMarkerAttribute = 'study_room.e2e.trace_marker';

const lines = (await readFile(tracesPath, 'utf8')).split(/\r?\n/).filter(Boolean);
const instanceSpanCounts = new Map(expectedInstances.map((instanceId) => [instanceId, 0]));
let serviceSpanCount = 0;
let expectedTraceFound = expectedTraceId === undefined;
let forbiddenTraceFound = false;
let expectedMarkerFound = expectedMarker === undefined;
let forbiddenMarkerFound = false;

function spanStringAttribute(span, key) {
  return (span.attributes ?? []).find((attribute) => attribute.key === key)?.value?.stringValue;
}

for (const line of lines) {
  const request = JSON.parse(line);
  for (const resourceSpans of request.resourceSpans ?? []) {
    const attributes = new Map(
      (resourceSpans.resource?.attributes ?? []).map((attribute) => [
        attribute.key,
        attribute.value?.stringValue,
      ]),
    );
    const spansForResource = (resourceSpans.scopeSpans ?? []).flatMap((scope) => scope.spans ?? []);
    const spans = spansForResource.length;
    if (attributes.get('service.name') !== expectedService) continue;
    serviceSpanCount += spans;
    const instanceId = attributes.get('service.instance.id');
    if (instanceSpanCounts.has(instanceId)) {
      instanceSpanCounts.set(instanceId, instanceSpanCounts.get(instanceId) + spans);
    }
    if (!expectedTraceFound && instanceId === expectedTraceInstance) {
      expectedTraceFound = spansForResource.some((span) => span.traceId === expectedTraceId);
    }
    if (!forbiddenTraceFound && forbiddenTraceId && instanceId === forbiddenTraceInstance) {
      forbiddenTraceFound = spansForResource.some((span) => span.traceId === forbiddenTraceId);
    }
    if (!expectedMarkerFound && instanceId === expectedMarkerInstance) {
      expectedMarkerFound = spansForResource.some(
        (span) => spanStringAttribute(span, traceMarkerAttribute) === expectedMarker,
      );
    }
    if (!forbiddenMarkerFound && forbiddenMarker && instanceId === forbiddenMarkerInstance) {
      forbiddenMarkerFound = spansForResource.some(
        (span) => spanStringAttribute(span, traceMarkerAttribute) === forbiddenMarker,
      );
    }
  }
}

assert(serviceSpanCount > 0, `No spans were exported for service.name=${expectedService}`);
assert(
  expectedTraceFound,
  `No span with traceId=${expectedTraceId} was exported by ${expectedTraceInstance}`,
);
assert(
  !forbiddenTraceFound,
  `A span with forbidden traceId=${forbiddenTraceId} was already exported by ${forbiddenTraceInstance}`,
);
assert(
  expectedMarkerFound,
  `No span with ${traceMarkerAttribute}=${expectedMarker} was exported by ${expectedMarkerInstance}`,
);
assert(
  !forbiddenMarkerFound,
  `A span with forbidden ${traceMarkerAttribute}=${forbiddenMarker} was already exported by ${forbiddenMarkerInstance}`,
);
for (const [instanceId, count] of instanceSpanCounts) {
  assert(count > 0, `No spans were exported for service.instance.id=${instanceId}`);
  if (Object.hasOwn(minimumInstanceSpanCounts, instanceId)) {
    const minimum = Number(minimumInstanceSpanCounts[instanceId]);
    assert(Number.isSafeInteger(minimum) && minimum >= 0, `Invalid minimum span count for ${instanceId}`);
    assert(
      count > minimum,
      `Expected a new span from service.instance.id=${instanceId}; count=${count}, baseline=${minimum}`,
    );
  }
}

const result = {
  scenario: 'opentelemetry-file-export',
  passed: true,
  serviceName: expectedService,
  serviceSpanCount,
  instanceSpanCounts: Object.fromEntries(instanceSpanCounts),
  minimumInstanceSpanCounts,
  exportRecordCount: lines.length,
  expectedTraceId: expectedTraceId ?? null,
  expectedTraceInstance,
  forbiddenTraceId: forbiddenTraceId ?? null,
  forbiddenTraceInstance,
  forbiddenTraceFound,
  expectedMarker: expectedMarker ?? null,
  expectedMarkerInstance,
  expectedMarkerFound,
  forbiddenMarker: forbiddenMarker ?? null,
  forbiddenMarkerInstance,
  forbiddenMarkerFound,
};
if (resultPath) {
  await mkdir(dirname(resultPath), { recursive: true });
  await writeFile(resultPath, `${JSON.stringify(result, null, 2)}\n`);
}
console.log(`OpenTelemetry exported ${serviceSpanCount} spans from ${expectedInstances.join(', ')}.`);
