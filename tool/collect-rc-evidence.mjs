#!/usr/bin/env node
import {
  cp,
  mkdir,
  readFile,
  readdir,
  rename,
  rm,
  stat,
  writeFile,
} from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { basename, dirname, join, relative, resolve, sep } from 'node:path';

import { GitHubApi, writeJson } from './release/github-api.mjs';
import {
  validateCoverageEvidenceFiles,
  validateComposeContainerSnapshot,
  validateComposeLog,
  validateGoldenEvidence,
  validateJobs,
  validatePlatformArtifact,
  validateRcIssueIdentity,
  validateRepositoryMetadata,
  selectWorkflowRun,
  validateRequiredCheckSources,
  requireMainRefSha,
  requiredArtifactDigest,
  sha256File,
  validateNpmAuditReport,
  validatePublishDryRunEvidence,
  verifyArtifactArchive,
} from './release/evidence-validation.mjs';
import {
  composeScenarios,
  goldenScenarios,
  platforms,
  requiredChecks,
  workflowRequirements,
  workflowPaths,
} from './release/required-checks.mjs';
import { rulesetName, validateRuleset } from './release/ruleset.mjs';

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function safeName(value) {
  return value.toLowerCase().replaceAll(/[^a-z0-9]+/g, '-').replaceAll(/^-|-$/g, '');
}

async function filesUnder(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) files.push(...await filesUnder(path));
    else if (entry.isFile()) files.push(path);
  }
  return files;
}

async function findFile(directory, name) {
  const matches = (await filesUnder(directory)).filter((path) => basename(path) === name);
  assert(matches.length === 1, `Expected exactly one ${name} in ${directory}, found ${matches.length}`);
  return matches[0];
}

function unzip(archive, destination) {
  const listing = spawnSync('unzip', ['-Z1', archive], { encoding: 'utf8' });
  assert(listing.status === 0, `Unable to inspect ${archive}: ${listing.stderr}`);
  for (const path of listing.stdout.split(/\r?\n/).filter(Boolean)) {
    const normalized = path.replaceAll('\\', '/');
    assert(
      !normalized.startsWith('/') && !normalized.split('/').includes('..'),
      `Unsafe artifact entry: ${path}`,
    );
  }
  const extracted = spawnSync('unzip', ['-q', archive, '-d', destination], { encoding: 'utf8' });
  assert(extracted.status === 0, `Unable to extract ${archive}: ${extracted.stderr}`);
}

function artifactByName(artifacts, name) {
  const matches = artifacts
    .filter((artifact) => artifact.name === name && artifact.expired === false)
    .sort((left, right) => right.id - left.id);
  assert(matches.length > 0, `Expected a non-expired artifact ${name}`);
  const artifact = matches[0];
  assert(typeof artifact.archive_download_url === 'string', `Artifact ${name} has no download URL`);
  requiredArtifactDigest(artifact);
  return artifact;
}

async function downloadAndExtract(api, artifact, workDirectory) {
  const archive = join(workDirectory, 'archives', `${artifact.id}.zip`);
  const destination = join(workDirectory, 'expanded', `${artifact.id}`);
  await api.download(artifact.archive_download_url, archive);
  const archiveSha256 = await verifyArtifactArchive(archive, artifact);
  await mkdir(destination, { recursive: true });
  unzip(archive, destination);
  return { archiveSha256, directory: destination };
}

function relativePath(directory, path) {
  return relative(directory, path).split(sep).join('/');
}

function safeArtifactPath(directory, path) {
  assert(typeof path === 'string' && path.length > 0, 'Evidence manifest contains an empty path');
  const resolvedDirectory = resolve(directory);
  const resolvedPath = resolve(directory, path);
  assert(resolvedPath.startsWith(`${resolvedDirectory}${sep}`), `Evidence path escapes its artifact: ${path}`);
  return resolvedPath;
}

