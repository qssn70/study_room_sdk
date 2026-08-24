# 0.4.1 release checklist

This project uses a lightweight release process intended for a solo maintainer.
There is no separate evidence archive, tracking issue, screenshot requirement,
repository Ruleset, or release-specific access token.

## Release candidate

A release candidate is ready when the candidate commit passes:

- the regular CI workflow, including contract drift checks, tests, coverage
  thresholds, dependency scans, package dry-runs, and Ubuntu Golden tests;
- the Compose integration workflow, including the dual-instance, security,
  persistence, retention, real Dart SDK, real Chrome CORS/Socket.IO,
  resilience, restore, and soak scenarios;
- the Example smoke builds workflow for Android, iOS, Web, Windows, macOS, and
  Linux, with unsigned outputs retained only as Actions artifacts.

Diagnostic logs and build artifacts produced by those workflows are useful for
debugging, but they are not a separate release gate and do not need to be
copied into an issue or long-term evidence bundle.

## `v0.4.*` candidate tag

1. Confirm the tag exactly matches the root package, server, SDK, UI, both
   examples, OpenAPI contract, and generated contract versions.
2. Confirm generated sources have no drift and realtime `schemaVersion` remains
   `1`.
3. Require CI, full Compose integration, Golden comparisons, and all six
   example smoke builds to pass.
4. Require a non-empty server OCI archive, SPDX JSON SBOM, version manifest,
   and verified SHA-256 checksum file.
5. Let automation create a draft GitHub Release with only those server
   candidate artifacts.

Actual pub.dev publication, server image push, promotion of the draft Release,
and production deployment are manual and are not required by this repository's
automated release process.
