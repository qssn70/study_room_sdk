CREATE TYPE "RoomRole" AS ENUM ('OWNER', 'MEMBER');
CREATE TYPE "JoinRequestStatus" AS ENUM ('PENDING', 'APPROVED', 'REJECTED', 'CANCELLED');
CREATE TYPE "SessionStatus" AS ENUM ('RUNNING', 'PAUSED', 'FINISHED');

CREATE TABLE "applications" (
  "app_id" VARCHAR(64) PRIMARY KEY,
  "issuer" TEXT NOT NULL,
  "audience" TEXT NOT NULL,
  "jwks_uri" TEXT NOT NULL,
  "enabled" BOOLEAN NOT NULL DEFAULT true,
  "chat_retention_days" INTEGER,
  "session_retention_days" INTEGER,
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "applications_chat_retention_positive" CHECK ("chat_retention_days" IS NULL OR "chat_retention_days" > 0),
  CONSTRAINT "applications_session_retention_positive" CHECK ("session_retention_days" IS NULL OR "session_retention_days" > 0)
);

CREATE TABLE "tenant_users" (
  "app_id" VARCHAR(64) NOT NULL,
  "user_id" TEXT NOT NULL,
  "display_name" TEXT NOT NULL,
  "avatar_url" TEXT NOT NULL DEFAULT '',
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY ("app_id", "user_id"),
  CONSTRAINT "tenant_users_application_fk" FOREIGN KEY ("app_id") REFERENCES "applications"("app_id") ON DELETE CASCADE
);

CREATE TABLE "rooms" (
  "id" UUID PRIMARY KEY,
  "app_id" VARCHAR(64) NOT NULL,
  "title" VARCHAR(100) NOT NULL,
  "version" INTEGER NOT NULL DEFAULT 1,
  "deleted_at" TIMESTAMPTZ,
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "rooms_application_fk" FOREIGN KEY ("app_id") REFERENCES "applications"("app_id") ON DELETE CASCADE
);

CREATE TABLE "room_memberships" (
  "room_id" UUID NOT NULL,
  "app_id" VARCHAR(64) NOT NULL,
  "user_id" TEXT NOT NULL,
  "role" "RoomRole" NOT NULL,
  "joined_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY ("room_id", "user_id"),
  CONSTRAINT "memberships_room_fk" FOREIGN KEY ("room_id") REFERENCES "rooms"("id") ON DELETE CASCADE,
  CONSTRAINT "memberships_user_fk" FOREIGN KEY ("app_id", "user_id") REFERENCES "tenant_users"("app_id", "user_id") ON DELETE CASCADE
);
CREATE UNIQUE INDEX "room_one_owner" ON "room_memberships" ("room_id") WHERE "role" = 'OWNER';

CREATE TABLE "join_requests" (
  "id" UUID PRIMARY KEY,
  "room_id" UUID NOT NULL,
  "app_id" VARCHAR(64) NOT NULL,
  "user_id" TEXT NOT NULL,
  "status" "JoinRequestStatus" NOT NULL DEFAULT 'PENDING',
  "decided_by" TEXT,
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "join_requests_room_fk" FOREIGN KEY ("room_id") REFERENCES "rooms"("id") ON DELETE CASCADE,
  CONSTRAINT "join_requests_user_fk" FOREIGN KEY ("app_id", "user_id") REFERENCES "tenant_users"("app_id", "user_id") ON DELETE CASCADE
);
CREATE UNIQUE INDEX "join_requests_one_pending" ON "join_requests" ("room_id", "user_id") WHERE "status" = 'PENDING';

CREATE TABLE "study_sessions" (
  "id" UUID PRIMARY KEY,
  "room_id" UUID NOT NULL,
  "app_id" VARCHAR(64) NOT NULL,
  "user_id" TEXT NOT NULL,
  "status" "SessionStatus" NOT NULL DEFAULT 'RUNNING',
  "started_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "finished_at" TIMESTAMPTZ,
  "updated_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "sessions_room_fk" FOREIGN KEY ("room_id") REFERENCES "rooms"("id") ON DELETE CASCADE,
  CONSTRAINT "sessions_user_fk" FOREIGN KEY ("app_id", "user_id") REFERENCES "tenant_users"("app_id", "user_id") ON DELETE CASCADE
);
CREATE UNIQUE INDEX "sessions_one_active" ON "study_sessions" ("room_id", "user_id") WHERE "status" IN ('RUNNING', 'PAUSED');

CREATE TABLE "chat_messages" (
  "id" UUID PRIMARY KEY,
  "room_id" UUID NOT NULL,
  "app_id" VARCHAR(64) NOT NULL,
  "sender_id" TEXT NOT NULL,
  "text" VARCHAR(2000) NOT NULL,
  "sent_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "messages_room_fk" FOREIGN KEY ("room_id") REFERENCES "rooms"("id") ON DELETE CASCADE,
  CONSTRAINT "messages_sender_fk" FOREIGN KEY ("app_id", "sender_id") REFERENCES "tenant_users"("app_id", "user_id") ON DELETE CASCADE
);

CREATE TABLE "audit_logs" (
  "id" UUID PRIMARY KEY,
  "app_id" VARCHAR(64),
  "actor_id" TEXT NOT NULL,
  "action" TEXT NOT NULL,
  "resource_id" TEXT,
  "metadata" JSONB,
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "audit_application_fk" FOREIGN KEY ("app_id") REFERENCES "applications"("app_id") ON DELETE SET NULL
);

CREATE INDEX "rooms_app_deleted_idx" ON "rooms" ("app_id", "deleted_at");
CREATE INDEX "memberships_user_idx" ON "room_memberships" ("app_id", "user_id");
CREATE INDEX "join_requests_user_idx" ON "join_requests" ("app_id", "user_id", "status");
CREATE INDEX "join_requests_room_idx" ON "join_requests" ("room_id", "status");
CREATE INDEX "sessions_user_idx" ON "study_sessions" ("app_id", "user_id", "status");
CREATE INDEX "messages_cursor_idx" ON "chat_messages" ("room_id", "sent_at", "id");
CREATE INDEX "audit_app_created_idx" ON "audit_logs" ("app_id", "created_at");
