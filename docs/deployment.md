# 0.4 deployment

## Topology

The included Compose topology is nginx → two stateless API instances → PostgreSQL and Redis. Redis carries Socket.IO adapter traffic, application invalidation, and presence keys. PostgreSQL is authoritative for applications, users, rooms, memberships, approvals, sessions, messages, and audit logs.

Use an external managed PostgreSQL/Redis service in production. Run `prisma migrate deploy` once before replacing API instances. Do not mix 0.3 and 0.4 instances behind one endpoint.

## Required configuration

- `DATABASE_URL`: PostgreSQL connection URL.
- `REDIS_URL`: Redis URL.
- `STUDY_ROOM_ADMIN_JWKS_URL`, `STUDY_ROOM_ADMIN_JWT_ISSUER`, `STUDY_ROOM_ADMIN_JWT_AUDIENCE`: independent admin trust configuration.
- `STUDY_ROOM_ALLOWED_ORIGINS`: comma-separated exact CORS origins.
- `PORT`: listener port, default `3000`.

Optional controls:

- `STUDY_ROOM_APP_RATE_LIMIT`, `STUDY_ROOM_USER_RATE_LIMIT`, `STUDY_ROOM_ADMIN_RATE_LIMIT`: per-minute limits; IP limiting defaults to 120 requests/minute.
- `STUDY_ROOM_TRUST_PROXY_HOPS`: trusted reverse-proxy hop count used to derive the client IP; set it only to the exact topology depth.
- `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` and `OTEL_SERVICE_NAME`: enable OTLP HTTP traces.
- `STUDY_ROOM_ALLOW_INSECURE_JWKS=true`: permits HTTP JWKS only for `localhost`, `127.0.0.1`, or the Compose `jwks` host. Never enable it for a public deployment.

Every registered application supplies its own issuer, audience, JWKS URI, enabled state, and nullable chat/session retention days. `null` means permanent retention. The daily 03:00 cleanup uses a PostgreSQL advisory transaction lock, so only one instance deletes expired rows.

## Security and operations

- Terminate TLS and expose only HTTPS/WSS.
- Do not expose PostgreSQL or Redis ports publicly.
- Admin tokens require a valid signature, issuer, audience, expiry, and `apps:manage` scope. Metrics additionally require `metrics:read`.
- User tokens require `sub`, `appId`, `displayName`, `iss`, `aud`, and `exp`; only RS256 and ES256 with a `kid` are accepted.
- Keep tokens and chat text out of URLs and logs. JSON production logs contain request IDs but not authorization headers or message bodies.
- Scrape `/metrics` using an admin token. Probe `/health/live` for process health and `/health/ready` for PostgreSQL/Redis readiness.
- Allow at least the 15-second HTTP timeout and 60-second presence TTL during rolling deployments. Shutdown hooks close HTTP, Prisma, Redis, and telemetry resources.

## Compose smoke test

```sh
cp .env.example .env
docker compose config
docker compose up --build
curl http://localhost:3000/health/ready
curl -X POST http://localhost:4000/token -H "content-type: application/json" -d '{"sub":"user-1","displayName":"User One"}'
docker compose --profile test run --rm e2e
```

The JWKS container generates independent RS256/ES256 application keys plus an admin key at startup and exposes an unauthenticated token endpoint. It is strictly a local fixture and must not be deployed to production. Key rotation/retirement controls under `/__test` require `E2E_FIXTURE_CONTROL_TOKEN`.

The main-branch and manually dispatched Compose integration workflow additionally runs phased persistence checks through the `study_room_e2e_state` volume. It stops both APIs, restarts PostgreSQL, restores the APIs, and verifies the stored room, membership, chat message, and active session. A separate crash scenario disables the `api-2` restart policy, sends `SIGKILL`, and waits for its Redis presence keys to expire before recreating the instance. The workflow always uploads Compose diagnostics and removes its named volumes.
