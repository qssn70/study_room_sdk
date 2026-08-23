# 0.4 release train

No CI job publishes packages or server images. Promotion is manual after the relevant CI, Compose integration, and platform-build workflows are green.

## `0.4.0-alpha.1`

Contract freeze candidate: OpenAPI/event generation, Prisma migration, application/admin JWKS, tenant auth, strict validation, and core service unit coverage.

## `0.4.0-beta.1`

Integration candidate: owner approval workflow, session/chat persistence, Redis adapter/presence, expiry and eviction behavior, Flutter SDK lifecycle, and the two-instance Compose E2E must pass.

## `0.4.0-rc.1`

Release candidate: localization/accessibility review, six-platform build matrix, operations endpoints, retention cleanup, package dry-runs, dependency audit, migration guide, and a clean staging soak.

The RC is ready when CI, Compose integration, and all six platform builds pass for the candidate commit. No tracking issue, screenshot archive, Ruleset, or separate evidence workflow is required.

## `0.4.0`

Before publishing, check that `study_room_sdk` and `study_room_ui` are still available on pub.dev, remove prerelease suffixes, and rerun CI, Compose integration, and the six-platform build from the final candidate. Actual pub.dev publication is outside this repository's automated workflow. Blue/green the 0.4 backend separately from 0.3; never mix protocol versions behind one load balancer.
