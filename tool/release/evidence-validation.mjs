import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { readFile, readdir, stat } from 'node:fs/promises';
import { basename, relative, resolve, sep } from 'node:path';

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

export const requiredJobSteps = Object.freeze({
  CI: Object.freeze({
    'dart-dependency-security': Object.freeze([
      'Scan Dart and Flutter workspace dependencies',
    ]),
    server: Object.freeze([
      'Generate OpenAPI-derived TypeScript, DTO, and Dart artifacts',
      'Validate OpenAPI and generated artifacts',
      'Verify generated artifacts have no diff',
      'Build server',
      'Test release evidence tooling',
      'Test server with line and branch coverage',
      'Enforce server line and branch coverage thresholds',
      'Audit npm dependencies',
      'Upload server CI evidence',
    ]),
    flutter: Object.freeze([
      'Regenerate Flutter localization artifacts',
      'Verify Flutter localization artifacts have no diff',
      'Analyze SDK, UI, and example',
      'Test SDK with line and branch coverage',
      'Enforce SDK line and branch coverage thresholds',
      'Test UI with line coverage',
      'Enforce UI line coverage threshold',
      'Test example',
      'Package publication checks',
      'Upload Flutter CI evidence',
    ]),
    'Golden tests (Ubuntu)': Object.freeze([
      'Validate the Golden baseline set',
      'Run UI tests including Golden comparisons',
      'Record successful Golden evidence',
      'Upload Golden CI evidence',
    ]),
    'compose-config': Object.freeze([
      'Validate secure default Compose profile',
      'Validate explicit development profile',
      'Validate explicit test profile',
      'Build server Compose image',
    ]),
  }),
  'Compose integration': Object.freeze({
    rate_limit: Object.freeze([
      'Initialize evidence timing',
      'Start isolated rate-limit stack',
      'Verify one shared IP quota across both API instances',
      'Capture structured result and diagnostics',
      'Upload rate-limit evidence',
    ]),
    core: Object.freeze([
      'Initialize evidence timing',
      'Start isolated two-instance stack',
      'Verify migration replay is idempotent',
      'Cross-instance core flow and duplicate-event idempotency',
      'Authentication, tenant isolation, rotation, expiry, and application disable',
      'Verify PostgreSQL persistence across API and database restarts',
      'Verify database tenant and owner constraints with invalid writes',
      'Verify retention continues for disabled applications',
      'Capture structured result and diagnostics',
      'Upload core evidence',
    ]),
    resilience: Object.freeze([
      'Initialize evidence timing',
      'Start isolated resilience stack',
      'Verify dependency readiness failure and recovery',
      'Verify rolling replacement through dynamically resolved nginx upstreams',
      'Verify liveness, readiness, and protected metrics',
      'Verify graceful shutdown and OpenTelemetry flush',
      'Verify presence expiry after SIGKILL',
      'Capture structured result and diagnostics',
      'Upload resilience evidence',
    ]),
    restore: Object.freeze([
      'Initialize evidence timing',
      'Start isolated restore stack',
      'Create data for logical backup',
      'Dump and restore into a fresh PostgreSQL database',
      'Recreate both APIs against the restored database',
      'Verify restored data through both APIs',
      'Capture structured result and diagnostics',
      'Upload restore evidence',
    ]),
    soak: Object.freeze([
      'Initialize evidence timing',
      'Start isolated soak stack',
      'Run ten-minute mixed HTTP/WebSocket soak with rolling replacements',
      'Capture structured result and diagnostics',
      'Upload soak evidence',
    ]),
  }),
  'Flutter platform builds': Object.freeze(Object.fromEntries(
    ['android', 'ios', 'web', 'windows', 'macos', 'linux'].map((platform) => [
      `Release build (${platform})`,
      Object.freeze([
        'Record release build start time',
        `Build ${platform} release artifact`,
        `Package ${platform} release artifact`,
        'Generate release evidence manifest',
        `Upload ${platform} release artifact`,
      ]),
    ]),
  )),
});

