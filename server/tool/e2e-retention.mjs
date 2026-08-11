import { createHash, randomUUID } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import { PrismaClient } from '@prisma/client';
import pg from 'pg';
import { RetentionService } from '../dist/operations/retention.service.js';
import { assert, delay, runId } from './e2e-support.mjs';

const { Client } = pg;
const databaseUrl = process.env.DATABASE_URL;
const resultPath = process.env.E2E_RESULT_PATH;
assert(databaseUrl, 'DATABASE_URL is required for retention E2E');

const suffix = createHash('sha256').update(runId).digest('hex').slice(0, 12);
const appId = `retention-${suffix}`;
const ownerId = `retention-owner-${suffix}`;
const roomId = randomUUID();
const oldMessageId = randomUUID();
const freshMessageId = randomUUID();
const oldFinishedId = randomUUID();
const freshFinishedId = randomUUID();
const runningId = randomUUID();
const startedAt = Date.now();
const client = new Client({ connectionString: databaseUrl });
const prisma = new PrismaClient();
let counts;
let cleanAttempts = 0;
let failure;

function messageFor(error) {
  return error instanceof Error ? error.message : String(error);
}

try {
  await client.connect();
  await client.query('BEGIN');
  await client.query(
    `INSERT INTO "applications"
       ("app_id", "issuer", "audience", "jwks_uri", "enabled", "chat_retention_days", "session_retention_days")
     VALUES ($1, 'https://retention.example', 'study-room-api', 'https://retention.example/jwks.json', false, 1, 1)`,
    [appId],
  );
  await client.query(
    `INSERT INTO "tenant_users" ("app_id", "user_id", "display_name") VALUES ($1, $2, 'Retention Owner')`,
    [appId, ownerId],
  );
  await client.query(
    `INSERT INTO "rooms" ("id", "app_id", "title") VALUES ($1, $2, 'Disabled retention E2E')`,
    [roomId, appId],
  );
  await client.query(
    `INSERT INTO "room_memberships" ("room_id", "app_id", "user_id", "role") VALUES ($1, $2, $3, 'OWNER')`,
    [roomId, appId, ownerId],
  );
  await client.query(
    `INSERT INTO "chat_messages" ("id", "room_id", "app_id", "sender_id", "text", "sent_at")
     VALUES ($1, $3, $4, $5, 'expired', NOW() - INTERVAL '2 days'),
            ($2, $3, $4, $5, 'fresh', NOW())`,
    [oldMessageId, freshMessageId, roomId, appId, ownerId],
  );
  await client.query(
    `INSERT INTO "study_sessions"
       ("id", "room_id", "app_id", "user_id", "status", "started_at", "finished_at", "updated_at")
     VALUES ($1, $4, $5, $6, 'FINISHED', NOW() - INTERVAL '3 days', NOW() - INTERVAL '2 days', NOW() - INTERVAL '2 days'),
            ($2, $4, $5, $6, 'FINISHED', NOW(), NOW(), NOW()),
            ($3, $4, $5, $6, 'RUNNING', NOW() - INTERVAL '2 days', NULL, NOW())`,
    [oldFinishedId, freshFinishedId, runningId, roomId, appId, ownerId],
  );
  await client.query('COMMIT');

  const retention = new RetentionService(prisma);
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    cleanAttempts = attempt;
    await retention.clean();
    const expired = await client.query(
      `SELECT
         (SELECT count(*) FROM "chat_messages" WHERE "id" = $1) +
         (SELECT count(*) FROM "study_sessions" WHERE "id" = $2) AS "remaining"`,
      [oldMessageId, oldFinishedId],
    );
    if (Number(expired.rows[0].remaining) === 0) break;
    await delay(250);
  }

  const messageRows = await client.query(
    `SELECT "id"::text FROM "chat_messages" WHERE "id" = ANY($1::uuid[]) ORDER BY "id"`,
    [[oldMessageId, freshMessageId]],
  );
  const sessionRows = await client.query(
    `SELECT "id"::text, "status"::text FROM "study_sessions" WHERE "id" = ANY($1::uuid[]) ORDER BY "id"`,
    [[oldFinishedId, freshFinishedId, runningId]],
  );
  const remainingMessages = messageRows.rows.map((row) => row.id);
  const remainingSessions = sessionRows.rows.map((row) => ({ id: row.id, status: row.status }));

  assert(!remainingMessages.includes(oldMessageId), 'Expired chat message for a disabled application was not deleted');
  assert(remainingMessages.includes(freshMessageId), 'Fresh chat message was deleted');
  assert(!remainingSessions.some((row) => row.id === oldFinishedId), 'Expired finished session for a disabled application was not deleted');
  assert(remainingSessions.some((row) => row.id === freshFinishedId), 'Fresh finished session was deleted');
  assert(
    remainingSessions.some((row) => row.id === runningId && row.status === 'RUNNING'),
    'Running session without finishedAt was deleted',
  );
  counts = {
    messagesBefore: 2,
    messagesAfter: remainingMessages.length,
    sessionsBefore: 3,
    sessionsAfter: remainingSessions.length,
    remainingMessages,
    remainingSessions,
  };
} catch (error) {
  failure = messageFor(error);
} finally {
  await client.query('ROLLBACK').catch(() => undefined);
  await client.query(`DELETE FROM "applications" WHERE "app_id" = $1`, [appId]).catch(() => undefined);
  await prisma.$disconnect().catch(() => undefined);
  await client.end().catch(() => undefined);

  const result = {
    scenario: 'disabled-application-retention',
    passed: failure === undefined,
    startedAt: new Date(startedAt).toISOString(),
    endedAt: new Date().toISOString(),
    durationMs: Date.now() - startedAt,
    applicationEnabled: false,
    retentionDays: { chat: 1, session: 1 },
    cleanAttempts,
    counts: counts ?? null,
    failure: failure ?? null,
  };
  if (resultPath) {
    await mkdir(dirname(resultPath), { recursive: true });
    await writeFile(resultPath, JSON.stringify(result, null, 2));
  }
}

if (failure) throw new Error(failure);
console.log('Disabled-application retention deleted only expired chat and finished-session data.');
