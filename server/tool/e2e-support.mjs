import { io } from 'socket.io-client';

export const api1 = process.env.E2E_API_1 ?? 'http://api-1:3000';
export const api2 = process.env.E2E_API_2 ?? 'http://api-2:3000';
export const jwks = process.env.E2E_JWKS ?? 'http://jwks:4000';
export const runId = process.env.E2E_RUN_ID ?? `local-${Date.now()}`;

export async function token(input = {}) {
  const response = await fetch(`${jwks}/token`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(input),
  });
  if (!response.ok) throw new Error(`Token fixture failed: ${response.status} ${await response.text()}`);
  return (await response.json()).accessToken;
}

export async function fixtureControl(target, action) {
  const controlToken = process.env.E2E_FIXTURE_CONTROL_TOKEN;
  if (!controlToken) throw new Error('E2E_FIXTURE_CONTROL_TOKEN is required');
  const response = await fetch(`${jwks}/__test/keys/${encodeURIComponent(target)}/${action}`, {
    method: 'POST',
    headers: { authorization: `Bearer ${controlToken}` },
  });
  if (!response.ok) throw new Error(`Fixture ${action} failed: ${response.status} ${await response.text()}`);
  return response.json();
}

export async function request(
  base,
  accessToken,
  method,
  path,
  body,
  expected = [200, 201, 204],
) {
  const response = await fetch(`${base}${path}`, {
    method,
    headers: {
      authorization: `Bearer ${accessToken}`,
      ...(body === undefined ? {} : { 'content-type': 'application/json' }),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (!expected.includes(response.status)) {
    throw new Error(`${method} ${path} returned ${response.status}: ${await response.text()}`);
  }
  if (response.status === 204) return undefined;
  const text = await response.text();
  return text ? JSON.parse(text) : undefined;
}

export function connect(base, accessToken) {
  return new Promise((resolve, reject) => {
    const socket = io(`${base}/v1/realtime`, {
      transports: ['websocket'],
      auth: { token: accessToken },
      reconnection: false,
    });
    const timer = setTimeout(() => {
      socket.close();
      reject(new Error('Timed out connecting realtime socket'));
    }, 10_000);
    socket.once('connect', () => {
      clearTimeout(timer);
      resolve(socket);
    });
    socket.once('connect_error', (error) => {
      clearTimeout(timer);
      reject(error);
    });
  });
}

export function ack(socket, event, data, expectedOk = true) {
  return new Promise((resolve, reject) => {
    socket.timeout(5_000).emit(event, data, (error, value) => {
      if (error) return reject(error);
      if (expectedOk && value?.ok !== true) {
        return reject(new Error(`${event} rejected: ${JSON.stringify(value)}`));
      }
      if (!expectedOk && value?.ok !== false) {
        return reject(new Error(`${event} unexpectedly succeeded: ${JSON.stringify(value)}`));
      }
      resolve(value);
    });
  });
}

export function nextEvent(socket, predicate, timeoutMs = 12_000) {
  return new Promise((resolve, reject) => {
    const handler = (event) => {
      if (!predicate(event)) return;
      clearTimeout(timer);
      socket.off('study-room.event', handler);
      resolve(event);
    };
    const timer = setTimeout(() => {
      socket.off('study-room.event', handler);
      reject(new Error('Timed out waiting for realtime event'));
    }, timeoutMs);
    socket.on('study-room.event', handler);
  });
}

export function expectNoEvent(socket, predicate, timeoutMs = 1_000) {
  return new Promise((resolve, reject) => {
    const handler = (event) => {
      if (!predicate(event)) return;
      clearTimeout(timer);
      socket.off('study-room.event', handler);
      reject(new Error(`Unexpected realtime event: ${JSON.stringify(event)}`));
    };
    const timer = setTimeout(() => {
      socket.off('study-room.event', handler);
      resolve();
    }, timeoutMs);
    socket.on('study-room.event', handler);
  });
}

export function socketDisconnect(socket, timeoutMs = 10_000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Timed out waiting for socket disconnect')), timeoutMs);
    socket.once('disconnect', (reason) => {
      clearTimeout(timer);
      resolve(reason);
    });
  });
}

export function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

export function memberStatus(room, userId) {
  const member = room?.members?.find((candidate) => candidate.id === userId);
  if (!member) throw new Error(`Member ${userId} is missing from room snapshot`);
  return member.status;
}

export function assert(condition, message) {
  if (!condition) throw new Error(message);
}
