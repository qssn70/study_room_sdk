import { createClient } from 'redis';
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

  const disconnected = socketDisconnect(memberSocket, 15_000);
  const marker = `e2e:presence-crash:${runId}`;
  await redis.set(marker, room.id, { EX: 120 });
  console.log(`Presence crash test ready: ${marker}`);
  await disconnected;
  await delay(Number(process.env.E2E_PRESENCE_EXPIRE_WAIT_MS ?? 6_000));

  const expired = await request(api1, ownerToken, 'GET', `/v1/rooms/${room.id}`);
  assert(memberStatus(expired, memberId) === 'offline', 'Crashed instance presence did not expire to offline');
  await redis.del(marker);
  console.log('Abnormal instance exit and Redis presence TTL E2E passed.');
} finally {
  memberSocket.close();
  await redis.quit();
}
