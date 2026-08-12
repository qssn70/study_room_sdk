# 0.4 RC release acceptance

The release candidate is accepted only when every gate below is green for the same commit. A rerun of the same commit is acceptable; results from different commit SHAs must not be combined. Record the full 40-character SHA before starting acceptance and verify that every Actions run reports that SHA as its `head_sha`.

## Required checks

Configure all 16 check contexts below as required for the protected release branch. GitHub's UI may display a workflow/job pair, but the Ruleset API stores the bare check-run `name`. Do not configure slash-prefixed names such as `CI/server`; those contexts are never emitted.

| Workflow | Required Ruleset context |
| --- | --- |
| CI | `dart-dependency-security` |
| CI | `server` |
| CI | `flutter` |
| CI | `Golden tests (Ubuntu)` |
| CI | `compose-config` |
| Compose integration | `rate_limit` |
| Compose integration | `core` |
| Compose integration | `resilience` |
| Compose integration | `restore` |
| Compose integration | `soak` |
| Flutter platform builds | `Release build (android)` |
| Flutter platform builds | `Release build (ios)` |
| Flutter platform builds | `Release build (web)` |
| Flutter platform builds | `Release build (windows)` |
| Flutter platform builds | `Release build (macos)` |
| Flutter platform builds | `Release build (linux)` |

Bind every context to the GitHub Actions integration rather than accepting any source. The active `main-release-gates` repository Ruleset must target `~DEFAULT_BRANCH`, require a current branch, have no bypass actors, and prohibit deletion and non-fast-forward updates. `node tool/configure-main-ruleset.mjs --repository owner/repo` performs a read-only dry run; add `--apply` only with a `GITHUB_TOKEN` that has repository Administration write access.

Do not treat a skipped, neutral, cancelled, or still-running check as accepted. The Golden gate must run with `STUDY_ROOM_RUN_GOLDENS=true`; a green job that skipped the eight comparisons is invalid evidence.

## Evidence record

Create one RC record containing all of the following:

| Field | Required evidence |
| --- | --- |
| RC commit | Full commit SHA and candidate tag or branch name. |
| CI | Actions run URL, run ID/attempt, completion time, structured server/SDK/UI coverage, structured success plus logs for both package dry-runs, Golden evidence, and confirmation that the five required CI checks succeeded. |
| Compose integration | Actions run URL plus the `compose-rate-limit-*`, `compose-core-*`, `compose-resilience-*`, `compose-restore-*`, and `compose-soak-*` evidence artifact names. |
| Container identity | For each Compose job, record the immutable `sha256:` image ID or registry digest used by `api-1` and `api-2`; the two instances within a job must use the same image. Prefer an OCI `RepoDigest`, falling back to Docker `.Image`/`.Id` when the CI image is not pushed. |
| Golden | CI run URL, the log showing all eight scenarios executed, and the commit containing the expected PNG baselines. A `golden-failure-*` artifact must be retained when the check fails. |
| Six platforms | Platform-build run URL and the six artifact names `study-room-<platform>-<commit SHA>`. |
| Branch protection | Repository settings screenshots and unmodified API JSON showing the active `main-release-gates` Ruleset, default-branch target, GitHub Actions source binding, and every required context listed above. |

Each platform artifact must contain `artifacts/manifests/<platform>.json`. Verify that every manifest contains:

- the same RC `commitSha`;
- the expected `platform` and Actions `runUrl`;
- UTC start/end timestamps and a non-negative duration;
- the artifact root and total byte size;
- a non-empty file list with relative path, byte size, and lowercase SHA-256 for every uploaded build file.

The uploaded primary deliverable is a packaged artifact rather than a raw native directory: Linux uses `tar.gz` to preserve executable modes and links, macOS/iOS use `ditto` ZIP archives to preserve app-bundle metadata, Windows/Web use ZIP, and Android remains an APK. The manifest SHA-256 must therefore be checked against that packaged deliverable.

Recompute at least the primary deliverable hash after downloading each artifact and compare it with the manifest. For directory bundles, verify all manifest entries or use an automated manifest verifier. Record the artifact name and manifest SHA-256 in the RC record.

For Compose evidence, inspect each `result.json`, timestamped Compose log, and `compose-ps.json`; an uploaded artifact alone is not proof of success. The record must identify the successful step outcomes and image identity. Restore evidence must include dump size/SHA-256 and restored entity IDs. Soak evidence must include duration, request/event counts, rolling-replacement timing, reconnect count, and no unexpected failure.