async function validateEvidenceManifest(directory, manifestPath, requirement, sha, workflow, job) {
  assert(job, `${requirement.job} job metadata is missing`);
  const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
  assert(manifest.schemaVersion === 1, `${requirement.job} evidence manifest schema is unsupported`);
  assert(manifest.commitSha === sha, `${requirement.job} evidence manifest SHA does not match`);
  assert(manifest.scenario === requirement.scenario, `${requirement.job} evidence manifest scenario does not match`);
  assert(manifest.runUrl === workflow.html_url, `${requirement.job} evidence run URL does not match`);
  assert(manifest.runIdentity?.runId === `${workflow.id}`, `${requirement.job} evidence run ID does not match`);
  assert(manifest.runIdentity?.runAttempt === `${workflow.run_attempt}`, `${requirement.job} evidence run attempt does not match`);
  assert(manifest.runIdentity?.workflow === workflow.name, `${requirement.job} evidence workflow name does not match`);
  assert(manifest.runIdentity?.job === requirement.job, `${requirement.job} evidence job name does not match`);
  const startedAt = Date.parse(manifest.timing?.startedAt);
  const endedAt = Date.parse(manifest.timing?.endedAt);
  assert(Number.isFinite(startedAt) && Number.isFinite(endedAt) && endedAt >= startedAt, `${requirement.job} evidence timing is invalid`);
  assert(Number.isSafeInteger(manifest.timing?.durationSeconds) && manifest.timing.durationSeconds >= 0, `${requirement.job} evidence duration is invalid`);
  assert(Array.isArray(manifest.artifacts) && manifest.artifacts.length > 0, `${requirement.job} evidence manifest is empty`);
  const declared = [];
  for (const entry of manifest.artifacts) {
    assert(/^[a-f0-9]{64}$/.test(entry.sha256), `${requirement.job} has an invalid manifest SHA-256`);
    const path = safeArtifactPath(directory, entry.path);
    const metadata = await stat(path);
    assert(metadata.isFile(), `${requirement.job} manifest entry is not a file: ${entry.path}`);
    assert(metadata.size === entry.sizeBytes, `${requirement.job} manifest size differs for ${entry.path}`);
    assert(await sha256File(path) === entry.sha256, `${requirement.job} manifest hash differs for ${entry.path}`);
    declared.push(entry.path);
  }
  assert(new Set(declared).size === declared.length, `${requirement.job} evidence manifest contains duplicate paths`);
  const actual = (await filesUnder(directory))
    .filter((path) => resolve(path) !== resolve(manifestPath))
    .map((path) => relativePath(directory, path))
    .sort();
  assert(JSON.stringify([...declared].sort()) === JSON.stringify(actual), `${requirement.job} evidence manifest does not cover the complete artifact`);
  return manifest;
}

async function readRequiredJson(directory, name, label) {
  const path = await findFile(directory, name);
  const value = JSON.parse(await readFile(path, 'utf8'));
  assert(value && typeof value === 'object' && !Array.isArray(value), `${label} is not a JSON object`);
  return { path, value };
}

async function requirePassedJson(directory, name, label) {
  const evidence = await readRequiredJson(directory, name, label);
  assert(evidence.value.passed === true, `${label} did not record passed=true`);
  return evidence.value;
}

