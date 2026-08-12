import { mkdir, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import { createClient } from 'redis';
import { io } from 'socket.io-client';
import { assert, delay, jwks, runId, token } from './e2e-support.mjs';

const proxy = process.env.E2E_PROXY ?? 'http://proxy:8080';
const durationMs = Number(process.env.E2E_SOAK_DURATION_MS ?? 600_000);
const intervalMs = Number(process.env.E2E_SOAK_INTERVAL_MS ?? 1_000);
const expectedReconnects = Number(process.env.E2E_EXPECTED_RECONNECTS ?? 2);
const proxyApi1 = process.env.E2E_PROXY_API_1 ?? 'http://api-1-proxy:8080';
const proxyApi2 = process.env.E2E_PROXY_API_2 ?? 'http://api-2-proxy:8080';
const resultPath = process.env.E2E_RESULT_PATH;
const reconnectKey = `e2e:soak:${runId}:reconnects`;
assert(Number.isSafeInteger(expectedReconnects) && expectedReconnects >= 0, 'E2E_EXPECTED_RECONNECTS must be a non-negative integer');
const redis = createClient({ url: process.env.REDIS_URL ?? 'redis://redis:6379' });

let httpRequests = 0;
let httpRetries = 0;
let chatMessages = 0;
let chatEvents = 0;
let sessions = 0;
let socketReconnects = 0;
let socketDisconnects = 0;
let socketConnectErrors = 0;
let socketSubscriptions = 0;
let socketSubscriptionFailures = 0;
const reconnectMilestones = [];
let iterations = 0;
let failure;
let room;
const sockets = [];
const processStartedAt = Date.now();
let workloadStartedAt;
redis.on('error', (error) => {
  console.error(`Soak Redis error: ${error.message}`);
  failure ??= `Soak Redis error: ${error.message}`;
});

async function apiRequest(accessToken, method, path, body) {
  let lastError;
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    httpRequests += 1;
    try {
      const response = await fetch(`${proxy}${path}`, {
        method,
        headers: {
          authorization: `Bearer ${accessToken}`,
          ...(body === undefined ? {} : { 'content-type': 'application/json' }),
        },
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: AbortSignal.timeout(7_000),
      });
      if (response.ok) {
        if (response.status === 204) return undefined;
        return JSON.parse(await response.text());
      }
      lastError = new Error(`${method} ${path} returned ${response.status}: ${await response.text()}`);
    } catch (error) {
      lastError = error;
    }
    if (attempt < 3) {
      httpRetries += 1;
      await delay(500 * attempt);
    }
  }
  throw lastError;
}

function connectResilient(base, accessToken) {
  const socket = io(`${base}/v1/realtime`, {
    transports: ['websocket'],
    auth: { token: accessToken },
    reconnection: true,
    reconnectionAttempts: Infinity,
    reconnectionDelay: 250,
    reconnectionDelayMax: 2_000,
  });
  let connectionCount = 0;
  let initialSettled = false;
  const ready = new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`Timed out subscribing soak socket through ${base}`)), 20_000);
    socket.on('connect', () => {
      const reconnect = connectionCount > 0;
      connectionCount += 1;
      socket.timeout(5_000).emit('room.subscribe', { roomId: room.id }, async (error, value) => {
        try {
          if (error || value?.ok !== true) {
            const subscriptionError = error ?? new Error(
              `room.subscribe rejected through ${base}: ${JSON.stringify(value)}`,
            );
            socketSubscriptionFailures += 1;
            if (!initialSettled) {
              initialSettled = true;
              clearTimeout(timer);
              reject(subscriptionError);
            } else if (!failure) {
              failure = subscriptionError instanceof Error
                ? subscriptionError.message
                : String(subscriptionError);
            }
            return;
          }
          socketSubscriptions += 1;
          if (reconnect) {
            socketReconnects += 1;
            const aggregateCount = await redis.incr(reconnectKey);
            reconnectMilestones.push({
              count: socketReconnects,
              aggregateCount,
              at: new Date().toISOString(),
            });
          }
          if (initialSettled) return;
          initialSettled = true;
          clearTimeout(timer);
          resolve();
        } catch (callbackError) {
          const callbackFailure = callbackError instanceof Error
            ? callbackError
            : new Error(String(callbackError));
          if (!initialSettled) {
            initialSettled = true;
            clearTimeout(timer);
            reject(callbackFailure);
          } else if (!failure) {
            failure = callbackFailure.message;
          }
        }
      });
    });
  });
  socket.on('disconnect', (reason) => {
    if (reason !== 'io client disconnect') socketDisconnects += 1;
  });
  socket.on('connect_error', () => {
    socketConnectErrors += 1;
  });
  socket.on('study-room.event', (event) => {
    if (event?.type === 'chat.message.created' && event.roomId === room.id) chatEvents += 1;
  });
  sockets.push(socket);
  return ready;
}