export const coverageEvidenceRequirements = Object.freeze({
  'server-coverage.json': Object.freeze({
    source: 'server/coverage/lcov.info',
    metrics: Object.freeze({ lines: 80, branches: 80 }),
  }),
  'sdk-coverage.json': Object.freeze({
    source: 'packages/study_room_sdk/coverage/lcov.info',
    metrics: Object.freeze({ lines: 80, branches: 80 }),
  }),
  'ui-coverage.json': Object.freeze({
    source: 'packages/study_room_ui/coverage/lcov.info',
    metrics: Object.freeze({ lines: 70 }),
  }),
});

function normalizedEvidenceText(value) {
  return `${value ?? ''}`.normalize('NFKC').trim().toLowerCase();
}

function normalizedVerifier(value) {
  const normalized = normalizedEvidenceText(value).replace(/^@+/, '');
  assert(/^[a-z0-9](?:[a-z0-9-]{0,37}[a-z0-9])?$/.test(normalized), 'RC verifier is not a valid normalized GitHub login');
  return normalized;
}

export function validateJobs(workflow, jobs, workflowRequirements) {
  const expected = workflowRequirements[workflow.name];
  assert(Array.isArray(expected), `No required-job declaration exists for ${workflow.name}`);
  const workflowStepRequirements = requiredJobSteps[workflow.name];
  assert(workflowStepRequirements, `No required-step declaration exists for ${workflow.name}`);
  const byName = new Map(jobs.map((job) => [job.name, job]));
  for (const name of expected) {
    const job = byName.get(name);
    assert(job, `${workflow.name} is missing job ${name}`);
    assert(job.status === 'completed' && job.conclusion === 'success', `${workflow.name}/${name} is not successful`);
    const failedStep = (job.steps ?? []).find((step) => step.conclusion !== 'success' && step.conclusion !== 'skipped');
    assert(!failedStep, `${workflow.name}/${name} step ${failedStep?.name} did not succeed`);
    const stepsByName = new Map((job.steps ?? []).map((step) => [step.name, step]));
    const requiredSteps = workflowStepRequirements[name];
    assert(Array.isArray(requiredSteps) && requiredSteps.length > 0, `${workflow.name}/${name} has no required-step declaration`);
    for (const stepName of requiredSteps) {
      const step = stepsByName.get(stepName);
      assert(step, `${workflow.name}/${name} is missing required step ${stepName}`);
      assert(
        step.status === 'completed' && step.conclusion === 'success',
        `${workflow.name}/${name} required step ${stepName} is not successful`,
      );
    }
  }
  return byName;
}