async function validateComposeArtifact(directory, requirement, sha, workflow, job) {
  const resultPath = await findFile(directory, 'result.json');
  const manifestPath = await findFile(directory, 'evidence-manifest.json');
  const imagesPath = await findFile(directory, 'service-images.json');
  const composePsPath = await findFile(directory, 'compose-ps.json');
  const composeLogPath = await findFile(directory, 'compose.log');
  const result = JSON.parse(await readFile(resultPath, 'utf8'));
  const manifest = await validateEvidenceManifest(
    directory,
    manifestPath,
    requirement,
    sha,
    workflow,
    job,
  );
  const images = JSON.parse(await readFile(imagesPath, 'utf8'));
  validateComposeLog(await readFile(composeLogPath, 'utf8'), requirement.job);
  const composePsLines = (await readFile(composePsPath, 'utf8')).split(/\r?\n/).filter(Boolean);
  const composePs = composePsLines.flatMap((line) => {
    const value = JSON.parse(line);
    return Array.isArray(value) ? value : [value];
  });
  assert(result.scenario === requirement.scenario, `${requirement.job} result scenario is incorrect`);
  assert(Object.keys(result.steps ?? {}).length > 0, `${requirement.job} has no recorded steps`);
  assert(Object.values(result.steps).every((value) => value === 'success'), `${requirement.job} has an unsuccessful step`);
  assert(images.schemaVersion === 1, `${requirement.job} service image schema is unsupported`);
  assert(images.assertions?.apiImagesPresent === true && images.assertions?.apiImageIdsMatch === true, `${requirement.job} service image assertions failed`);
  const api1 = images.services?.['api-1'];
  const api2 = images.services?.['api-2'];
  assert(api1?.imageId?.startsWith('sha256:'), `${requirement.job} api-1 image ID is missing`);
  assert(api2?.imageId === api1.imageId, `${requirement.job} API instances use different images`);
  assert(typeof api1.containerId === 'string' && api1.containerId.length > 0, `${requirement.job} api-1 container ID is missing`);
  assert(typeof api2.containerId === 'string' && api2.containerId.length > 0, `${requirement.job} api-2 container ID is missing`);
  validateComposeContainerSnapshot(images, composePs, requirement.job);
  for (const digest of [...(api1.repoDigests ?? []), ...(api2.repoDigests ?? [])]) {
    assert(/@sha256:[a-f0-9]{64}$/.test(digest), `${requirement.job} has an invalid repository digest`);
  }
  const passedEvidence = {};
  if (requirement.job === 'rate_limit') {
    passedEvidence.rateLimit = await requirePassedJson(directory, 'rate-limit.json', 'rate-limit evidence');
    assert(passedEvidence.rateLimit.sharedAcrossInstances === true, 'rate-limit evidence is not cross-instance');
    assert(passedEvidence.rateLimit.rejectedStatus === 429, 'rate-limit evidence did not reject request 121');
  } else if (requirement.job === 'core') {
    for (const name of ['core-flow.json', 'security.json', 'persistence.json', 'database-integrity.json', 'retention.json']) {
      passedEvidence[name] = await requirePassedJson(directory, name, `core ${name}`);
    }
    assert(passedEvidence['security.json'].tenantIsolation?.websocketEventLeak === false, 'core security evidence reports a WebSocket leak');
    assert(passedEvidence['core-flow.json'].lifecycle?.includes('deleted'), 'core lifecycle did not reach room deletion');
  } else if (requirement.job === 'resilience') {
    for (const name of ['rolling-probe.json', 'operations.json', 'graceful-proxy.json', 'graceful-api-2.json', 'otel.json', 'presence-crash.json']) {
      passedEvidence[name] = await requirePassedJson(directory, name, `resilience ${name}`);
    }
    const graceful = (await readRequiredJson(directory, 'graceful-shutdown.json', 'graceful shutdown evidence')).value;
    assert(graceful.state?.exitCode === 0 && graceful.state?.oomKilled === false && graceful.state?.error === '', 'graceful shutdown was not clean');
    assert(passedEvidence['graceful-proxy.json'].failures?.length === 0, 'graceful shutdown proxy probe had failures');
    assert(passedEvidence['graceful-api-2.json'].failures?.length === 0, 'api-2 was not continuously ready during graceful shutdown');
    assert(passedEvidence['otel.json'].instanceSpanCounts?.['api-1'] > 0 && passedEvidence['otel.json'].instanceSpanCounts?.['api-2'] > 0, 'OpenTelemetry evidence is missing an API instance');
    assert(passedEvidence['presence-crash.json'].expiredTtl?.indexTtlSeconds === -2, 'Presence index did not expire after SIGKILL');
  } else if (requirement.job === 'restore') {
    passedEvidence.restore = await requirePassedJson(directory, 'restore.json', 'restore evidence');
    assert(Object.values(passedEvidence.restore.restored ?? {}).every((value) => typeof value === 'string' && value.length > 0), 'restore entity IDs are incomplete');
    const dump = (await readRequiredJson(directory, 'dump-metadata.json', 'dump metadata')).value;
    const dumpPath = await findFile(directory, 'study-room.dump');
    const dumpStat = await stat(dumpPath);
    assert(dump.sizeBytes === dumpStat.size && dump.sizeBytes > 0, 'restore dump size does not match');
    assert(dump.sha256 === await sha256File(dumpPath), 'restore dump SHA-256 does not match');
  } else if (requirement.job === 'soak') {
    passedEvidence.soak = await requirePassedJson(directory, 'soak.json', 'soak evidence');
    passedEvidence.soakProxy = await requirePassedJson(directory, 'soak-proxy.json', 'soak proxy evidence');
    assert(passedEvidence.soak.durationMs >= 600_000, 'soak duration was shorter than 600 seconds');
    assert(passedEvidence.soakProxy.durationMs >= 600_000, 'soak proxy probe was shorter than 600 seconds');
    assert(passedEvidence.soak.socketReconnects >= 2, 'soak did not record two successful reconnects');
    assert(passedEvidence.soak.httpRequests > 0 && passedEvidence.soak.chatEvents > 0, 'soak did not exercise HTTP and WebSocket traffic');
    assert(passedEvidence.soak.httpRetries === 0, 'soak observed HTTP retries');
    assert(passedEvidence.soak.socketSubscriptionFailures === 0, 'soak observed WebSocket subscription failures');
    assert(
      passedEvidence.soak.socketDisconnects === passedEvidence.soak.socketReconnects,
      'soak WebSocket disconnects were not fully recovered',
    );
    assert(passedEvidence.soakProxy.failures?.length === 0, 'soak proxy probe had failures');
    const replacements = (await readRequiredJson(directory, 'soak-replacements.json', 'soak replacement evidence')).value;
    const workloadStartedAt = Date.parse(passedEvidence.soak.startedAt);
    const workloadEndedAt = Date.parse(passedEvidence.soak.endedAt);
    const proxyStartedAt = Date.parse(passedEvidence.soakProxy.startedAt);
    const proxyEndedAt = Date.parse(passedEvidence.soakProxy.endedAt);
    assert(Number.isFinite(workloadStartedAt) && Number.isFinite(workloadEndedAt), 'soak workload timestamps are invalid');
    assert(Number.isFinite(proxyStartedAt) && Number.isFinite(proxyEndedAt), 'soak proxy timestamps are invalid');
    assert(proxyStartedAt <= workloadStartedAt && proxyEndedAt >= workloadEndedAt, 'soak proxy did not cover the full workload');
    let previousReplacementAt = workloadStartedAt;
    const reconnectMilestones = passedEvidence.soak.reconnectMilestones ?? [];
    for (const service of ['api-1', 'api-2']) {
      const replacementStartedAt = Date.parse(replacements[service]?.startedAt);
      const replacementCompletedAt = Date.parse(replacements[service]?.completedAt);
      assert(Number.isFinite(replacementStartedAt) && Number.isFinite(replacementCompletedAt), `soak replacement timing is missing for ${service}`);
      assert(replacementStartedAt >= previousReplacementAt && replacementCompletedAt >= replacementStartedAt, `soak replacement timing is out of order for ${service}`);
      assert(replacementCompletedAt <= workloadEndedAt, `soak replacement completed outside the workload for ${service}`);
      assert(
        reconnectMilestones.some((milestone) => {
          const at = Date.parse(milestone?.at);
          return Number.isFinite(at) && at >= replacementStartedAt && at <= replacementCompletedAt + 120_000;
        }),
        `soak did not record a successful proxy WebSocket reconnect during ${service} replacement`,
      );
      previousReplacementAt = replacementCompletedAt;
    }
  }
  for (const path of await filesUnder(directory)) {
    if (!path.endsWith('.json')) continue;
    let value;
    try {
      value = JSON.parse(await readFile(path, 'utf8'));
    } catch {
      continue;
    }
    assert(value?.passed !== false, `${requirement.job} contains a failed result in ${basename(path)}`);
  }
  return { result, manifest, serviceImages: images, passedEvidence };
}

