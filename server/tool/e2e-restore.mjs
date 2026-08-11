import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import { api1, api2, assert, request, runId, token } from './e2e-support.mjs';

const phase = process.env.E2E_PHASE ?? 'setup';
const statePath = process.env.E2E_STATE_PATH ?? '/state/restore.json';
const resultPath = process.env.E2E_RESULT_PATH;

if (phase === 'setup') {
  const ownerId = `restore-owner-${runId}`;
  const ownerToken = await token({ sub: ownerId, displayName: 'Restore Owner' });
  const room = await request(api1, ownerToken, 'POST', '/v1/rooms', { title: `Restore ${runId}` });
  const message = await request(
    api2,
    ownerToken,
    'POST',
    `/v1/rooms/${room.id}/messages`,
    { text: `restore-message-${runId}` },
  );
  const session = await request(api1, ownerToken, 'POST', `/v1/rooms/${room.id}/sessions`);
  const paused = await request(api2, ownerToken, 'PATCH', `/v1/sessions/${session.id}`, { status: 'paused' });
  await mkdir(dirname(statePath), { recursive: true });
  await writeFile(statePath, JSON.stringify({
    runId,
    ownerId,
    roomId: room.id,
    roomTitle: room.title,
    messageId: message.id,
    messageText: message.text,
    sessionId: paused.id,
  }, null, 2));
  console.log(`Restore source state written to ${statePath}.`);
} else if (phase === 'verify') {
  const state = JSON.parse(await readFile(statePath, 'utf8'));
  assert(state.runId === runId, `Restore state belongs to ${state.runId}, expected ${runId}`);
  const ownerToken = await token({ sub: state.ownerId, displayName: 'Restore Owner' });
  const room = await request(api2, ownerToken, 'GET', `/v1/rooms/${state.roomId}`);
  const messages = await request(api1, ownerToken, 'GET', `/v1/rooms/${state.roomId}/messages?limit=100`);
  const sessions = await request(api2, ownerToken, 'GET', `/v1/rooms/${state.roomId}/active-sessions?limit=100`);
  assert(room.title === state.roomTitle, 'Restored room title is incorrect');
  assert(messages.items.some((item) => item.id === state.messageId && item.text === state.messageText), 'Restored chat message is missing');
  assert(sessions.items.some((item) => item.id === state.sessionId && item.status === 'paused'), 'Restored active session is missing');
  const result = {
    scenario: 'postgres-logical-restore',
    passed: true,
    restored: { roomId: state.roomId, messageId: state.messageId, sessionId: state.sessionId },
  };
  if (resultPath) {
    await mkdir(dirname(resultPath), { recursive: true });
    await writeFile(resultPath, JSON.stringify(result, null, 2));
  }
  console.log('Restored PostgreSQL data was verified through both API instances.');
} else {
  throw new Error(`Unknown E2E_PHASE: ${phase}`);
}
