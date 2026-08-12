import {
  ack,
  api1,
  api2,
  assert,
  connect,
  delay,
  expectNoEvent,
  fixtureControl,
  request,
  runId,
  socketDisconnect,
  token,
} from './e2e-support.mjs';
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';

const resultPath = process.env.E2E_RESULT_PATH;
const startedAt = Date.now();

const adminToken = await token({ type: 'admin', sub: `admin-${runId}` });
const alternateApp = {
  appId: 'demo-alt',
  issuer: 'http://jwks:4000/apps/demo-alt',
  audience: 'study-room-api',
  jwksUri: 'http://jwks:4000/apps/demo-alt/jwks.json',
  enabled: true,
  chatRetentionDays: null,
  sessionRetentionDays: null,
};
const registeredApplications = await request(api1, adminToken, 'GET', '/admin/v1/apps?limit=100');
if (!registeredApplications.items.some((application) => application.appId === alternateApp.appId)) {
  await request(api1, adminToken, 'POST', '/admin/v1/apps', alternateApp, [201]);
}
const { appId: _appId, ...alternateAppUpdate } = alternateApp;
await request(api1, adminToken, 'PATCH', '/admin/v1/apps/demo-alt', alternateAppUpdate);

const invalidScenarios = ['wrong-issuer', 'wrong-audience', 'wrong-app-id', 'unknown-kid', 'expired'];
for (const scenario of invalidScenarios) {
  const invalid = await token({
    sub: `invalid-${scenario}-${runId}`,
    displayName: 'Invalid Token',
    scenario,
  });
  await request(api1, invalid, 'GET', '/v1/rooms', undefined, [401]);
}
const unprivilegedAdmin = await token({ type: 'admin', scenario: 'missing-scope' });
await request(api1, unprivilegedAdmin, 'GET', '/admin/v1/apps', undefined, [401, 403]);

const primaryId = `tenant-primary-${runId}`;
const alternateId = `tenant-alternate-${runId}`;
const primaryToken = await token({ sub: primaryId, displayName: 'Primary Tenant' });
const alternateToken = await token({
  appId: 'demo-alt',
  sub: alternateId,
  displayName: 'Alternate Tenant',
});
const primaryRoom = await request(api1, primaryToken, 'POST', '/v1/rooms', { title: `Tenant isolation ${runId}` });
await request(api2, alternateToken, 'GET', `/v1/rooms/${primaryRoom.id}`, undefined, [403]);
await request(
  api2,
  alternateToken,
  'POST',
  `/v1/rooms/${primaryRoom.id}/messages`,
  { text: 'cross-tenant-write-must-fail' },
  [403],
);
const crossTenantJoin = await fetch(`${api1}/v1/rooms/${primaryRoom.id}/join-requests`, {
  method: 'POST',
  headers: { authorization: `Bearer ${alternateToken}` },
});
assert(
  [403, 404].includes(crossTenantJoin.status),
  `Cross-tenant join request returned ${crossTenantJoin.status}`,
);

const isolationSocket = await connect(api2, alternateToken);
try {
  const rejectedSubscription = await ack(
    isolationSocket,
    'room.subscribe',
    { roomId: primaryRoom.id },
    false,
  );
  assert(
    rejectedSubscription.error?.code === 'membership_required',
    'Cross-tenant WebSocket subscription returned an unexpected error',
  );
  const isolatedEvent = `tenant-isolation-${runId}`;
  const noLeak = expectNoEvent(
    isolationSocket,
    (event) => event.roomId === primaryRoom.id || event.payload?.text === isolatedEvent,
  );
  await request(
    api1,
    primaryToken,
    'POST',
    `/v1/rooms/${primaryRoom.id}/messages`,
    { text: isolatedEvent },
  );
  await noLeak;
} finally {
  isolationSocket.close();
}

const expiring = await token({
  sub: primaryId,
  displayName: 'Primary Tenant',
  lifetimeSeconds: 8,
});
const expiringSocket = await connect(api2, expiring);
try {
  const disconnected = socketDisconnect(expiringSocket, 15_000);
  const expiryEvent = new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Timed out waiting for token expiry event')), 15_000);
    expiringSocket.once('study-room.auth-expired', (event) => {
      clearTimeout(timer);
      assert(event?.code === 'token_expired', 'Unexpected token expiry event');
      resolve();
    });
  });
  await expiryEvent;
  await disconnected;
} finally {
  expiringSocket.close();
}

const cachedOldToken = await token({ sub: `rotation-old-${runId}`, displayName: 'Old Key' });
await request(api1, cachedOldToken, 'GET', '/v1/rooms');
await fixtureControl('demo', 'rotate');
const rotatedToken = await token({ sub: `rotation-new-${runId}`, displayName: 'New Key' });
await request(api2, rotatedToken, 'GET', '/v1/rooms');
await request(api1, cachedOldToken, 'GET', '/v1/rooms');
await fixtureControl('demo', 'retire');
await delay(Number(process.env.E2E_JWKS_RETIRE_WAIT_MS ?? 2_500));
await request(api1, cachedOldToken, 'GET', '/v1/rooms', undefined, [401]);
await request(api2, rotatedToken, 'GET', '/v1/rooms');

const alternateSocket = await connect(api2, alternateToken);
const disconnected = socketDisconnect(alternateSocket);
try {
  await request(api1, adminToken, 'PATCH', '/admin/v1/apps/demo-alt', { enabled: false });
  await disconnected;
  await request(api2, alternateToken, 'GET', '/v1/rooms', undefined, [401]);
} finally {
  alternateSocket.close();
  await request(api1, adminToken, 'PATCH', '/admin/v1/apps/demo-alt', { enabled: true });
}

const result = {
  scenario: 'authentication-and-tenant-isolation',
  passed: true,
  startedAt: new Date(startedAt).toISOString(),
  endedAt: new Date().toISOString(),
  durationMs: Date.now() - startedAt,
  invalidTokenScenarios: invalidScenarios,
  tenantIsolation: {
    restReadDenied: true,
    restWriteDenied: true,
    joinRequestStatus: crossTenantJoin.status,
    websocketSubscriptionDenied: true,
    websocketEventLeak: false,
  },
  keyRotation: true,
  applicationDisableDisconnect: true,
};
if (resultPath) {
  await mkdir(dirname(resultPath), { recursive: true });
  await writeFile(resultPath, `${JSON.stringify(result, null, 2)}\n`);
}
console.log('Issuer, audience, appId, kid, expiry, scope, rotation, REST/WebSocket tenant isolation, and disable E2E passed.');