async function saveApi(api, path, outputPath) {
  const result = await api.request(path);
  await mkdir(dirname(outputPath), { recursive: true });
  await writeFile(outputPath, result.text);
  return result.json;
}

function ensurePathWithin(parent, child, label) {
  const resolvedParent = resolve(parent);
  const resolvedChild = resolve(child);
  assert(
    resolvedChild.startsWith(`${resolvedParent}${sep}`),
    `${label} must stay inside ${resolvedParent}`,
  );
  return resolvedChild;
}

const repository = process.env.GITHUB_REPOSITORY;
const rcSha = process.env.RC_SHA?.toLowerCase();
const issueNumber = Number(process.env.RC_ISSUE_NUMBER);
const verifiedBy = process.env.RC_VERIFIED_BY?.trim();
const capturedAt = process.env.RC_CAPTURED_AT_UTC;
const workspace = resolve(process.env.GITHUB_WORKSPACE ?? process.cwd());
const runnerTemp = resolve(process.env.RUNNER_TEMP ?? join(workspace, 'build'));
const outputDirectory = ensurePathWithin(
  workspace,
  process.env.RC_EVIDENCE_DIR ?? join(workspace, 'artifacts', `rc-evidence-${rcSha}`),
  'RC_EVIDENCE_DIR',
);
const workDirectory = ensurePathWithin(
  runnerTemp,
  process.env.RC_EVIDENCE_WORK_DIR ?? join(runnerTemp, `rc-evidence-work-${rcSha}`),
  'RC_EVIDENCE_WORK_DIR',
);
assert(repository, 'GITHUB_REPOSITORY is required');
assert(/^[^/]+\/[^/]+$/.test(repository), 'GITHUB_REPOSITORY must use owner/name form');
assert(/^[a-f0-9]{40}$/.test(rcSha ?? ''), 'RC_SHA must be a full lowercase 40-character SHA');
assert(Number.isSafeInteger(issueNumber) && issueNumber > 0, 'RC_ISSUE_NUMBER must be positive');
assert(verifiedBy, 'RC_VERIFIED_BY is required');
assert(capturedAt && !Number.isNaN(Date.parse(capturedAt)), 'RC_CAPTURED_AT_UTC must be ISO-8601');
assert(Date.parse(capturedAt) <= Date.now(), 'RC_CAPTURED_AT_UTC cannot be in the future');
assert(process.env.GITHUB_TOKEN, 'GITHUB_TOKEN is required');
const screenshotUrls = (() => {
  try {
    const values = JSON.parse(process.env.RC_SCREENSHOT_URLS ?? '[]');
    assert(Array.isArray(values), 'RC_SCREENSHOT_URLS must be a JSON array');
    return values;
  } catch (error) {
    throw new Error(`Invalid RC_SCREENSHOT_URLS: ${error.message}`);
  }
})();
assert(screenshotUrls.length > 0, 'At least one Ruleset UI screenshot is required');
assert(screenshotUrls.length <= 10, 'At most ten Ruleset UI screenshots are allowed');
assert(new Set(screenshotUrls).size === screenshotUrls.length, 'Ruleset UI screenshot URLs must be unique');