export function validateRcIssueIdentity({ issue, comments, sha, verifiedBy, capturedAtUtc }) {
  const normalizedVerifiedBy = normalizedVerifier(verifiedBy);
  const normalizedCapturedAtUtc = new Date(capturedAtUtc).toISOString();
  const issueText = [issue?.title, issue?.body, ...(comments ?? []).map((comment) => comment?.body)]
    .map((value) => `${value ?? ''}`)
    .join('\n');
  const normalizedIssueText = normalizedEvidenceText(issueText);
  const escapedVerifier = normalizedVerifiedBy.replaceAll(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const verifierField = new RegExp(`(?:^|\\n)\\s*verified by:\\s*@${escapedVerifier}\\s*(?:$|\\n)`, 'i');
  assert(issueText.toLowerCase().includes(sha.toLowerCase()), 'RC issue does not identify the frozen SHA');
  assert(verifierField.test(normalizedIssueText), 'RC issue does not contain the required Verified by: @login field');
  assert(normalizedIssueText.includes(normalizedCapturedAtUtc.toLowerCase()), 'RC issue does not identify the normalized capture time');
  return { issueText, normalizedVerifiedBy, normalizedCapturedAtUtc };
}

export function validateCoverageEvidenceFiles(files, { sha, runUrl }) {
  const expectedNames = Object.keys(coverageEvidenceRequirements).sort();
  const actualNames = files.map((file) => file.name).sort();
  assert(JSON.stringify(actualNames) === JSON.stringify(expectedNames), 'Coverage evidence filename set is incorrect');
  const accepted = {};
  for (const file of files) {
    const requirement = coverageEvidenceRequirements[file.name];
    const coverage = file.value;
    assert(coverage && typeof coverage === 'object' && !Array.isArray(coverage), `${file.name} is not a JSON object`);
    assert(coverage.schemaVersion === 1, `${file.name} schema is unsupported`);
    assert(coverage.passed === true, `${file.name} did not pass`);
    assert(coverage.commitSha === sha, `${file.name} belongs to another SHA`);
    assert(coverage.runUrl === runUrl, `${file.name} belongs to another CI run`);
    assert(coverage.source === requirement.source, `${file.name} has an unexpected LCOV source`);
    assert(Array.isArray(coverage.results), `${file.name} coverage results are missing`);
    const results = coverage.results;
    const resultLabels = results.map((result) => result.label);
    const expectedLabels = Object.keys(requirement.metrics);
    assert(new Set(resultLabels).size === resultLabels.length, `${file.name} contains duplicate coverage metrics`);
    assert(JSON.stringify(resultLabels) === JSON.stringify(expectedLabels), `${file.name} coverage metric set or order is incorrect`);
    for (const result of results) {
      const minimum = requirement.metrics[result.label];
      assert(result.minimum === minimum, `${file.name} ${result.label} threshold is not ${minimum}`);
      assert(result.passed === true, `${file.name} ${result.label} did not pass`);
      assert(Number.isSafeInteger(result.hits) && result.hits >= 0, `${file.name} ${result.label} hits are invalid`);
      assert(Number.isSafeInteger(result.found) && result.found > 0, `${file.name} ${result.label} found count is invalid`);
      assert(Number.isFinite(result.percent) && result.percent + Number.EPSILON >= minimum, `${file.name} ${result.label} is below threshold`);
      const computedPercent = result.hits / result.found * 100;
      assert(Math.abs(result.percent - computedPercent) < 1e-9, `${file.name} ${result.label} percent does not match hits/found`);
    }
    accepted[file.name] = coverage;
  }
  return accepted;
}

export function validateGoldenEvidence(golden, { sha, runUrl, scenarios }) {
  assert(golden?.schemaVersion === 1, 'Golden evidence schema is unsupported');
  assert(golden.commitSha === sha && golden.runGoldens === true, 'Golden evidence does not prove a real RC run');
  assert(golden.runUrl === runUrl, 'Golden evidence run URL does not match the selected CI run');
  assert(golden.scenarioCount === scenarios.length, `Golden evidence does not contain ${scenarios.length} scenarios`);
  assert(Array.isArray(golden.baselines), 'Golden evidence baselines are missing');
  assert(golden.baselines.length === scenarios.length, 'Golden evidence baseline count is incorrect');
  assert(JSON.stringify(golden.baselines.map((entry) => entry.name).sort()) === JSON.stringify([...scenarios].sort()), 'Golden scenario names do not match');
  const hashes = new Set();
  for (const baseline of golden.baselines) {
    assert(Number.isSafeInteger(baseline.sizeBytes) && baseline.sizeBytes > 0, `${baseline.name} Golden size is invalid`);
    assert(/^[a-f0-9]{64}$/.test(baseline.sha256), `${baseline.name} Golden SHA-256 is invalid`);
    assert(!hashes.has(baseline.sha256), `${baseline.name} reuses another Golden SHA-256`);
    hashes.add(baseline.sha256);
  }
  return golden;
}

async function filesUnder(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const path = resolve(directory, entry.name);
    if (entry.isDirectory()) files.push(...await filesUnder(path));
    else if (entry.isFile()) files.push(path);
  }
  return files;
}

export function validateComposeContainerSnapshot(images, composeRows, scenario) {
  const byService = new Map(composeRows.map((container) => [
    container.Service,
    container.ID ?? container.Id,
  ]));
  for (const service of ['api-1', 'api-2']) {
    const composeId = byService.get(service);
    assert(typeof composeId === 'string' && composeId.length > 0, `${scenario} Compose snapshot is missing ${service}`);
    assert(
      images.services?.[service]?.containerId === composeId,
      `${scenario} ${service} container ID does not match compose-ps.json`,
    );
  }
  return images;
}

