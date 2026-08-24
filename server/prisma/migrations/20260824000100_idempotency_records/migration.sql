BEGIN;

CREATE TABLE "idempotency_records" (
  "app_id" VARCHAR(64) NOT NULL,
  "user_id" TEXT NOT NULL,
  "operation" VARCHAR(64) NOT NULL,
  "key" VARCHAR(128) NOT NULL,
  "request_hash" VARCHAR(64) NOT NULL,
  "resource_id" UUID NOT NULL,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "idempotency_records_pkey"
    PRIMARY KEY ("app_id", "user_id", "operation", "key"),
  CONSTRAINT "idempotency_records_application_fk"
    FOREIGN KEY ("app_id") REFERENCES "applications"("app_id")
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "idempotency_records_user_fk"
    FOREIGN KEY ("app_id", "user_id") REFERENCES "tenant_users"("app_id", "user_id")
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "idempotency_records_operation_check"
    CHECK ("operation" IN ('rooms.create', 'chat.send', 'sessions.start')),
  CONSTRAINT "idempotency_records_key_check"
    CHECK ("key" ~ '^[A-Za-z0-9._:-]{1,128}$'),
  CONSTRAINT "idempotency_records_request_hash_check"
    CHECK ("request_hash" ~ '^[0-9a-f]{64}$')
);

CREATE INDEX "idempotency_records_created_at_idx"
  ON "idempotency_records"("created_at");

COMMIT;