await rm(outputDirectory, { recursive: true, force: true });
await rm(workDirectory, { recursive: true, force: true });
await mkdir(outputDirectory, { recursive: true });
await mkdir(workDirectory, { recursive: true });
const api = new GitHubApi({ repository });
const githubDirectory = join(outputDirectory, 'github');
const repositoryMetadata = await saveApi(api, '', join(githubDirectory, 'repository.json'));
validateRepositoryMetadata(repositoryMetadata, repository);
const branch = await saveApi(api, '/git/ref/heads/main', join(githubDirectory, 'main-ref.json'));
requireMainRefSha(branch, rcSha, 'Initial');
const commit = await saveApi(api, `/commits/${rcSha}`, join(githubDirectory, 'commit.json'));
assert(commit.sha === rcSha, `Commit API returned ${commit.sha}, expected ${rcSha}`);

const checkResponse = await saveApi(
  api,
  `/commits/${rcSha}/check-runs?per_page=100`,
  join(githubDirectory, 'check-runs.json'),
);
const checksByName = new Map();
for (const check of checkResponse.check_runs ?? []) {
  const current = checksByName.get(check.name);
  if (!current || check.id > current.id) checksByName.set(check.name, check);
}
for (const name of requiredChecks) {
  const check = checksByName.get(name);
  assert(check, `Required check ${name} is missing for ${rcSha}`);
  assert(check.status === 'completed' && check.conclusion === 'success', `Required check ${name} is not successful`);
  assert(check.head_sha === rcSha, `Required check ${name} belongs to another SHA`);
  assert(check.app?.slug === 'github-actions', `Required check ${name} is not from GitHub Actions`);
  assert(typeof check.details_url === 'string' && check.details_url.length > 0, `Required check ${name} has no details URL`);
}
const integrationIds = new Set(requiredChecks.map((name) => checksByName.get(name).app.id));
assert(integrationIds.size === 1, 'Required checks have different GitHub integration IDs');
const integrationId = [...integrationIds][0];
assert(Number.isSafeInteger(integrationId) && integrationId > 0, 'GitHub Actions integration ID is invalid');

