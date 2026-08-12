# 0.4 release train

No CI job publishes packages or server images. Promotion is manual and uses the same commit after every gate is green.

## `0.4.0-alpha.1`

Contract freeze candidate: OpenAPI/event generation, Prisma migration, application/admin JWKS, tenant auth, strict validation, and core service unit coverage.

## `0.4.0-beta.1`

Integration candidate: owner approval workflow, session/chat persistence, Redis adapter/presence, expiry and eviction behavior, Flutter SDK lifecycle, and the two-instance Compose E2E must pass.

## `0.4.0-rc.1`

Release candidate: localization/accessibility review, six-platform build matrix, operations endpoints, retention cleanup, package dry-runs, dependency audit, migration guide, and a clean staging soak.

The RC is accepted only through the SHA-locked `RC evidence` workflow after all 16 required checks pass on the same `main` commit and the active `main-release-gates` Ruleset has been captured through both API JSON and UI screenshots.

## `0.4.0`

Before publishing, check that `study_room_sdk` and `study_room_ui` are still available on pub.dev, remove prerelease suffixes, rerun every CI workflow from a clean tag candidate, and obtain package ownership approval. Blue/green the 0.4 backend separately from 0.3; never mix protocol versions behind one load balancer.
