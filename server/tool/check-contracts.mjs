import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import Ajv2020 from 'ajv/dist/2020.js';
import addFormats from 'ajv-formats';
import { load } from 'js-yaml';

const root = resolve(import.meta.dirname, '..', '..');
const openapiPath = resolve(root, 'contracts', 'openapi.yaml');
const realtimePath = resolve(root, 'contracts', 'realtime-events.schema.json');
const redoclyConfig = resolve(root, 'contracts', 'redocly.yaml');
const require = createRequire(import.meta.url);
const redoclyCli = require.resolve('@redocly/cli/bin/cli.js');
const openapi = load(await readFile(openapiPath, 'utf8'));
const realtime = JSON.parse(await readFile(realtimePath, 'utf8'));

const redocly = spawnSync(
  process.execPath,
  [
    redoclyCli,
    'lint',
    openapiPath,
    '--config',
    redoclyConfig,
    '--lint-config',
    'error',
  ],
  { stdio: 'inherit' },
);
if (redocly.status !== 0) process.exit(redocly.status ?? 1);

const ajv = new Ajv2020({ allErrors: true, strict: true });
addFormats(ajv);
const validateRealtime = ajv.compile(realtime);

const baseEvent = {
  schemaVersion: 1,
  eventId: '00000000-0000-4000-8000-000000000001',
  roomId: '00000000-0000-4000-8000-000000000002',
  roomVersion: 1,
  occurredAt: '2026-08-09T12:00:00.000Z',
};
const member = {
  id: 'user-1',
  displayName: 'User One',
  avatarUrl: '',
  role: 'owner',
  status: 'online',
};
const samples = [
  { ...baseEvent, type: 'room.state', payload: { id: baseEvent.roomId, appId: 'app-1', title: 'Study', version: 1, members: [member] } },
  { ...baseEvent, type: 'membership.updated', payload: { roomId: baseEvent.roomId, active: false } },
  { ...baseEvent, roomVersion: null, type: 'join-request.created', payload: { id: baseEvent.eventId, roomId: baseEvent.roomId, userId: 'user-2', displayName: 'User Two', status: 'pending', createdAt: baseEvent.occurredAt, updatedAt: baseEvent.occurredAt } },
  { ...baseEvent, roomVersion: null, type: 'join-request.updated', payload: { id: baseEvent.eventId, roomId: baseEvent.roomId, userId: 'user-2', displayName: 'User Two', status: 'approved', createdAt: baseEvent.occurredAt, updatedAt: baseEvent.occurredAt } },
  { ...baseEvent, type: 'member.presence.updated', payload: member },
  { ...baseEvent, roomVersion: null, type: 'chat.message.created', payload: { id: baseEvent.eventId, roomId: baseEvent.roomId, senderId: 'user-1', senderName: 'User One', text: 'Hello', sentAt: baseEvent.occurredAt } },
  { ...baseEvent, roomVersion: null, type: 'session.updated', payload: { id: baseEvent.eventId, roomId: baseEvent.roomId, userId: 'user-1', status: 'running', startedAt: baseEvent.occurredAt, finishedAt: null, updatedAt: baseEvent.occurredAt } },
];
for (const sample of samples) {
  if (!validateRealtime(sample)) {
    throw new Error(`Valid realtime sample rejected (${sample.type}): ${ajv.errorsText(validateRealtime.errors)}`);
  }
}
for (const invalid of [
  { ...samples[0], roomId: undefined },
  { ...samples[1], payload: { roomId: baseEvent.roomId, active: false, unexpected: true } },
  { ...samples[5], type: 'session.updated' },
]) {
  if (validateRealtime(invalid)) throw new Error(`Invalid realtime sample accepted: ${JSON.stringify(invalid)}`);
}

const methods = new Set(['get', 'post', 'put', 'patch', 'delete', 'options', 'head', 'trace']);
const operationIds = new Set();
const schemas = openapi.components?.schemas ?? {};
const rewrittenSchemas = rewriteRefs(schemas);
let compiledResponses = 0;
for (const [path, pathItem] of Object.entries(openapi.paths ?? {})) {
  for (const [method, operation] of Object.entries(pathItem)) {
    if (!methods.has(method)) continue;
    if (!operation.operationId || operationIds.has(operation.operationId)) {
      throw new Error(`Missing or duplicate operationId at ${method.toUpperCase()} ${path}`);
    }
    operationIds.add(operation.operationId);
    if (!Array.isArray(operation.security)) {
      throw new Error(`Explicit security is required at ${method.toUpperCase()} ${path}`);
    }
    for (const [status, declared] of Object.entries(operation.responses ?? {})) {
      const response = dereferenceResponse(declared, openapi.components?.responses ?? {});
      if (!response.headers?.['x-request-id']) {
        throw new Error(`Response ${status} has no x-request-id header at ${method.toUpperCase()} ${path}`);
      }
      if (status === '204') {
        if (response.content) throw new Error(`204 response must not declare content at ${method.toUpperCase()} ${path}`);
        continue;
      }
      const content = response.content ?? {};
      if (Object.keys(content).length === 0) {
        throw new Error(`Response ${status} has no content at ${method.toUpperCase()} ${path}`);
      }
      for (const [mediaType, media] of Object.entries(content)) {
        if (!media.schema) throw new Error(`Response ${status} ${mediaType} has no schema at ${method.toUpperCase()} ${path}`);
        ajv.compile({ ...rewriteRefs(media.schema), $defs: rewrittenSchemas });
        compiledResponses += 1;
      }
    }
  }
}
if (compiledResponses === 0) throw new Error('No response schemas were compiled');

const generated = spawnSync(
  process.execPath,
  [resolve(import.meta.dirname, 'generate-contracts.mjs'), '--check'],
  { stdio: 'inherit' },
);
if (generated.status !== 0) process.exit(generated.status ?? 1);
console.log(`Contracts are valid: ${operationIds.size} operations, ${compiledResponses} response schemas, ${samples.length} realtime variants.`);

function rewriteRefs(value) {
  if (Array.isArray(value)) return value.map(rewriteRefs);
  if (!value || typeof value !== 'object') return value;
  return Object.fromEntries(Object.entries(value).map(([key, item]) => [
    key,
    key === '$ref' && typeof item === 'string'
      ? item.replace('#/components/schemas/', '#/$defs/')
      : rewriteRefs(item),
  ]));
}

function dereferenceResponse(response, responses) {
  if (!response?.$ref) return response ?? {};
  const name = response.$ref.split('/').at(-1);
  const resolved = responses[name];
  if (!resolved) throw new Error(`Unknown response reference: ${response.$ref}`);
  return resolved;
}