const runsResponse = await saveApi(
  api,
  `/actions/runs?head_sha=${rcSha}&per_page=100`,
  join(githubDirectory, 'actions-runs.json'),
);
const workflows = Object.keys(workflowRequirements).map((name) =>
  selectWorkflowRun(
    runsResponse.workflow_runs ?? [],
    name,
    workflowPaths[name],
    rcSha,
  )
);
const workflowEvidence = [];
for (const workflow of workflows) {
  const slug = safeName(workflow.name);
  const workflowDirectory = join(outputDirectory, 'workflows', slug);
  const run = await saveApi(api, `/actions/runs/${workflow.id}`, join(workflowDirectory, 'run.json'));
  assert(run.head_sha === rcSha && run.status === 'completed' && run.conclusion === 'success', `${workflow.name} run detail drifted from the selected successful RC run`);
  assert(
    run.event === 'push'
      && run.name === workflow.name
      && run.path === workflowPaths[workflow.name],
    `${workflow.name} run identity or workflow path is incorrect`,
  );
  const jobsResponse = await saveApi(
    api,
    `/actions/runs/${workflow.id}/jobs?filter=latest&per_page=100`,
    join(workflowDirectory, 'jobs.json'),
  );
  const jobsByName = validateJobs(workflow, jobsResponse.jobs ?? [], workflowRequirements);
  const artifactsResponse = await saveApi(
    api,
    `/actions/runs/${workflow.id}/artifacts?per_page=100`,
    join(workflowDirectory, 'artifacts.json'),
  );
  await api.download(
    `${api.baseUrl}/actions/runs/${workflow.id}/logs`,
    join(workflowDirectory, 'logs.zip'),
  );
  workflowEvidence.push({
    workflow,
    run,
    jobs: jobsResponse.jobs,
    jobsByName,
    artifacts: artifactsResponse.artifacts,
  });
}
const requiredCheckSources = validateRequiredCheckSources({
  checksByName,
  workflowEvidence,
  workflowRequirements,
});
await writeJson(join(githubDirectory, 'required-check-sources.json'), {
  schemaVersion: 1,
  commitSha: rcSha,
  sources: Object.fromEntries(requiredCheckSources),
});

const rulesets = await saveApi(api, '/rulesets?per_page=100', join(githubDirectory, 'rulesets.json'));
const matchingRulesets = rulesets.filter((ruleset) => ruleset.name === rulesetName);
assert(matchingRulesets.length === 1, `Expected exactly one ${rulesetName}, found ${matchingRulesets.length}`);
const selectedRuleset = matchingRulesets[0];
const ruleset = await saveApi(
  api,
  `/rulesets/${selectedRuleset.id}`,
  join(githubDirectory, 'ruleset.json'),
);
validateRuleset(ruleset, integrationId);