export function validateComposeLog(contents, scenario) {
  assert(typeof contents === 'string' && contents.trim().length > 0, `${scenario} Compose log is empty`);
  const lines = contents.split(/\r?\n/).filter((line) => line.trim().length > 0);
  const timestamp = /\b\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z\b/;
  assert(lines.some((line) => timestamp.test(line)), `${scenario} Compose log does not contain Docker timestamps`);
  return { lineCount: lines.length };
}

function relativePath(directory, path) {
  return relative(directory, path).split(sep).join('/');
}

function safeArtifactPath(directory, path) {
  assert(typeof path === 'string' && path.length > 0, 'Platform manifest contains an empty path');
  const resolvedDirectory = resolve(directory);
  const resolvedPath = resolve(directory, path);
  assert(resolvedPath.startsWith(`${resolvedDirectory}${sep}`), `Platform path escapes its artifact: ${path}`);
  return resolvedPath;
}

export async function validatePlatformArtifact(directory, platform, sha, run) {
  const manifestMatches = (await filesUnder(directory))
    .filter((path) => basename(path) === `${platform}.json`);
  assert(manifestMatches.length === 1, `Expected exactly one ${platform}.json manifest`);
  const manifestPath = manifestMatches[0];
  const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
  assert(manifest.schemaVersion === 1, `${platform} manifest schema is unsupported`);
  assert(manifest.commitSha === sha, `${platform} manifest SHA does not match`);
  assert(manifest.platform === platform, `${platform} manifest platform does not match`);
  assert(manifest.runId === `${run.id}`, `${platform} manifest run ID does not match`);
  assert(manifest.runAttempt === `${run.run_attempt}`, `${platform} manifest run attempt does not match`);
  assert(manifest.runUrl === run.html_url, `${platform} manifest run URL does not match`);
  const startedAt = Date.parse(manifest.startedAtUtc);
  const endedAt = Date.parse(manifest.endedAtUtc);
  assert(Number.isFinite(startedAt) && Number.isFinite(endedAt) && endedAt >= startedAt, `${platform} manifest timing is invalid`);
  assert(Number.isFinite(manifest.durationSeconds) && manifest.durationSeconds >= 0, `${platform} manifest duration is invalid`);
  assert(typeof manifest.artifactRoot === 'string' && manifest.artifactRoot.length > 0, `${platform} artifact root is missing`);
  assert(Array.isArray(manifest.files) && manifest.files.length > 0, `${platform} manifest has no files`);
  assert(new Set(manifest.files.map((entry) => entry.path)).size === manifest.files.length, `${platform} manifest contains duplicate paths`);
  const expectedExtension = platform === 'android'
    ? '.apk'
    : platform === 'linux'
      ? '.tar.gz'
      : '.zip';
  const mainArtifacts = manifest.files.filter((entry) => entry.path.endsWith(expectedExtension));
  assert(mainArtifacts.length === 1, `${platform} must contain exactly one ${expectedExtension} main artifact`);
  assert(manifest.artifactRoot === mainArtifacts[0].path, `${platform} artifact root is not the main artifact path`);
  const manifestRelativePath = relativePath(directory, manifestPath);
  const actualFiles = (await filesUnder(directory))
    .map((path) => relativePath(directory, path))
    .filter((path) => path !== manifestRelativePath)
    .sort();
  const declaredFiles = manifest.files.map((entry) => entry.path).sort();
  assert(JSON.stringify(actualFiles) === JSON.stringify(declaredFiles), `${platform} artifact files do not exactly match its manifest`);
  let totalSizeBytes = 0;
  const verifiedFiles = [];
  for (const entry of manifest.files) {
    assert(/^[a-f0-9]{64}$/.test(entry.sha256), `${platform} manifest has an invalid SHA-256`);
    const path = safeArtifactPath(directory, entry.path);
    const metadata = await stat(path);
    assert(metadata.isFile(), `${platform} manifest entry is not a file: ${entry.path}`);
    const digest = await sha256File(path);
    assert(metadata.size === entry.sizeBytes, `${platform} size mismatch for ${entry.path}`);
    assert(digest === entry.sha256, `${platform} SHA-256 mismatch for ${entry.path}`);
    totalSizeBytes += metadata.size;
    verifiedFiles.push({ path: entry.path, sizeBytes: metadata.size, sha256: digest });
  }
  assert(totalSizeBytes === manifest.totalSizeBytes, `${platform} total size does not match`);
  return { manifest, verifiedFiles, manifestSha256: await sha256File(manifestPath) };
}

