import { createHash, randomUUID } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import pg from 'pg';
import { assert, runId } from './e2e-support.mjs';

const { Client } = pg;
const databaseUrl = process.env.DATABASE_URL;
const resultPath = process.env.E2E_RESULT_PATH;
assert(databaseUrl, 'DATABASE_URL is required for database integrity E2E');

const suffix = createHash('sha256').update(runId).digest('hex').slice(0, 12);
const appA = `db-a-${suffix}`;
const appB = `db-b-${suffix}`;
const ownerA = `owner-a-${suffix}`;
const memberA = `member-a-${suffix}`;
const userB = `user-b-${suffix}`;
const roomA = randomUUID();
const checks = [];
const startedAt = Date.now();
const client = new Client({ connectionString: databaseUrl });
let failure;

function messageFor(error) {
  return error instanceof Error ? error.message : String(error);
}

async function expectDatabaseError(name, expected, action) {
  await client.query('BEGIN');
  try {
    await action();
    await client.query('ROLLBACK');
    throw new Error(`${name} unexpectedly committed`);
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    assert(error?.code === expected.code, `${name} returned SQLSTATE ${error?.code ?? 'none'}, expected ${expected.code}`);
    assert(
      error?.constraint === expected.constraint,
      `${name} reported constraint ${error?.constraint ?? 'none'}, expected ${expected.constraint}`,
    );
    checks.push({ name, sqlState: error.code, constraint: error.constraint, passed: true });
  }
}

try {
  await client.connect();
  await client.query('BEGIN');
  await client.query(
    `INSERT INTO "applications" ("app_id", "issuer", "audience", "jwks_uri", "enabled")
     VALUES ($1, 'https://issuer-a.example', 'study-room-api', 'https://issuer-a.example/jwks.json', true),
            ($2, 'https://issuer-b.example', 'study-room-api', 'https://issuer-b.example/jwks.json', true)`,
    [appA, appB],
  );
  await client.query(
    `INSERT INTO "tenant_users" ("app_id", "user_id", "display_name")
     VALUES ($1, $2, 'Owner A'), ($1, $3, 'Member A'), ($4, $5, 'User B')`,
    [appA, ownerA, memberA, appB, userB],
  );
  await client.query(
    `INSERT INTO "rooms" ("id", "app_id", "title") VALUES ($1, $2, 'Database integrity E2E')`,
    [roomA, appA],
  );
  await client.query(
    `INSERT INTO "room_memberships" ("room_id", "app_id", "user_id", "role")
     VALUES ($1, $2, $3, 'OWNER')`,
    [roomA, appA, ownerA],
  );
  await client.query('COMMIT');

  await expectDatabaseError(
    'cross-tenant room child',
    { code: '23503', constraint: 'memberships_room_tenant_fk' },
    () => client.query(
      `INSERT INTO "room_memberships" ("room_id", "app_id", "user_id", "role")
       VALUES ($1, $2, $3, 'MEMBER')`,
      [roomA, appB, userB],
    ),
  );

  await expectDatabaseError(
    'cross-tenant join-request room child',
    { code: '23503', constraint: 'join_requests_room_tenant_fk' },
    () => client.query(
      `INSERT INTO "join_requests" ("id", "room_id", "app_id", "user_id", "status")
       VALUES ($1, $2, $3, $4, 'PENDING')`,
      [randomUUID(), roomA, appB, userB],
    ),
  );

  await expectDatabaseError(
    'cross-tenant session room child',
    { code: '23503', constraint: 'sessions_room_tenant_fk' },
    () => client.query(
      `INSERT INTO "study_sessions" ("id", "room_id", "app_id", "user_id", "status")
       VALUES ($1, $2, $3, $4, 'RUNNING')`,
      [randomUUID(), roomA, appB, userB],
    ),
  );

  await expectDatabaseError(
    'cross-tenant chat-message room child',
    { code: '23503', constraint: 'messages_room_tenant_fk' },
    () => client.query(
      `INSERT INTO "chat_messages" ("id", "room_id", "app_id", "sender_id", "text")
       VALUES ($1, $2, $3, $4, 'cross-tenant')`,
      [randomUUID(), roomA, appB, userB],
    ),
  );

  await expectDatabaseError(
    'cross-tenant join-request decider',
    { code: '23503', constraint: 'join_requests_decided_by_fk' },
    () => client.query(
      `INSERT INTO "join_requests" ("id", "room_id", "app_id", "user_id", "status", "decided_by")
       VALUES ($1, $2, $3, $4, 'REJECTED', $5)`,
      [randomUUID(), roomA, appA, memberA, userB],
    ),
  );

  await expectDatabaseError(
    'room without owner',
    { code: '23514', constraint: 'room_exactly_one_owner' },
    async () => {
      await client.query(
        `INSERT INTO "rooms" ("id", "app_id", "title") VALUES ($1, $2, 'Ownerless room')`,
        [randomUUID(), appA],
      );
      await client.query('SET CONSTRAINTS ALL IMMEDIATE');
    },
  );

  await expectDatabaseError(
    'delete last owner',
    { code: '23514', constraint: 'room_exactly_one_owner' },
    async () => {
      await client.query(
        `DELETE FROM "room_memberships" WHERE "room_id" = $1 AND "user_id" = $2`,
        [roomA, ownerA],
      );
      await client.query('SET CONSTRAINTS ALL IMMEDIATE');
    },
  );

  await expectDatabaseError(
    'second owner',
    { code: '23505', constraint: 'room_one_owner' },
    () => client.query(
      `INSERT INTO "room_memberships" ("room_id", "app_id", "user_id", "role")
       VALUES ($1, $2, $3, 'OWNER')`,
      [roomA, appA, memberA],
    ),
  );
} catch (error) {
  failure = messageFor(error);
} finally {
  await client.query('ROLLBACK').catch(() => undefined);
  await client.query(`DELETE FROM "applications" WHERE "app_id" = ANY($1::text[])`, [[appA, appB]])
    .catch(() => undefined);
  await client.end().catch(() => undefined);

  const result = {
    scenario: 'database-tenant-owner-integrity',
    passed: failure === undefined,
    startedAt: new Date(startedAt).toISOString(),
    endedAt: new Date().toISOString(),
    durationMs: Date.now() - startedAt,
    checks,
    failure: failure ?? null,
  };
  if (resultPath) {
    await mkdir(dirname(resultPath), { recursive: true });
    await writeFile(resultPath, JSON.stringify(result, null, 2));
  }
}

if (failure) throw new Error(failure);
console.log(`Database tenant and owner constraints rejected ${checks.length} invalid writes.`);
