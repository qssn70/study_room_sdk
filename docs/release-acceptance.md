# 0.4 RC release acceptance

The release candidate is accepted only when every gate below is green for the same commit. A rerun of the same commit is acceptable; results from different commit SHAs must not be combined. Record the full 40-character SHA before starting acceptance and verify that every Actions run reports that SHA as its `head_sha`.

## Required checks

Configure all 16 check contexts below as required for the protected release branch. Confirm the exact context strings exposed by GitHub before saving the rule; the expected workflow/job names are:

- `CI/dart-dependency-security`
- `CI/server`
- `CI/flutter`
- `CI/Golden tests (Ubuntu)`
- `CI/compose-config`
- `Compose integration/rate_limit`
- `Compose integration/core`
- `Compose integration/resilience`
- `Compose integration/restore`
- `Compose integration/soak`
- `Flutter platform builds/Release build (android)`
- `Flutter platform builds/Release build (ios)`
- `Flutter platform builds/Release build (web)`
- `Flutter platform builds/Release build (windows)`
- `Flutter platform builds/Release build (macos)`
- `Flutter platform builds/Release build (linux)`

Do not treat a skipped, neutral, cancelled, or still-running check as accepted. The Golden gate must run with `STUDY_ROOM_RUN_GOLDENS=true`; a green job that skipped the eight comparisons is invalid evidence.

## Evidence record

Create one RC record containing all of the following:

| Field | Required evidence |
| --- | --- |
| RC commit | Full commit SHA and candidate tag or branch name. |
| CI | Actions run URL, run ID/attempt, completion time, and confirmation that the five required CI checks succeeded. |
| Compose integration | Actions run URL plus the `compose-rate-limit-*`, `compose-core-*`, `compose-resilience-*`, `compose-restore-*`, and `compose-soak-*` evidence artifact names. |
| Container identity | For each Compose job, record the immutable `sha256:` image ID or registry digest used by `api-1` and `api-2`; the two instances within a job must use the same image. Prefer an OCI `RepoDigest`, falling back to Docker `.Image`/`.Id` when the CI image is not pushed. |
| Golden | CI run URL, the log showing all eight scenarios executed, and the commit containing the expected PNG baselines. A `golden-failure-*` artifact must be retained when the check fails. |
| Six platforms | Platform-build run URL and the six artifact names `study-room-<platform>-<commit SHA>`. |
| Branch protection | Repository settings screenshot and API JSON showing the target branch/ruleset and every required context listed above. |

Each platform artifact must contain `artifacts/manifests/<platform>.json`. Verify that every manifest contains:

- the same RC `commitSha`;
- the expected `platform` and Actions `runUrl`;
- UTC start/end timestamps and a non-negative duration;
- the artifact root and total byte size;
- a non-empty file list with relative path, byte size, and lowercase SHA-256 for every uploaded build file.

The uploaded primary deliverable is a packaged artifact rather than a raw native directory: Linux uses `tar.gz` to preserve executable modes and links, macOS/iOS use `ditto` ZIP archives to preserve app-bundle metadata, Windows/Web use ZIP, and Android remains an APK. The manifest SHA-256 must therefore be checked against that packaged deliverable.

Recompute at least the primary deliverable hash after downloading each artifact and compare it with the manifest. For directory bundles, verify all manifest entries or use an automated manifest verifier. Record the artifact name and manifest SHA-256 in the RC record.

For Compose evidence, inspect each `result.json`, timestamped Compose log, and `compose-ps.json`; an uploaded artifact alone is not proof of success. The record must identify the successful step outcomes and image identity. Restore evidence must include dump size/SHA-256 and restored entity IDs. Soak evidence must include duration, request/event counts, rolling-replacement timing, reconnect count, and no unexpected failure.

## Capturing Actions and branch-protection evidence

In the GitHub UI:

1. Open the commit or pull request Checks view and copy the URL of each workflow run.
2. Confirm the displayed commit SHA, conclusion, run attempt, and artifact names.
3. Open repository **Settings → Rules → Rulesets** or **Settings → Branches**, select the rule that targets the release branch, and capture a screenshot showing the repository, branch target, enforcement state, and complete required-check list.
4. Store the screenshot with the RC record; include the capture time and the account that verified it.

For API evidence, save the unmodified JSON responses for the RC SHA and branch rule:

- `GET /repos/{owner}/{repo}/commits/{sha}/check-runs` — verify every required check has `status=completed`, `conclusion=success`, and the expected `details_url`.
- `GET /repos/{owner}/{repo}/actions/runs?head_sha={sha}` — record workflow run IDs, attempts, URLs, timestamps, and `head_sha`.
- `GET /repos/{owner}/{repo}/branches/{branch}/protection/required_status_checks` for classic branch protection, or `GET /repos/{owner}/{repo}/rulesets` plus the selected ruleset detail endpoint when rulesets are used.

The API token must have read access to Actions and repository administration metadata. Redact credentials, but do not edit check names, conclusions, SHAs, URLs, timestamps, or rule contents in the saved evidence.

## Completion rule and current local limitation

P2 is complete only after the real Docker dual-instance scenarios and all GitHub Actions checks above have run successfully for one SHA, their evidence has been reviewed, and branch-protection configuration has been independently captured. This document does not assert that branch protection has already been configured.

On the current local machine the Docker daemon is unavailable and `gh` is not installed. Static YAML checks, `docker compose config`, local unit tests, and generated-file checks may prepare the release, but they must not be used to mark P2 complete. Final acceptance must occur on a working Docker host and GitHub-hosted or equivalent six-platform runners with repository access.
