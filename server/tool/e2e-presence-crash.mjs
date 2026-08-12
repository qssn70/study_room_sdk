import { createClient } from 'redis';
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import {
  ack,
  api1,
  api2,
  assert,
  connect,
  delay,
  memberStatus,
  request,
  runId,
  socketDisconnect,
  token,
} from './e2e-support.mjs';

const resultPath = process.env.E2E_RESULT_PATH;
const startedAt = Date.now();
const ttlSeconds = Number(process.env.STUDY_ROOM_PRESENCE_TTL_SECONDS ?? 60);
const refreshSeconds = Number(process.env.STUDY_ROOM_PRESENCE_REFRESH_SECONDS ?? 20);

const ownerId = `ttl-owner-${runId}`;
const memberId = `ttl-member-${runId}`;
const ownerToken = await token({ sub: ownerId, displayName: 'TTL Owner' });
const memberToken = await token({ sub: memberId, displayName: 'TTL Member' });
const room = await request(api1, ownerToken, 'POST', '/v1/rooms', { title: `TTL crash ${runId}` });
await request(api2, memberToken, 'POST', `/v1/rooms/${room.id}/join-requests`);
const inbox = await request(api1, ownerToken, 'GET', `/v1/rooms/${room.id}/join-requests`);
const pending = inbox.items.find((item) => item.userId === memberId);
assert(pending, 'TTL test join request is missing');
await request(
  api1,
  ownerToken,
  'PATCH',
  `/v1/rooms/${room.id}/join-requests/${pending.id}`,
  { decision: 'approved' },
);

const memberSocket = await connect(api2, memberToken);
const redis = createClient({ url: process.env.REDIS_URL ?? 'redis://redis:6379' });
redis.on('error', (error) => console.error(`TTL coordination Redis error: ${error.message}`));
await redis.connect();
try {
  await ack(memberSocket, 'room.subscribe', { roomId: room.id });
  const online = await request(api1, ownerToken, 'GET', `/v1/rooms/${room.id}`);
  assert(memberStatus(online, memberId) === 'online', 'Member did not become online before API crash');

  const indexKey = `study-room:presence-room:demo:${encodeURIComponent(room.id)}`;
  const connectionKeys = await redis.sMembers(indexKey);
  assert(connectionKeys.length > 0, 'Presence room index did not contain a connection key');
  const captureTtl = async () => ({
    capturedAt: new Date().toISOString(),
    indexKey,
    indexTtlSeconds: await redis.ttl(indexKey),
    connections: await Promise.all(connectionKeys.map(async (key) => ({
      key,
      ttlSeconds: await redis.ttl(key),
      value: await redis.get(key),
    }))),
  });
  const initialTtl = await captureTtl();
  assert(
    initialTtl.indexTtlSeconds >= ttlSeconds,
    `Initial presence index TTL was ${initialTtl.indexTtlSeconds}, expected at least ${ttlSeconds}`,
  );
  assert(
    initialTtl.connections.every((connection) => connection.ttlSeconds > 0),
    'An initial presence connection key had no positive TTL',
  );
  await delay(Math.min(Math.max(refreshSeconds * 2_000 + 250, 1_250), ttlSeconds * 750));
  const refreshedTtl = await captureTtl();
  assert(
    refreshedTtl.connections.every((connection) => connection.ttlSeconds >= Math.max(1, ttlSeconds - refreshSeconds - 1)),
    'Presence connection TTL was not refreshed before the instance crash',
  );
  assert(
    refreshedTtl.indexTtlSeconds >= ttlSeconds,
    'Presence room index TTL was not refreshed before the instance crash',
  );

  const disconnected = socketDisconnect(memberSocket, 15_000);
  const marker = `e2e:presence-crash:${runId}`;
  await redis.set(marker, room.id, { EX: 120 });
  console.log(`Presence crash test ready: ${marker}`);
  await disconnected;
  const expireWaitMs = Number(process.env.E2E_PRESENCE_EXPIRE_WAIT_MS ?? ((ttlSeconds * 2 + 2) * 1_000));
  assert(
    expireWaitMs > ttlSeconds * 2_000,
    'E2E_PRESENCE_EXPIRE_WAIT_MS must exceed the room-index TTL',
  );
  await delay(expireWaitMs);

  const expired = await request(api1, ownerToken, 'GET', `/v1/rooms/${room.id}`);
  assert(memberStatus(expired, memberId) === 'offline', 'Crashed instance presence did not expire to offline');
  const expiredTtl = await captureTtl();
  assert(
    expiredTtl.connections.every((connection) => connection.ttlSeconds === -2),
    'At least one crashed-instance presence connection key still exists',
  );
  assert(expiredTtl.indexTtlSeconds === -2, 'Crashed-instance room presence index still exists');
  await redis.del(marker);
  const result = {
    scenario: 'redis-presence-instance-crash',
    passed: true,
    startedAt: new Date(startedAt).toISOString(),
    endedAt: new Date().toISOString(),
    durationMs: Date.now() - startedAt,
    configuredTtlSeconds: ttlSeconds,
    configuredRefreshSeconds: refreshSeconds,
    expireWaitMs,
    roomId: room.id,
    initialTtl,
    refreshedTtl,
    expiredTtl,
    memberStatusAfterExpiry: memberStatus(expired, memberId),
  };
  if (resultPath) {
    await mkdir(dirname(resultPath), { recursive: true });
    await writeFile(resultPath, `${JSON.stringify(result, null, 2)}\n`);
  }
  console.log('Abnormal instance exit and Redis presence TTL E2E passed.');
} finally {
  memberSocket.close();
  await redis.quit();
}