Each Compose artifact also contains `service-images.json`. Both `api-1` and `api-2` must have the same immutable `sha256:` image ID; record any available RepoDigest as additional evidence. Core evidence must include real PostgreSQL persistence and concurrency results. Resilience evidence must include Presence TTL measurements, OpenTelemetry export, and graceful SIGTERM shutdown.

## Automated RC record

Create an RC tracking issue that names the full candidate SHA. Attach enough Ruleset settings screenshots to show the repository, active enforcement, default-branch target, source binding, and all 16 contexts. Record the verifier on its own line using the exact field `Verified by: @github-login`, and record the UTC capture time in normalized ISO-8601 form such as `2026-08-12T01:02:03.000Z`. Ordinary mentions of the same login elsewhere in the issue do not satisfy the verifier field.

Configure the Actions secret `RC_EVIDENCE_TOKEN` with repository Contents, Actions, Checks, Issues, and Administration read access. The workflow deliberately does not use the default `GITHUB_TOKEN` for collection because it cannot reliably read repository Rulesets. The workflow's scoped default token has `actions: write`, `issues: write`, `checks: read`, and `contents: read` so it can publish the final issue record, inspect the checked-out run, and delete an unfinalized artifact if finalization fails.

Dispatch the manual `RC evidence` workflow from `main` while `main` still equals the frozen `rc_sha`, and provide the issue number, screenshot attachment URLs as a JSON array, verifier, and capture time. The workflow rejects any other dispatch ref or workflow SHA, checks out the explicit SHA, refuses to use a newer `main`, and selects only successful push runs for that SHA. It downloads all three selected runs and their artifacts, recomputes platform hashes, and validates every embedded SHA. A successful run uploads `rc-evidence-<full SHA>` for 90 days and comments its artifact URL, ID, and SHA-256 on the tracking issue. On a collection, upload, output-validation, or issue-record failure, the workflow attempts to publish a short-lived `rc-evidence-failure-*` diagnostic artifact; it is never an accepted record. If the accepted upload already occurred, the workflow retries deletion and records the rollback outcome. Even if GitHub prevents deletion, an artifact from a failed workflow run is unaccepted and must not be promoted: acceptance requires both the exact artifact name and a successful `RC evidence` workflow conclusion.

The collector also binds every required check-run ID to the matching job returned by the selected workflow run and run attempt. It rejects a same-SHA check from another rerun, and preserves the raw check-runs and per-workflow jobs API responses plus the derived `required-check-sources.json` mapping.

The accepted artifact contains `rc.json`, `rc.md`, `SHA256SUMS`, raw GitHub API responses, Ruleset screenshots, CI evidence, Compose results and logs, service image identities, and the six platform manifests and verified deliverable hashes. It intentionally omits the large platform binaries after hashing them.

## Capturing Actions and branch-protection evidence

In the GitHub UI:

1. Open the commit or pull request Checks view and copy the URL of each workflow run.
2. Confirm the displayed commit SHA, conclusion, run attempt, and artifact names.
3. Open repository **Settings → Rules → Rulesets → main-release-gates** and capture screenshots showing the repository, default-branch target, active enforcement, source binding, and complete required-check list.
4. Attach the screenshots to the SHA-specific RC tracking issue; the evidence workflow downloads and hashes the original attachments.

For API evidence, save the unmodified JSON responses for the RC SHA and branch rule:

- `GET /repos/{owner}/{repo}/commits/{sha}/check-runs` — verify every required check has `status=completed`, `conclusion=success`, and the expected `details_url`.
- `GET /repos/{owner}/{repo}/actions/runs?head_sha={sha}` — record workflow run IDs, attempts, URLs, timestamps, and `head_sha`.
- `GET /repos/{owner}/{repo}/branches/{branch}/protection/required_status_checks` for classic branch protection, or `GET /repos/{owner}/{repo}/rulesets` plus the selected ruleset detail endpoint when rulesets are used.

The API token must have read access to Actions and repository administration metadata. Redact credentials, but do not edit check names, conclusions, SHAs, URLs, timestamps, or rule contents in the saved evidence.

## Completion rule and local evidence limitation

P2 is complete only after the real Docker dual-instance scenarios and all GitHub Actions checks above have run successfully for one SHA, their evidence has been reviewed, and branch-protection configuration has been independently captured. This document does not assert that branch protection has already been configured.

Local Docker Compose rehearsals can validate the implementation before the candidate SHA is frozen, but evidence from a dirty worktree, an uncommitted tree, or a different SHA must not be used to mark P2 complete. Final acceptance requires the three successful GitHub workflows, five Compose artifacts, six platform artifacts, and Ruleset evidence from the same frozen SHA. If any fix changes the candidate SHA, discard the prior RC artifact and repeat every gate.