export async function sha256File(path) {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(path)) hash.update(chunk);
  return hash.digest('hex');
}

export function requiredArtifactDigest(artifact) {
  const label = artifact?.name ?? artifact?.id ?? 'unknown artifact';
  assert(
    typeof artifact?.digest === 'string'
      && /^sha256:[a-f0-9]{64}$/.test(artifact.digest),
    `Artifact ${label} is missing a valid SHA-256 digest`,
  );
  return artifact.digest.slice('sha256:'.length);
}

export async function verifyArtifactArchive(archivePath, artifact) {
  const expected = requiredArtifactDigest(artifact);
  const actual = await sha256File(archivePath);
  assert(actual === expected, `Artifact ${artifact.name} archive SHA-256 does not match GitHub`);
  return actual;
}

export function validateNpmAuditReport(report) {
  assert(report && typeof report === 'object' && !Array.isArray(report), 'npm audit evidence is not a JSON object');
  assert(Number.isSafeInteger(report.auditReportVersion), 'npm audit report version is missing');
  assert(report.metadata && typeof report.metadata === 'object', 'npm audit metadata is missing');
  const counts = report.metadata.vulnerabilities;
  assert(counts && typeof counts === 'object' && !Array.isArray(counts), 'npm audit vulnerability counts are missing');
  for (const severity of ['info', 'low', 'moderate', 'high', 'critical', 'total']) {
    assert(
      Number.isSafeInteger(counts[severity]) && counts[severity] >= 0,
      `npm audit ${severity} vulnerability count is invalid`,
    );
  }
  assert(counts.high === 0 && counts.critical === 0, 'npm audit reports high or critical vulnerabilities');
  assert(
    report.vulnerabilities && typeof report.vulnerabilities === 'object' && !Array.isArray(report.vulnerabilities),
    'npm audit vulnerability details are missing',
  );
  const blockingPackages = Object.entries(report.vulnerabilities)
    .filter(([, vulnerability]) => ['high', 'critical'].includes(vulnerability?.severity))
    .map(([name]) => name)
    .sort();
  assert(
    blockingPackages.length === 0,
    `npm audit contains high or critical package entries: ${blockingPackages.join(', ')}`,
  );
  return {
    auditReportVersion: report.auditReportVersion,
    vulnerabilities: {
      info: counts.info,
      low: counts.low,
      moderate: counts.moderate,
      high: counts.high,
      critical: counts.critical,
      total: counts.total,
    },
  };
}

export function validatePublishDryRunEvidence(evidence, { sha, run }) {
  assert(evidence && typeof evidence === 'object' && !Array.isArray(evidence), 'Publish dry-run evidence is not a JSON object');
  assert(evidence.schemaVersion === 1, 'Publish dry-run evidence schema is unsupported');
  assert(evidence.commitSha === sha, 'Publish dry-run evidence belongs to another SHA');
  assert(evidence.runUrl === run.html_url, 'Publish dry-run evidence belongs to another CI run');
  assert(evidence.runId === `${run.id}`, 'Publish dry-run evidence run ID does not match');
  assert(evidence.runAttempt === `${run.run_attempt}`, 'Publish dry-run evidence run attempt does not match');
  assert(evidence.passed === true, 'Publish dry-run evidence did not record passed=true');
  const expectedPackages = Object.freeze({
    study_room_sdk: 'sdk-publish-dry-run.log',
    study_room_ui: 'ui-publish-dry-run.log',
  });
  for (const [name, log] of Object.entries(expectedPackages)) {
    const result = evidence.packages?.[name];
    assert(result?.passed === true, `${name} publish dry-run did not pass`);
    assert(result.log === log, `${name} publish dry-run log path is incorrect`);
  }
  assert(
    Object.keys(evidence.packages ?? {}).sort().join(',') === Object.keys(expectedPackages).sort().join(','),
    'Publish dry-run evidence package set is incorrect',
  );
  return evidence;
}