async function waitForChatEvent(previousCount) {
  const deadline = Date.now() + 8_000;
  while (Date.now() < deadline) {
    if (chatEvents > previousCount) return;
    await delay(100);
  }
  throw new Error('Timed out waiting for a soak chat event');
}

try {
  const ownerToken = await token({ sub: `soak-owner-${runId}`, displayName: 'Soak Owner' });
  room = await apiRequest(ownerToken, 'POST', '/v1/rooms', { title: `Soak ${runId}` });
  await redis.connect();
  await redis.set(reconnectKey, '0', { PX: durationMs + 120_000 });
  await connectResilient(proxyApi1, ownerToken);
  await connectResilient(proxyApi2, ownerToken);
  workloadStartedAt = Date.now();
  await redis.set(`e2e:soak:${runId}`, room.id, { PX: durationMs + 120_000 });
  console.log(`Soak workload ready for rolling restarts; fixture=${jwks} room=${room.id}`);

  const deadline = workloadStartedAt + durationMs;
  while (Date.now() < deadline) {
    if (failure) throw new Error(failure);
    const snapshot = await apiRequest(ownerToken, 'GET', `/v1/rooms/${room.id}`);
    if (snapshot.id !== room.id) throw new Error('Soak room snapshot changed identity');

    if (iterations % 5 === 0) {
      const previousEvents = chatEvents;
      await apiRequest(
        ownerToken,
        'POST',
        `/v1/rooms/${room.id}/messages`,
        { text: `soak-${runId}-${iterations}` },
      );
      chatMessages += 1;
      await waitForChatEvent(previousEvents);
    }

    if (iterations % 30 === 0) {
      const session = await apiRequest(ownerToken, 'POST', `/v1/rooms/${room.id}/sessions`);
      await apiRequest(ownerToken, 'PATCH', `/v1/sessions/${session.id}`, { status: 'finished' });
      sessions += 1;
    }

    iterations += 1;
    await delay(intervalMs);
  }
  if (failure) throw new Error(failure);
  assert(
    socketReconnects >= expectedReconnects,
    `Expected at least ${expectedReconnects} successful WebSocket reconnects, observed ${socketReconnects}`,
  );
  assert(
    chatEvents >= chatMessages,
    `Observed ${chatEvents} chat events for ${chatMessages} sent messages`,
  );
} catch (error) {
  failure = error instanceof Error ? error.message : String(error);
} finally {
  for (const socket of sockets) socket.close();
  if (redis.isOpen) {
    await redis.del([`e2e:soak:${runId}`, reconnectKey]).catch(() => undefined);
    await redis.quit();
  }
  const result = {
    scenario: 'mixed-http-websocket-soak',
    passed: failure === undefined,
    startedAt: new Date(workloadStartedAt ?? processStartedAt).toISOString(),
    endedAt: new Date().toISOString(),
    durationMs: Date.now() - (workloadStartedAt ?? processStartedAt),
    iterations,
    httpRequests,
    httpRetries,
    chatMessages,
    chatEvents,
    sessions,
    expectedReconnects,
    socketReconnects,
    socketDisconnects,
    socketConnectErrors,
    socketSubscriptions,
    socketSubscriptionFailures,
    reconnectMilestones,
    failure: failure ?? null,
  };
  if (resultPath) {
    await mkdir(dirname(resultPath), { recursive: true });
    await writeFile(resultPath, `${JSON.stringify(result, null, 2)}\n`);
  }
}

if (failure) throw new Error(failure);
console.log(`Soak passed: ${iterations} iterations, ${chatMessages} chats, ${sessions} sessions, ${socketReconnects} reconnects.`);
