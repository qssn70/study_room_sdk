# 0.4 release checklist

This project uses a lightweight release process intended for a solo maintainer.
There is no separate evidence archive, tracking issue, screenshot requirement,
repository Ruleset, or release-specific access token.

## Release candidate

A release candidate is ready when the candidate commit passes:

- the regular CI workflow, including contract drift checks, tests, coverage
  thresholds, dependency scans, package dry-runs, and Ubuntu Golden tests;
- the Compose integration workflow, including the dual-instance, security,
  persistence, retention, resilience, restore, and soak scenarios;
- the Flutter platform workflow for Android, iOS, Web, Windows, macOS, and
  Linux.

Diagnostic logs and build artifacts produced by those workflows are useful for
debugging, but they are not a separate release gate and do not need to be
copied into an issue or long-term evidence bundle.

## Final 0.4.0

1. Remove the prerelease suffix from the server, SDK, UI, example, and generated
   contract version fields.
2. Update the package changelogs and release notes.
3. Confirm that `study_room_sdk` and `study_room_ui` remain available on
   pub.dev if publication is planned.
4. Run CI, Compose integration, and all six platform builds for the final
   candidate.
5. Optionally create a `v0.4.0` Git tag and GitHub Release.

Actual pub.dev publication and production deployment are manual and are not
required by this repository's automated release process.