export function checkRunIdFromJob(job) {
  const url = job?.check_run_url;
  assert(typeof url === 'string', `Actions job ${job?.name ?? 'unknown'} has no check_run_url`);
  const match = url.match(/\/check-runs\/(\d+)$/);
  assert(match, `Actions job ${job?.name ?? 'unknown'} has an invalid check_run_url`);
  const id = Number(match[1]);
  assert(Number.isSafeInteger(id) && id > 0, `Actions job ${job?.name ?? 'unknown'} has an invalid check-run ID`);
  return id;
}

export function validateRequiredCheckSources({ checksByName, workflowEvidence, workflowRequirements }) {
  const accepted = new Map();
  const checkRunIds = new Set();
  for (const workflow of workflowEvidence) {
    const expectedNames = workflowRequirements[workflow.workflow.name];
    assert(Array.isArray(expectedNames), `No required-check declaration exists for ${workflow.workflow.name}`);
    for (const name of expectedNames) {
      const job = workflow.jobsByName.get(name);
      assert(job, `${workflow.workflow.name} is missing job ${name}`);
      const check = checksByName.get(name);
      assert(check, `Required check ${name} is missing`);
      const expectedCheckRunId = checkRunIdFromJob(job);
      assert(
        check.id === expectedCheckRunId,
        `${name} check-run does not belong to selected ${workflow.workflow.name} run attempt`,
      );
      assert(job.run_id === workflow.workflow.id, `${workflow.workflow.name}/${name} belongs to another workflow run`);
      assert(
        job.run_attempt === workflow.workflow.run_attempt,
        `${workflow.workflow.name}/${name} belongs to another run attempt`,
      );
      assert(job.head_sha === workflow.workflow.head_sha, `${workflow.workflow.name}/${name} belongs to another SHA`);
      assert(!checkRunIds.has(check.id), `Required check-run ${check.id} is linked to more than one job`);
      checkRunIds.add(check.id);
      assert(!accepted.has(name), `Required check ${name} is linked to more than one workflow job`);
      accepted.set(name, {
        checkRunId: check.id,
        checkRunUrl: job.check_run_url,
        jobId: job.id,
        jobUrl: job.html_url,
        workflowName: workflow.workflow.name,
        workflowRunId: workflow.workflow.id,
        workflowRunAttempt: workflow.workflow.run_attempt,
      });
    }
  }
  const expected = Object.values(workflowRequirements).flat().sort();
  assert(JSON.stringify([...accepted.keys()].sort()) === JSON.stringify(expected), 'Required check source set is incomplete');
  return accepted;
}

export function requireMainRefSha(ref, expectedSha, phase) {
  const actual = ref?.object?.sha;
  assert(actual === expectedSha, `${phase} main is ${actual}, expected frozen RC ${expectedSha}`);
  return actual;
}

export function validateRepositoryMetadata(metadata, repository) {
  assert(metadata && typeof metadata === 'object' && !Array.isArray(metadata), 'Repository metadata is not a JSON object');
  assert(metadata.full_name === repository, `Repository metadata identifies ${metadata.full_name}, expected ${repository}`);
  assert(metadata.default_branch === 'main', `Repository default branch is ${metadata.default_branch}, expected main`);
  return metadata;
}

export function selectWorkflowRun(runs, name, path, sha) {
  const matches = runs.filter((run) =>
    run.name === name
    && run.path === path
    && run.event === 'push'
    && run.head_sha === sha
    && run.status === 'completed'
    && run.conclusion === 'success'
  ).sort((left, right) => right.run_attempt - left.run_attempt || right.id - left.id);
  assert(
    matches.length > 0,
    `No successful push run named ${name} at ${path} exists for ${sha}`,
  );
  return matches[0];
}
