BEGIN;

-- Abort before changing constraints when legacy rows would violate the new tenant boundary.
DO $$
DECLARE
  mismatch_counts JSONB;
BEGIN
  SELECT jsonb_object_agg(source_table, violation_count)
  INTO mismatch_counts
  FROM (
    SELECT 'room_memberships' AS source_table, count(*) AS violation_count
    FROM "room_memberships" child
    JOIN "rooms" room ON room."id" = child."room_id"
    WHERE child."app_id" <> room."app_id"
    UNION ALL
    SELECT 'join_requests', count(*)
    FROM "join_requests" child
    JOIN "rooms" room ON room."id" = child."room_id"
    WHERE child."app_id" <> room."app_id"
    UNION ALL
    SELECT 'study_sessions', count(*)
    FROM "study_sessions" child
    JOIN "rooms" room ON room."id" = child."room_id"
    WHERE child."app_id" <> room."app_id"
    UNION ALL
    SELECT 'chat_messages', count(*)
    FROM "chat_messages" child
    JOIN "rooms" room ON room."id" = child."room_id"
    WHERE child."app_id" <> room."app_id"
  ) counts
  WHERE violation_count > 0;

  IF mismatch_counts IS NOT NULL THEN
    RAISE EXCEPTION USING
      MESSAGE = 'Tenant-integrity preflight failed: room child rows reference a room from another application',
      DETAIL = mismatch_counts::TEXT,
      HINT = 'Compare each child table app_id with rooms.app_id for the matching room_id, repair the rows, and rerun the migration.';
  END IF;
END
$$;

DO $$
DECLARE
  invalid_count BIGINT;
  invalid_samples TEXT[];
BEGIN
  SELECT count(*), (array_agg("app_id" || ':' || "user_id" ORDER BY "app_id", "user_id"))[1:10]
  INTO invalid_count, invalid_samples
  FROM "tenant_users"
  WHERE char_length("user_id") < 1 OR char_length("user_id") > 256;

  IF invalid_count > 0 THEN
    RAISE EXCEPTION USING
      MESSAGE = 'Tenant-integrity preflight failed: tenant user IDs must contain between 1 and 256 characters',
      DETAIL = format('count=%s samples=%s', invalid_count, invalid_samples),
      HINT = 'Repair tenant_users.user_id and all referencing rows before rerunning the migration.';
  END IF;
END
$$;

DO $$
DECLARE
  missing_owner_count BIGINT;
  multiple_owner_count BIGINT;
  invalid_room_samples UUID[];
BEGIN
  WITH owner_counts AS (
    SELECT room."id" AS room_id, count(membership."room_id") AS owner_count
    FROM "rooms" room
    LEFT JOIN "room_memberships" membership
      ON membership."room_id" = room."id" AND membership."role" = 'OWNER'
    GROUP BY room."id"
  )
  SELECT
    count(*) FILTER (WHERE owner_count = 0),
    count(*) FILTER (WHERE owner_count > 1),
    (array_agg(room_id ORDER BY room_id) FILTER (WHERE owner_count <> 1))[1:10]
  INTO missing_owner_count, multiple_owner_count, invalid_room_samples
  FROM owner_counts;

  IF missing_owner_count > 0 OR multiple_owner_count > 0 THEN
    RAISE EXCEPTION USING
      MESSAGE = 'Owner-integrity preflight failed: every persisted room must have exactly one owner',
      DETAIL = format(
        'missing_owner=%s multiple_owners=%s sample_room_ids=%s',
        missing_owner_count,
        multiple_owner_count,
        invalid_room_samples
      ),
      HINT = 'Create the missing OWNER membership or reduce duplicate OWNER memberships before rerunning the migration.';
  END IF;
END
$$;

DO $$
DECLARE
  invalid_count BIGINT;
  invalid_samples UUID[];
BEGIN
  SELECT count(*), (array_agg(request."id" ORDER BY request."id"))[1:10]
  INTO invalid_count, invalid_samples
  FROM "join_requests" request
  LEFT JOIN "tenant_users" decider
    ON decider."app_id" = request."app_id" AND decider."user_id" = request."decided_by"
  WHERE request."decided_by" IS NOT NULL AND decider."user_id" IS NULL;

  IF invalid_count > 0 THEN
    RAISE EXCEPTION USING
      MESSAGE = 'Tenant-integrity preflight failed: join request deciders must belong to the same application',
      DETAIL = format('count=%s sample_request_ids=%s', invalid_count, invalid_samples),
      HINT = 'Set decided_by to a tenant_users.user_id from the same app_id, or clear invalid historical deciders.';
  END IF;
END
$$;

DO $$
DECLARE
  invalid_count BIGINT;
BEGIN
  SELECT count(*)
  INTO invalid_count
  FROM "applications"
  WHERE ("chat_retention_days" IS NOT NULL AND "chat_retention_days" NOT BETWEEN 1 AND 36500)
     OR ("session_retention_days" IS NOT NULL AND "session_retention_days" NOT BETWEEN 1 AND 36500);

  IF invalid_count > 0 THEN
    RAISE EXCEPTION USING
      MESSAGE = 'Retention preflight failed: configured retention must be NULL or between 1 and 36500 days',
      DETAIL = format('applications=%s', invalid_count),
      HINT = 'Reduce chat_retention_days and session_retention_days to at most 36500 before rerunning the migration.';
  END IF;
END
$$;

ALTER TABLE "tenant_users"
  ADD CONSTRAINT "tenant_users_user_id_length"
  CHECK (char_length("user_id") BETWEEN 1 AND 256) NOT VALID;