const issue = await saveApi(api, `/issues/${issueNumber}`, join(githubDirectory, 'rc-issue.json'));
assert(issue.pull_request === undefined, `Issue ${issueNumber} is a pull request, not an RC tracking issue`);
const comments = await saveApi(
  api,
  `/issues/${issueNumber}/comments?per_page=100`,
  join(githubDirectory, 'rc-issue-comments.json'),
);
const { issueText, normalizedVerifiedBy, normalizedCapturedAtUtc } = validateRcIssueIdentity({
  issue,
  comments,
  sha: rcSha,
  verifiedBy,
  capturedAtUtc: capturedAt,
});
const uiFiles = [];
for (let index = 0; index < screenshotUrls.length; index += 1) {
  const url = screenshotUrls[index];
  assert(typeof url === 'string' && /^https:\/\/(github\.com|(?:user-images|private-user-images|objects)\.githubusercontent\.com)\//.test(url), `Unsupported screenshot URL: ${url}`);
  assert(issueText.includes(url), `Screenshot URL is not attached to RC issue ${issueNumber}: ${url}`);
  const temporaryPath = join(workDirectory, 'screenshots', `ruleset-${String(index + 1).padStart(2, '0')}`);
  const response = await api.download(url, temporaryPath);
  assert(response.headers.get('content-type')?.startsWith('image/'), `${url} is not an image`);
  const type = response.headers.get('content-type').split(';')[0];
  const extension = new Map([
    ['image/png', '.png'],
    ['image/jpeg', '.jpg'],
    ['image/webp', '.webp'],
    ['image/gif', '.gif'],
  ]).get(type);
  assert(extension, `${url} uses unsupported image type ${type}`);
  const path = join(outputDirectory, 'github', 'ui', `ruleset-${String(index + 1).padStart(2, '0')}${extension}`);
  await mkdir(dirname(path), { recursive: true });
  await rename(temporaryPath, path);
  const metadata = await stat(path);
  assert(metadata.size > 0, `${url} downloaded as an empty file`);
  uiFiles.push({ path: relative(outputDirectory, path).split(sep).join('/'), sizeBytes: metadata.size, sha256: await sha256File(path), sourceUrl: url });
}
await writeJson(join(outputDirectory, 'github', 'ui-evidence.json'), {
  schemaVersion: 1,
  issueNumber,
  verifiedBy: normalizedVerifiedBy,
  capturedAtUtc: normalizedCapturedAtUtc,
  files: uiFiles,
});

const ciWorkflow = workflowEvidence.find((entry) => entry.workflow.name === 'CI');
const composeWorkflow = workflowEvidence.find((entry) => entry.workflow.name === 'Compose integration');
const platformWorkflow = workflowEvidence.find((entry) => entry.workflow.name === 'Flutter platform builds');
const ciArtifacts = [
  `ci-server-evidence-${ciWorkflow.workflow.id}-${ciWorkflow.workflow.run_attempt}`,
  `ci-flutter-evidence-${ciWorkflow.workflow.id}-${ciWorkflow.workflow.run_attempt}`,
  `ci-golden-evidence-${ciWorkflow.workflow.id}-${ciWorkflow.workflow.run_attempt}`,
];
const ciArtifactResults = [];
for (const name of ciArtifacts) {
  const artifact = artifactByName(ciWorkflow.artifacts, name);
  const download = await downloadAndExtract(api, artifact, workDirectory);
  const destination = join(outputDirectory, 'ci', name.replace(`-${ciWorkflow.workflow.id}-${ciWorkflow.workflow.run_attempt}`, ''));
  await cp(download.directory, destination, { recursive: true });
  ciArtifactResults.push({ artifact, archiveSha256: download.archiveSha256 });
}
const goldenPath = await findFile(join(outputDirectory, 'ci'), 'golden-evidence.json');
const golden = validateGoldenEvidence(JSON.parse(await readFile(goldenPath, 'utf8')), {
  sha: rcSha,
  runUrl: ciWorkflow.workflow.html_url,
  scenarios: goldenScenarios,
});
const coveragePaths = (await filesUnder(join(outputDirectory, 'ci')))
  .filter((value) => basename(value).endsWith('coverage.json'));
validateCoverageEvidenceFiles(await Promise.all(coveragePaths.map(async (path) => ({
  name: basename(path),
  value: JSON.parse(await readFile(path, 'utf8')),
}))), { sha: rcSha, runUrl: ciWorkflow.workflow.html_url });
const contractsPath = await findFile(join(outputDirectory, 'ci'), 'contracts.json');
const contracts = JSON.parse(await readFile(contractsPath, 'utf8'));
assert(contracts.commitSha === rcSha && contracts.generatedDiff === false, 'Contract evidence does not prove zero drift for the RC SHA');
const npmAuditPath = await findFile(join(outputDirectory, 'ci'), 'npm-audit.json');
const npmAudit = validateNpmAuditReport(JSON.parse(await readFile(npmAuditPath, 'utf8')));
const publishDryRunPath = await findFile(join(outputDirectory, 'ci'), 'publish-dry-run.json');
const publishDryRun = validatePublishDryRunEvidence(
  JSON.parse(await readFile(publishDryRunPath, 'utf8')),
  { sha: rcSha, run: ciWorkflow.workflow },
);
for (const log of ['sdk-publish-dry-run.log', 'ui-publish-dry-run.log']) {
  const path = await findFile(join(outputDirectory, 'ci'), log);
  assert((await stat(path)).size > 0, `${log} is empty`);
}

const composeResults = [];
for (const requirement of composeScenarios) {
  const name = `${requirement.artifact}-${composeWorkflow.workflow.id}-${composeWorkflow.workflow.run_attempt}`;
  const artifact = artifactByName(composeWorkflow.artifacts, name);
  const download = await downloadAndExtract(api, artifact, workDirectory);
  const destination = join(outputDirectory, 'compose', requirement.job);
  await cp(download.directory, destination, { recursive: true });
  const job = composeWorkflow.jobsByName.get(requirement.job);
  composeResults.push({
    job: requirement.job,
    artifact,
    archiveSha256: download.archiveSha256,
    verification: await validateComposeArtifact(
      destination,
      requirement,
      rcSha,
      composeWorkflow.workflow,
      job,
    ),
  });
}

const platformResults = [];
for (const platform of platforms) {
  const name = `study-room-${platform}-${rcSha}`;
  const artifact = artifactByName(platformWorkflow.artifacts, name);
  const download = await downloadAndExtract(api, artifact, workDirectory);
  const verification = await validatePlatformArtifact(download.directory, platform, rcSha, platformWorkflow.workflow);
  const destination = join(outputDirectory, 'platforms', platform);
  await mkdir(destination, { recursive: true });
  await writeJson(join(destination, 'manifest.json'), verification.manifest);
  await writeJson(join(destination, 'verification.json'), {
    schemaVersion: 1,
    artifact: {
      id: artifact.id,
      name: artifact.name,
      sizeInBytes: artifact.size_in_bytes,
      digest: artifact.digest ?? null,
      downloadedArchiveSha256: download.archiveSha256,
      archiveDownloadUrl: artifact.archive_download_url,
      expiresAt: artifact.expires_at,
    },
    manifestSha256: verification.manifestSha256,
    verifiedFiles: verification.verifiedFiles,
  });
  platformResults.push({
    platform,
    artifact,
    archiveSha256: download.archiveSha256,
    verification,
  });
}

const finalBranch = await saveApi(
  api,
  '/git/ref/heads/main',
  join(githubDirectory, 'main-ref-final.json'),
);
requireMainRefSha(finalBranch, rcSha, 'Final');
const generatedAt = new Date().toISOString();
const rcRecord = {
  schemaVersion: 1,
  candidate: '0.4.0-rc.1',
  accepted: true,
  repository,
  branch: 'main',
  commitSha: rcSha,
  generatedAtUtc: generatedAt,
  requiredChecks: requiredChecks.map((name) => ({
    name,
    checkRunId: requiredCheckSources.get(name).checkRunId,
    checkRunUrl: requiredCheckSources.get(name).checkRunUrl,
    jobId: requiredCheckSources.get(name).jobId,
    jobUrl: requiredCheckSources.get(name).jobUrl,
    workflowName: requiredCheckSources.get(name).workflowName,
    workflowRunId: requiredCheckSources.get(name).workflowRunId,
    workflowRunAttempt: requiredCheckSources.get(name).workflowRunAttempt,
    detailsUrl: checksByName.get(name).details_url,
    completedAt: checksByName.get(name).completed_at,
    conclusion: checksByName.get(name).conclusion,
  })),
  workflows: workflows.map((workflow) => ({
    name: workflow.name,
    runId: workflow.id,
    runAttempt: workflow.run_attempt,
    url: workflow.html_url,
    headSha: workflow.head_sha,
    startedAt: workflow.run_started_at,
    updatedAt: workflow.updated_at,
    conclusion: workflow.conclusion,
  })),
  ruleset: { id: ruleset.id, name: ruleset.name, enforcement: ruleset.enforcement },
  issue: {
    number: issueNumber,
    url: issue.html_url,
    verifiedBy: normalizedVerifiedBy,
    capturedAtUtc: normalizedCapturedAtUtc,
  },
  ciArtifacts: ciArtifactResults.map(({ artifact, archiveSha256 }) => ({
    artifactId: artifact.id,
    artifactName: artifact.name,
    artifactDigest: artifact.digest,
    downloadedArchiveSha256: archiveSha256,
  })),
  npmAudit,
  publishDryRun,
  compose: composeResults.map(({ job, artifact, archiveSha256, verification }) => ({
    job,
    artifactId: artifact.id,
    artifactName: artifact.name,
    artifactDigest: artifact.digest,
    downloadedArchiveSha256: archiveSha256,
    imageId: verification.serviceImages.services['api-1'].imageId,
  })),
  platforms: platformResults.map(({ platform, artifact, archiveSha256, verification }) => ({
    platform,
    artifactId: artifact.id,
    artifactName: artifact.name,
    artifactDigest: artifact.digest,
    downloadedArchiveSha256: archiveSha256,
    manifestSha256: verification.manifestSha256,
    deliverables: verification.verifiedFiles,
  })),
  goldenBaselines: golden.baselines,
};
await writeJson(join(outputDirectory, 'rc.json'), rcRecord);
await writeFile(join(outputDirectory, 'rc.md'), [
  '# Study Room 0.4 RC acceptance',
  '',
  `- Result: accepted`,
  `- Commit: \`${rcSha}\``,
  `- Generated: ${generatedAt}`,
  `- Required checks: ${requiredChecks.length} successful`,
  `- Compose scenarios: ${composeResults.length} verified`,
  `- Platform artifacts: ${platformResults.length} verified`,
  `- Ruleset: ${ruleset.name} (${ruleset.enforcement})`,
  `- Tracking issue: ${issue.html_url}`,
  '',
].join('\n'));

const evidenceFiles = (await filesUnder(outputDirectory))
  .filter((path) => basename(path) !== 'SHA256SUMS')
  .sort();
const sums = [];
for (const path of evidenceFiles) {
  sums.push(`${await sha256File(path)}  ${relative(outputDirectory, path).split(sep).join('/')}`);
}
await writeFile(join(outputDirectory, 'SHA256SUMS'), `${sums.join('\n')}\n`);
await rm(workDirectory, { recursive: true, force: true });
console.log(`Accepted RC ${rcSha}; evidence written to ${outputDirectory}.`);
