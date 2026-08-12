# 0.4 deployment

## Topology

The included Compose topology is nginx → two stateless API instances → PostgreSQL and Redis. Redis carries Socket.IO adapter traffic, application invalidation, and presence keys. PostgreSQL is authoritative for applications, users, rooms, memberships, approvals, sessions, messages, and audit logs.

Use an external managed PostgreSQL/Redis service in production. Run `prisma migrate deploy` once before replacing API instances. Do not mix 0.3 and 0.4 instances behind one endpoint.

## Tenant-integrity migration rehearsal

Before applying the 0.4 migration in production, restore a current production
snapshot into an isolated PostgreSQL database and run `prisma migrate deploy`
against that clone. The migration intentionally aborts without repairing data
when it finds cross-tenant room children, user IDs outside 1–256 characters,
rooms without exactly one owner, invalid `decided_by` users, or retention
values outside `NULL`/1–36500. Preserve the PostgreSQL `MESSAGE`, `DETAIL`, and
`HINT` diagnostics, repair the source data through an audited process, refresh
the snapshot, and repeat the rehearsal before scheduling the production run.

The migration adds and validates the new composite foreign keys before
dropping the legacy room foreign keys. The owner constraint triggers are
deferred until transaction commit, so room creation and ownership transfer
must keep their room and membership writes in the same transaction.

## Required configuration

- `DATABASE_URL`: PostgreSQL connection URL.
- `REDIS_URL`: Redis URL.
- `STUDY_ROOM_ADMIN_JWKS_URL`, `STUDY_ROOM_ADMIN_JWT_ISSUER`, `STUDY_ROOM_ADMIN_JWT_AUDIENCE`: independent admin trust configuration.
- `STUDY_ROOM_RUNTIME_PROFILE`: `production`, `dev`, or `test`; defaults to `production`.
- `STUDY_ROOM_ALLOWED_ORIGINS`: comma-separated exact CORS origins.
- `PORT`: listener port, default `3000`.

Optional controls:

- `STUDY_ROOM_IP_RATE_LIMIT`, `STUDY_ROOM_APP_RATE_LIMIT`, `STUDY_ROOM_USER_RATE_LIMIT`, `STUDY_ROOM_ADMIN_RATE_LIMIT`: fixed 60-second IP/application/user/administrator quotas; defaults are 120/600/180/120.
- `STUDY_ROOM_TRUST_PROXY_HOPS`: trusted reverse-proxy hop count used to derive the client IP; set it only to the exact topology depth.
- `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` and `OTEL_SERVICE_NAME`: enable OTLP HTTP traces.
- `STUDY_ROOM_ALLOW_INSECURE_JWKS=true`: permits HTTP JWKS only when the runtime profile is explicitly `dev` or `test`, and only for localhost, loopback addresses, or the Compose `jwks` host. Production rejects HTTP regardless of this flag.

Every registered application supplies its own issuer, audience, JWKS URI, enabled state, and nullable chat/session retention days. `null` means permanent retention. The daily 03:00 cleanup uses a PostgreSQL advisory transaction lock, so only one instance deletes expired rows.

Startup validates the administrator JWKS URI and every persisted application JWKS URI before accepting traffic. An existing HTTP registration therefore prevents a production-profile instance from starting until the registration is repaired.

## Security and operations

- Terminate TLS and expose only HTTPS/WSS.
- Do not expose PostgreSQL or Redis ports publicly.
- Admin tokens require a valid signature, issuer, audience, expiry, and `apps:manage` scope. Metrics additionally require `metrics:read`.
- User tokens require `sub`, `appId`, `displayName`, `iss`, `aud`, and `exp`; only RS256 and ES256 with a `kid` are accepted.
- Keep tokens and chat text out of URLs and logs. JSON production logs contain request IDs but not authorization headers or message bodies.
- Scrape `/metrics` using an admin token. Probe `/health/live` for process health and `/health/ready` for PostgreSQL/Redis readiness.
- Allow at least the 15-second HTTP timeout and 60-second presence TTL during rolling deployments. Shutdown hooks close HTTP, Prisma, Redis, and telemetry resources.

## Compose smoke test

The default profile contains no fixture services. Use `.env.example`, configure an external HTTPS administrator JWKS, and start it without `--profile` for production-style validation.

For the local fixture flow:

```sh
cp .env.dev.example .env.dev
# Replace the placeholder password and fixture control token.
docker compose --env-file .env.dev --profile dev config
docker compose --env-file .env.dev --profile dev up --build
curl http://localhost:3000/health/ready
curl -X POST http://localhost:4000/token -H "content-type: application/json" -d '{"sub":"user-1","displayName":"User One"}'
```

The JWKS container generates independent RS256/ES256 application keys plus an admin key at startup and exposes an unauthenticated token endpoint. Browser preflight and credential-free CORS are enabled only for `/token`; `/__test` controls deliberately expose no CORS headers. The fixture exists only in the explicit `dev`/`test` profiles and must not be deployed to production. Key rotation/retirement controls under `/__test` require an explicit `E2E_FIXTURE_CONTROL_TOKEN`; Compose provides no default token.

CI uses the `test` profile and injects a fresh database password and fixture control token for every run:

```sh
docker compose --env-file .env.test --profile test up --build --detach --wait postgres redis jwks
docker compose --env-file .env.test --profile test run --rm migrate
docker compose --env-file .env.test --profile test run --rm --no-deps seed
docker compose --env-file .env.test --profile test up --build --detach --wait proxy
docker compose --env-file .env.test --profile test run --rm e2e
```

The `core` Compose integration job runs phased persistence checks through the
`study_room_e2e_state` volume. It stops both APIs and PostgreSQL, starts the
same database volume again, and verifies the stored room, membership, chat
message, and active sessions through both API instances. The core flow also
exercises concurrent join requests, concurrent active-session creation, the
complete remove/leave/rejoin/ownership-transfer/delete lifecycle, and
cross-tenant REST and WebSocket isolation.

The `resilience` job starts the OpenTelemetry Collector only through the
explicit `test` profile. It exports traces to a JSON-lines file, verifies spans
from both API instance IDs with `service.name=study-room-server`, and confirms
that `docker stop --timeout 15 api-1` exits cleanly and flushes telemetry while
the proxy continues to serve through `api-2`. A separate crash scenario
disables the `api-2` restart policy, sends `SIGKILL`, records the Redis
connection/index TTL before and after refresh, and waits for those keys to
expire before recreating the instance.

All five Compose jobs upload timestamped logs, `compose-ps.json`, structured
scenario results, and `service-images.json`. The image evidence maps running
services to container IDs, immutable image IDs, and available repository
digests, and each job directly asserts that `api-1` and `api-2` use the same
image ID. Every job removes its isolated containers, networks, and named
volumes after evidence upload.