ALTER TABLE "tenant_users" VALIDATE CONSTRAINT "tenant_users_user_id_length";

ALTER TABLE "applications"
  ADD CONSTRAINT "applications_chat_retention_range"
  CHECK ("chat_retention_days" IS NULL OR "chat_retention_days" BETWEEN 1 AND 36500) NOT VALID,
  ADD CONSTRAINT "applications_session_retention_range"
  CHECK ("session_retention_days" IS NULL OR "session_retention_days" BETWEEN 1 AND 36500) NOT VALID;
ALTER TABLE "applications" VALIDATE CONSTRAINT "applications_chat_retention_range";
ALTER TABLE "applications" VALIDATE CONSTRAINT "applications_session_retention_range";
ALTER TABLE "applications"
  DROP CONSTRAINT "applications_chat_retention_positive",
  DROP CONSTRAINT "applications_session_retention_positive";

ALTER TABLE "rooms"
  ADD CONSTRAINT "rooms_id_app_id_key" UNIQUE ("id", "app_id");

ALTER TABLE "room_memberships"
  ADD CONSTRAINT "memberships_room_tenant_fk"
  FOREIGN KEY ("room_id", "app_id") REFERENCES "rooms"("id", "app_id")
  ON DELETE CASCADE ON UPDATE CASCADE NOT VALID;
ALTER TABLE "join_requests"
  ADD CONSTRAINT "join_requests_room_tenant_fk"
  FOREIGN KEY ("room_id", "app_id") REFERENCES "rooms"("id", "app_id")
  ON DELETE CASCADE ON UPDATE CASCADE NOT VALID;
ALTER TABLE "study_sessions"
  ADD CONSTRAINT "sessions_room_tenant_fk"
  FOREIGN KEY ("room_id", "app_id") REFERENCES "rooms"("id", "app_id")
  ON DELETE CASCADE ON UPDATE CASCADE NOT VALID;
ALTER TABLE "chat_messages"
  ADD CONSTRAINT "messages_room_tenant_fk"
  FOREIGN KEY ("room_id", "app_id") REFERENCES "rooms"("id", "app_id")
  ON DELETE CASCADE ON UPDATE CASCADE NOT VALID;

ALTER TABLE "room_memberships" VALIDATE CONSTRAINT "memberships_room_tenant_fk";
ALTER TABLE "join_requests" VALIDATE CONSTRAINT "join_requests_room_tenant_fk";
ALTER TABLE "study_sessions" VALIDATE CONSTRAINT "sessions_room_tenant_fk";
ALTER TABLE "chat_messages" VALIDATE CONSTRAINT "messages_room_tenant_fk";

ALTER TABLE "room_memberships" DROP CONSTRAINT "memberships_room_fk";
ALTER TABLE "join_requests" DROP CONSTRAINT "join_requests_room_fk";
ALTER TABLE "study_sessions" DROP CONSTRAINT "sessions_room_fk";
ALTER TABLE "chat_messages" DROP CONSTRAINT "messages_room_fk";

ALTER TABLE "join_requests"
  ADD CONSTRAINT "join_requests_decided_by_fk"
  FOREIGN KEY ("app_id", "decided_by") REFERENCES "tenant_users"("app_id", "user_id")
  ON DELETE NO ACTION ON UPDATE NO ACTION NOT VALID;
ALTER TABLE "join_requests" VALIDATE CONSTRAINT "join_requests_decided_by_fk";

CREATE FUNCTION "assert_room_has_exactly_one_owner"(target_room_id UUID)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  owner_count BIGINT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "rooms" WHERE "id" = target_room_id) THEN
    RETURN;
  END IF;

  SELECT count(*)
  INTO owner_count
  FROM "room_memberships"
  WHERE "room_id" = target_room_id AND "role" = 'OWNER';

  IF owner_count <> 1 THEN
    RAISE EXCEPTION USING
      ERRCODE = '23514',
      CONSTRAINT = 'room_exactly_one_owner',
      MESSAGE = format('Room %s must have exactly one owner; found %s', target_room_id, owner_count);
  END IF;
END
$$;

CREATE FUNCTION "enforce_room_exactly_one_owner"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_TABLE_NAME = 'rooms' THEN
    IF TG_OP <> 'DELETE' THEN
      PERFORM "assert_room_has_exactly_one_owner"(NEW."id");
    END IF;
    IF TG_OP = 'UPDATE' AND OLD."id" IS DISTINCT FROM NEW."id" THEN
      PERFORM "assert_room_has_exactly_one_owner"(OLD."id");
    END IF;
  ELSIF TG_OP = 'INSERT' THEN
    PERFORM "assert_room_has_exactly_one_owner"(NEW."room_id");
  ELSIF TG_OP = 'DELETE' THEN
    PERFORM "assert_room_has_exactly_one_owner"(OLD."room_id");
  ELSE
    PERFORM "assert_room_has_exactly_one_owner"(NEW."room_id");
    IF OLD."room_id" IS DISTINCT FROM NEW."room_id" THEN
      PERFORM "assert_room_has_exactly_one_owner"(OLD."room_id");
    END IF;
  END IF;
  RETURN NULL;
END
$$;

CREATE CONSTRAINT TRIGGER "rooms_exactly_one_owner_deferred"
AFTER INSERT OR UPDATE ON "rooms"
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION "enforce_room_exactly_one_owner"();

CREATE CONSTRAINT TRIGGER "memberships_exactly_one_owner_deferred"
AFTER INSERT OR UPDATE OR DELETE ON "room_memberships"
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION "enforce_room_exactly_one_owner"();

COMMIT;
