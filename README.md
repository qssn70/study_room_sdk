# Study Room SDK 0.4

Production-oriented online study rooms for Flutter: a stable Dart SDK, reusable Flutter UI, and a NestJS reference backend backed by PostgreSQL and Redis.

The current stable release is `0.4.1`. It is backward compatible with 0.4.0 and keeps REST under `/v1` and the Socket.IO namespace at `/v1/realtime`.

## Workspace

- `packages/study_room_sdk`: HTTP/realtime client, immutable models, structured errors, lifecycle management, and the compatible local focus data layer.
- `packages/study_room_ui`: room lobby, application status, owner approval inbox, member/ownership controls, and the local focus experience.
- `apps/example_flutter`: reference owner/member application for all six Flutter platforms.
- `server`: NestJS API with Prisma/PostgreSQL, Redis presence and multi-instance Socket.IO, per-application JWKS, operations endpoints, and retention jobs.
- `contracts`: authoritative OpenAPI 3.1 and realtime JSON Schema contracts.

## Local stack

The default Compose profile starts PostgreSQL, Redis, migrations, two API instances, and nginx. It never starts the development JWKS fixture, seed, or E2E runner. PostgreSQL and Redis are not published to the host.

```sh
cp .env.dev.example .env.dev
# Replace POSTGRES_PASSWORD and E2E_FIXTURE_CONTROL_TOKEN in .env.dev.
docker compose --env-file .env.dev --profile dev up --build
```

The explicit `dev` profile adds the ephemeral JWKS fixture and demo application seed. Production-style deployments instead copy `.env.example`, configure an external HTTPS administrator JWKS, and run without a profile.

Create a short-lived demo token:

```sh
curl -X POST http://localhost:4000/token \
  -H "content-type: application/json" \
  -d '{"sub":"owner-1","displayName":"Owner"}'
```

The API is served at `http://localhost:3000`, health endpoints at `/health/live` and `/health/ready`, and the OpenAPI viewer at `/docs/openapi`.

## Flutter

```dart
final sdk = StudyRoomSdk(
  StudyRoomSdkConfig(
    apiBaseUri: Uri.parse('https://study.example.com'),
    realtimeUri: Uri.parse('wss://study.example.com/v1/realtime'),
    tokenProvider: (request) async => StudyRoomAccessToken(
      token: await tokenService.issueToken(forceRefresh: request.forceRefresh),
      expiresAt: await tokenService.expiresAt(),
    ),
  ),
);

await sdk.start();
final room = await sdk.rooms.create(
  'Exam preparation',
  idempotencyKey: retryKey,
);
await sdk.rooms.subscribe(room.id);
await sdk.chat.send(room.id, 'Hello', idempotencyKey: messageRetryKey);
await sdk.close();
```

Configure UI localization on the host `MaterialApp`:

```dart
MaterialApp(
  localizationsDelegates: StudyRoomLocalizations.localizationsDelegates,
  supportedLocales: StudyRoomLocalizations.supportedLocales,
  home: StudyRoomLobbyView(sdk: sdk, currentUserId: userId),
)
```

The focus UI defaults to a bundled offline gradient and performs no background network request.

## Verification

```sh
npm ci
npm run check:contracts
npm run check:release-versions -- 0.4.1
npm run build
npm test
npm run analyze:all
dart test packages/study_room_sdk
flutter test packages/study_room_ui
npm run doc:check
```

See [getting started](docs/getting-started.md), [backup and idempotency](docs/data-backup-and-idempotency.md), [deployment](docs/deployment.md), [realtime events](docs/realtime-events.md), and the [0.3 migration guide](docs/migration-0.3-to-0.4.md).

The Flutter packages use Apache-2.0. The reference server and repository-level code use GPL-3.0-only. This project does not publish packages as part of its CI.
