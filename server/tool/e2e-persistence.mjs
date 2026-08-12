import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import {
  api1,
  api2,
  assert,
  request,
  runId,
  token,
} from './e2e-support.mjs';

const phase = process.env.E2E_PHASE ?? 'setup';
const statePath = process.env.E2E_STATE_PATH ?? '/state/persistence.json';
const resultPath = process.env.E2E_RESULT_PATH;
const startedAt = Date.now();

if (phase === 'setup') {
  const ownerId = `persist-owner-${runId}`;
  const memberId = `persist-member-${runId}`;
  const ownerToken = await token({ sub: ownerId, displayName: 'Persistence Owner' });
  const memberToken = await token({ sub: memberId, displayName: 'Persistence Member' });
  const room = await request(api1, ownerToken, 'POST', '/v1/rooms', { title: `Persistence ${runId}` });
  await request(api2, memberToken, 'POST', `/v1/rooms/${room.id}/join-requests`);
  const requests = await request(api1, ownerToken, 'GET', `/v1/rooms/${room.id}/join-requests`);
  const pending = requests.items.find((item) => item.userId === memberId);
  assert(pending, 'Persistence join request is missing');
  await request(
    api1,
    ownerToken,
    'PATCH',
    `/v1/rooms/${room.id}/join-requests/${pending.id}`,
    { decision: 'approved' },
  );
  const chatText = `persisted-message-${runId}`;
  const message = await request(
    api1,
    ownerToken,
    'POST',
    `/v1/rooms/${room.id}/messages`,
    { text: chatText },
  );
  const session = await request(api2, memberToken, 'POST', `/v1/rooms/${room.id}/sessions`);
  const paused = await request(
    api2,
    memberToken,
    'PATCH',
    `/v1/sessions/${session.id}`,
    { status: 'paused' },
  );
  const ownerSession = await request(api1, ownerToken, 'POST', `/v1/rooms/${room.id}/sessions`);
  const ownerPaused = await request(
    api1,
    ownerToken,
    'PATCH',
    `/v1/sessions/${ownerSession.id}`,
    { status: 'paused' },
  );
  await mkdir(dirname(statePath), { recursive: true });
  await writeFile(statePath, JSON.stringify({
    runId,
    roomId: room.id,
    roomTitle: room.title,
    ownerId,
    memberId,
    chatId: message.id,
    chatText,
    sessionIds: [paused.id, ownerPaused.id],
  }, null, 2));
  console.log(`Persistence setup state written to ${statePath}.`);
} else if (phase === 'verify') {
  const state = JSON.parse(await readFile(statePath, 'utf8'));
  assert(state.runId === runId, `Persistence state belongs to ${state.runId}, expected ${runId}`);
  const ownerToken = await token({ sub: state.ownerId, displayName: 'Persistence Owner' });
  const memberToken = await token({ sub: state.memberId, displayName: 'Persistence Member' });
  const room = await request(api2, ownerToken, 'GET', `/v1/rooms/${state.roomId}`);
  assert(room.title === state.roomTitle, 'Room was not preserved across PostgreSQL/API restart');
  assert(room.members.some((member) => member.id === state.memberId), 'Membership was not preserved');

  const messages = await request(
    api2,
    memberToken,
    'GET',
    `/v1/rooms/${state.roomId}/messages?limit=100`,
  );
  assert(
    messages.items.some((message) => message.id === state.chatId && message.text === state.chatText),
    'Chat message was not preserved across restart',
  );

  const sessionPageOne = await request(
    api1,
    memberToken,
    'GET',
    `/v1/rooms/${state.roomId}/active-sessions?limit=1`,
  );
  assert(sessionPageOne.items.length === 1 && sessionPageOne.nextCursor, 'Active sessions did not produce a first cursor page');
  const sessionPageTwo = await request(
    api2,
    memberToken,
    'GET',
    `/v1/rooms/${state.roomId}/active-sessions?limit=1&cursor=${encodeURIComponent(sessionPageOne.nextCursor)}`,
  );
  assert(sessionPageTwo.items.length === 1, 'Active sessions second cursor page is missing');
  assert(sessionPageTwo.items[0].id !== sessionPageOne.items[0].id, 'Active session cursor repeated an item');
  const sessionIds = new Set([...sessionPageOne.items, ...sessionPageTwo.items].map((session) => session.id));
  assert(
    state.sessionIds.every((sessionId) => sessionIds.has(sessionId)),
    'Active sessions were not preserved across restart',
  );
  assert(
    [...sessionPageOne.items, ...sessionPageTwo.items].every((session) => session.status === 'paused'),
    'An active session changed state across restart',
  );
  const sessionBoundary = await request(
    api1,
    memberToken,
    'GET',
    `/v1/rooms/${state.roomId}/active-sessions?limit=100`,
  );
  assert(sessionBoundary.items.length === 2 && sessionBoundary.nextCursor === null, 'Active session maximum page boundary is incorrect');
  await request(
    api1,
    memberToken,
    'GET',
    `/v1/rooms/${state.roomId}/active-sessions?limit=101`,
    undefined,
    [400],
  );
  const result = {
    scenario: 'postgres-api-persistence',
    passed: true,
    startedAt: new Date(startedAt).toISOString(),
    endedAt: new Date().toISOString(),
    durationMs: Date.now() - startedAt,
    roomId: state.roomId,
    chatId: state.chatId,
    sessionIds: state.sessionIds,
    verifiedThrough: ['api-1', 'api-2'],
  };
  if (resultPath) {
    await mkdir(dirname(resultPath), { recursive: true });
    await writeFile(resultPath, `${JSON.stringify(result, null, 2)}\n`);
  }
  console.log('Room, membership, chat, and active session persistence E2E passed.');
} else {
  throw new Error(`Unknown E2E_PHASE: ${phase}`);
}
