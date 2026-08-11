import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

describe('database tenant and owner integrity migration', () => {
  const serverRoot = resolve(__dirname, '..');
  const schema = readFileSync(resolve(serverRoot, 'prisma', 'schema.prisma'), 'utf8');
  const foundationMigration = readFileSync(
    resolve(serverRoot, 'prisma', 'migrations', '20260809000100_v1_foundation', 'migration.sql'),
    'utf8',
  );
  const migration = readFileSync(
    resolve(
      serverRoot,
      'prisma',
      'migrations',
      '20260811000100_tenant_integrity_owner_constraints',
      'migration.sql',
    ),
    'utf8',
  );

  it('models every room child relation with the tenant discriminator', () => {
    expect(schema).toContain('@@unique([id, appId], map: "rooms_id_app_id_key")');
    for (const constraint of [
      'memberships_room_tenant_fk',
      'join_requests_room_tenant_fk',
      'sessions_room_tenant_fk',
      'messages_room_tenant_fk',
    ]) {
      expect(schema).toContain(`fields: [roomId, appId], references: [id, appId]`);
      expect(schema).toContain(`map: "${constraint}"`);
      expect(migration).toContain(`CONSTRAINT "${constraint}"`);
      expect(migration).toContain(`VALIDATE CONSTRAINT "${constraint}"`);
    }
  });

  it('models applicant and decider as distinct same-tenant relations', () => {
    expect(schema).toMatch(/joinRequests\s+JoinRequest\[\]\s+@relation\("JoinRequestApplicant"\)/);
    expect(schema).toMatch(/decidedJoinRequests\s+JoinRequest\[\]\s+@relation\("JoinRequestDecider"\)/);
    expect(schema).toContain('@relation("JoinRequestApplicant", fields: [appId, userId]');
    expect(schema).toContain('@relation("JoinRequestDecider", fields: [appId, decidedBy]');
    expect(migration).toContain('FOREIGN KEY ("app_id", "decided_by")');
    expect(migration).toContain('REFERENCES "tenant_users"("app_id", "user_id")');
  });

  it('runs data preflights before installing the constraints', () => {
    expect(migration.trimStart().startsWith('BEGIN;')).toBe(true);
    expect(migration.trimEnd().endsWith('COMMIT;')).toBe(true);
    const firstConstraint = migration.indexOf('ALTER TABLE "tenant_users"');
    expect(firstConstraint).toBeGreaterThan(0);
    for (const diagnostic of [
      'room child rows reference a room from another application',
      'tenant user IDs must contain between 1 and 256 characters',
      'every persisted room must have exactly one owner',
      'join request deciders must belong to the same application',
      'configured retention must be NULL or between 1 and 36500 days',
    ]) {
      const position = migration.indexOf(diagnostic);
      expect(position).toBeGreaterThan(0);
      expect(position).toBeLessThan(firstConstraint);
    }
  });

  it('enforces owner cardinality at transaction commit from both parent and child writes', () => {
    expect(foundationMigration).toContain(
      'CREATE UNIQUE INDEX "room_one_owner" ON "room_memberships" ("room_id") WHERE "role" = \'OWNER\';',
    );
    expect(migration).toContain('CREATE CONSTRAINT TRIGGER "rooms_exactly_one_owner_deferred"');
    expect(migration).toContain('CREATE CONSTRAINT TRIGGER "memberships_exactly_one_owner_deferred"');
    expect(migration.match(/DEFERRABLE INITIALLY DEFERRED/g)).toHaveLength(2);
    expect(migration).toContain("CONSTRAINT = 'room_exactly_one_owner'");
  });

  it('caps retention and persisted user identifiers', () => {
    expect(migration).toContain('CHECK (char_length("user_id") BETWEEN 1 AND 256)');
    expect(migration).toContain('"chat_retention_days" BETWEEN 1 AND 36500');
    expect(migration).toContain('"session_retention_days" BETWEEN 1 AND 36500');
    expect(migration).toContain('DROP CONSTRAINT "applications_chat_retention_positive"');
  });
});
