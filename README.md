# Study Room SDK

Flutter SDK, optional Flutter widgets, and a NestJS reference backend for adding online study rooms to another app.

## Packages

- `packages/study_room_sdk`: core Flutter SDK for auth, REST, realtime streams, room state, study sessions, and chat.
- `packages/study_room_ui`: optional Flutter widgets built on the SDK domain models.
- `apps/example_flutter`: minimal integration example.
- `server`: NestJS reference backend with REST and Socket.IO realtime endpoints.

## Quick Start

```sh
docker compose up --build
cd packages/study_room_sdk && dart test
cd ../study_room_ui && flutter test
cd ../../server && npm test
```

The reference API listens on `http://localhost:3000`. OpenAPI docs are served from `/docs/openapi`.

## License Layout

- Flutter SDK and UI packages are intended for Apache-2.0 distribution.
- The reference backend in `server/` follows the repository GPL-3.0 license.
- Commercial/private backend licensing can be handled separately.

See `docs/getting-started.md` for integration details.

