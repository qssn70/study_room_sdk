import assert from 'node:assert/strict';
import { mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

import {
  goldenScenarios,
  requiredChecks,
  workflowPaths,
} from './release/required-checks.mjs';
import {
  checkRunIdFromJob,
  requireMainRefSha,
  requiredJobSteps,
  sha256File,
  selectWorkflowRun,
  validateComposeContainerSnapshot,
  validateComposeLog,
  validateCoverageEvidenceFiles,
  validateGoldenEvidence,
  validateJobs,
  validateNpmAuditReport,
  validatePlatformArtifact,
  validatePublishDryRunEvidence,
  validateRcIssueIdentity,
  validateRepositoryMetadata,
  validateRequiredCheckSources,
  verifyArtifactArchive,
} from './release/evidence-validation.mjs';
import { buildRuleset, validateRuleset } from './release/ruleset.mjs';
import { GitHubApi } from './release/github-api.mjs';

test('GitHub API never forwards its repository token to another origin', async () => {
  const originalFetch = globalThis.fetch;
  const requests = [];
  globalThis.fetch = async (url, options) => {
    requests.push({ url: `${url}`, authorization: options.headers.authorization });
    return new Response('{}', { status: 200, headers: { 'content-type': 'application/json' } });
  };
  try {
    const api = new GitHubApi({ repository: 'example/repo', token: 'secret-token' });
    await api.request('/issues/1');
    await api.request('https://example.test/screenshot.png');
  } finally {
    globalThis.fetch = originalFetch;
  }
  assert.deepEqual(requests, [
    {
      url: 'https://api.github.com/repos/example/repo/issues/1',
      authorization: 'Bearer secret-token',
    },
    { url: 'https://example.test/screenshot.png', authorization: undefined },
  ]);
});

test('RC collector confines recursive cleanup to the workspace and runner temp', async () => {
  const collector = await readFile(resolve('tool/collect-rc-evidence.mjs'), 'utf8');
  assert.match(collector, /ensurePathWithin\(\s*workspace,/);
  assert.match(collector, /ensurePathWithin\(\s*runnerTemp,/);
  assert.match(collector, /await rm\(outputDirectory, \{ recursive: true, force: true \}\)/);
  assert.match(collector, /await rm\(workDirectory, \{ recursive: true, force: true \}\)/);
});

test('RC evidence verifies the downloaded artifact ZIP against the GitHub digest', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'study-room-artifact-'));
  const archive = join(directory, 'artifact.zip');
  await writeFile(archive, 'downloaded artifact bytes');
  const digest = await sha256File(archive);
  assert.equal(
    await verifyArtifactArchive(archive, { id: 1, name: 'evidence', digest: `sha256:${digest}` }),
    digest,
  );
  await assert.rejects(
    verifyArtifactArchive(archive, { id: 1, name: 'evidence', digest: `sha256:${'0'.repeat(64)}` }),
    /archive SHA-256 does not match GitHub/,
  );
  await assert.rejects(
    verifyArtifactArchive(archive, { id: 1, name: 'evidence', digest: null }),
    /missing a valid SHA-256 digest/,
  );
});

test('RC evidence rejects high or critical npm audit findings', () => {
  const clean = {
    auditReportVersion: 2,
    vulnerabilities: {
      example: { severity: 'moderate' },
    },
    metadata: {
      vulnerabilities: { info: 0, low: 0, moderate: 1, high: 0, critical: 0, total: 1 },
    },
  };
  assert.deepEqual(validateNpmAuditReport(clean).vulnerabilities, clean.metadata.vulnerabilities);
  assert.throws(
    () => validateNpmAuditReport({
      ...clean,
      metadata: {
        vulnerabilities: { ...clean.metadata.vulnerabilities, high: 1, total: 2 },
      },
    }),
    /high or critical vulnerabilities/,
  );
  assert.throws(
    () => validateNpmAuditReport({
      ...clean,
      vulnerabilities: { compromised: { severity: 'critical' } },
    }),
    /high or critical package entries: compromised/,
  );
});

test('RC evidence requires structured success from both package publish dry-runs', () => {
  const sha = 'a'.repeat(40);
  const run = { id: 42, run_attempt: 3, html_url: 'https://github.com/example/repo/actions/runs/42' };
  const evidence = {
    schemaVersion: 1,
    commitSha: sha,
    runUrl: run.html_url,
    runId: '42',
    runAttempt: '3',
    packages: {
      study_room_sdk: { passed: true, log: 'sdk-publish-dry-run.log' },
      study_room_ui: { passed: true, log: 'ui-publish-dry-run.log' },
    },
    passed: true,
  };
  assert.equal(validatePublishDryRunEvidence(evidence, { sha, run }), evidence);
  assert.throws(
    () => validatePublishDryRunEvidence({
      ...evidence,
      packages: { ...evidence.packages, study_room_ui: { ...evidence.packages.study_room_ui, passed: false } },
    }, { sha, run }),
    /study_room_ui publish dry-run did not pass/,
  );
  assert.throws(
    () => validatePublishDryRunEvidence({ ...evidence, runAttempt: '2' }, { sha, run }),
    /run attempt does not match/,
  );
});

test('RC evidence binds every required check to the selected workflow run attempt', () => {
  const sha = 'b'.repeat(40);
  const requirements = { CI: ['server', 'flutter'] };
  const workflow = { name: 'CI', id: 100, run_attempt: 2, head_sha: sha };
  const serverJob = {
    id: 501,
    name: 'server',
    run_id: 100,
    run_attempt: 2,
    head_sha: sha,
    check_run_url: 'https://api.github.com/repos/example/repo/check-runs/701',
    html_url: 'https://github.com/example/repo/actions/runs/100/job/501',
  };
  const flutterJob = {
    id: 502,
    name: 'flutter',
    run_id: 100,
    run_attempt: 2,
    head_sha: sha,
    check_run_url: 'https://api.github.com/repos/example/repo/check-runs/702',
    html_url: 'https://github.com/example/repo/actions/runs/100/job/502',
  };
  assert.equal(checkRunIdFromJob(serverJob), 701);
  const sources = validateRequiredCheckSources({
    checksByName: new Map([
      ['server', { id: 701 }],
      ['flutter', { id: 702 }],
    ]),
    workflowEvidence: [{ workflow, jobsByName: new Map([['server', serverJob], ['flutter', flutterJob]]) }],
    workflowRequirements: requirements,
  });
  assert.deepEqual(sources.get('server'), {
    checkRunId: 701,
    checkRunUrl: serverJob.check_run_url,
    jobId: 501,
    jobUrl: serverJob.html_url,
    workflowName: 'CI',
    workflowRunId: 100,
    workflowRunAttempt: 2,
  });
  assert.throws(
    () => validateRequiredCheckSources({
      checksByName: new Map([['server', { id: 999 }], ['flutter', { id: 702 }]]),
      workflowEvidence: [{ workflow, jobsByName: new Map([['server', serverJob], ['flutter', flutterJob]]) }],
      workflowRequirements: requirements,
    }),
    /server check-run does not belong to selected CI run attempt/,
  );
  assert.throws(
    () => validateRequiredCheckSources({
      checksByName: new Map([['server', { id: 701 }], ['flutter', { id: 702 }]]),
      workflowEvidence: [{
        workflow,
        jobsByName: new Map([
          ['server', { ...serverJob, run_id: 99 }],
          ['flutter', flutterJob],
        ]),
      }],
      workflowRequirements: requirements,
    }),
    /server belongs to another workflow run/,
  );
});

test('RC workflow selection rejects a same-name run from another workflow path', () => {
  const sha = 'f'.repeat(40);
  const base = {
    name: 'CI',
    event: 'push',
    head_sha: sha,
    status: 'completed',
    conclusion: 'success',
    run_attempt: 1,
  };
  const official = { ...base, id: 10, path: workflowPaths.CI };
  const impostor = { ...base, id: 20, run_attempt: 2, path: '.github/workflows/impostor.yml' };
  assert.equal(
    selectWorkflowRun([impostor, official], 'CI', workflowPaths.CI, sha),
    official,
  );
  assert.throws(
    () => selectWorkflowRun([impostor], 'CI', workflowPaths.CI, sha),
    /at \.github\/workflows\/ci\.yml/,
  );
  assert.deepEqual(workflowPaths, {
    CI: '.github/workflows/ci.yml',
    'Compose integration': '.github/workflows/integration.yml',
    'Flutter platform builds': '.github/workflows/platform-builds.yml',
  });
});

test('RC evidence requires every declared critical workflow step to succeed', () => {
  const workflow = { name: 'CI' };
  const requirements = { CI: ['server'] };
  const steps = requiredJobSteps.CI.server.map((name) => ({ name, status: 'completed', conclusion: 'success' }));
  const job = { name: 'server', status: 'completed', conclusion: 'success', steps };
  assert.equal(validateJobs(workflow, [job], requirements).get('server'), job);
  assert.throws(
    () => validateJobs(workflow, [{ ...job, steps: steps.slice(1) }], requirements),
    /missing required step Generate OpenAPI-derived/,
  );
  assert.throws(
    () => validateJobs(workflow, [{
      ...job,
      steps: steps.map((step) => step.name === 'Build server'
        ? { ...step, conclusion: 'skipped' }
        : step),
    }], requirements),
    /required step Build server is not successful/,
  );
});

test('critical-step declarations cover all 16 required jobs', () => {
  assert.deepEqual(
    Object.fromEntries(Object.entries(requiredJobSteps).map(([workflow, jobs]) => [
      workflow,
      Object.keys(jobs).sort(),
    ])),
    {
      CI: ['Golden tests (Ubuntu)', 'compose-config', 'dart-dependency-security', 'flutter', 'server'],
      'Compose integration': ['core', 'rate_limit', 'resilience', 'restore', 'soak'],
      'Flutter platform builds': [
        'Release build (android)',
        'Release build (ios)',
        'Release build (linux)',
        'Release build (macos)',
        'Release build (web)',
        'Release build (windows)',
      ],
    },
  );
});

test('critical-step declarations match the current workflow step names', async () => {
  const yaml = (await import('js-yaml')).default;
  const workflowPaths = [
    '.github/workflows/ci.yml',
    '.github/workflows/integration.yml',
    '.github/workflows/platform-builds.yml',
  ];
  for (const path of workflowPaths) {
    const workflow = yaml.load(await readFile(resolve(path), 'utf8'));
    const jobsByDisplayName = new Map();
    for (const [jobId, job] of Object.entries(workflow.jobs)) {
      if (workflow.name === 'Flutter platform builds') {
        for (const platform of ['android', 'ios', 'web', 'windows', 'macos', 'linux']) {
          jobsByDisplayName.set(`Release build (${platform})`, {
            steps: (job.steps ?? []).map((step) => `${step.name ?? ''}`.replaceAll('${{ matrix.target }}', platform)),
          });
        }
      } else {
        jobsByDisplayName.set(job.name ?? jobId, { steps: (job.steps ?? []).map((step) => step.name) });
      }
    }
    for (const [jobName, requiredSteps] of Object.entries(requiredJobSteps[workflow.name])) {
      const declared = jobsByDisplayName.get(jobName)?.steps ?? [];
      for (const requiredStep of requiredSteps) {
        assert.ok(declared.includes(requiredStep), `${workflow.name}/${jobName} lacks ${requiredStep}`);
      }
    }
  }
});

test('RC issue identity includes normalized verifier, capture time, and frozen SHA', () => {
  const sha = 'a'.repeat(40);
  const capturedAtUtc = '2026-08-12T01:02:03.000Z';
  const valid = validateRcIssueIdentity({
    issue: { title: `RC ${sha}`, body: 'Verified by: @ＡＬＩＣＥ' },
    comments: [{ body: `Captured: ${capturedAtUtc}` }],
    sha,
    verifiedBy: ' @Alice ',
    capturedAtUtc,
  });
  assert.equal(valid.normalizedVerifiedBy, 'alice');
  assert.equal(valid.normalizedCapturedAtUtc, capturedAtUtc);
  assert.throws(
    () => validateRcIssueIdentity({
      issue: { title: `RC ${sha}`, body: 'Verified by: @bob' },
      comments: [{ body: `Captured: ${capturedAtUtc}` }],
      sha,
      verifiedBy: 'alice',
      capturedAtUtc,
    }),
    /Verified by: @login field/,
  );
  assert.throws(
    () => validateRcIssueIdentity({
      issue: { title: `RC ${sha}`, body: 'Verified by: @alice' },
      comments: [],
      sha,
      verifiedBy: 'alice',
      capturedAtUtc,
    }),
    /normalized capture time/,
  );
  assert.throws(
    () => validateRcIssueIdentity({
      issue: { title: `RC ${sha}`, body: 'Target branch: main' },
      comments: [{ body: `Captured: ${capturedAtUtc}` }],
      sha,
      verifiedBy: 'main',
      capturedAtUtc,
    }),
    /Verified by: @login field/,
  );
});

test('RC evidence requires exact coverage files, metrics, and thresholds', () => {
  const sha = 'b'.repeat(40);
  const runUrl = 'https://github.com/example/repo/actions/runs/42';
  const coverage = (name, source, metrics) => ({
    name,
    value: {
      schemaVersion: 1,
      commitSha: sha,
      runUrl,
      source,
      passed: true,
      results: Object.entries(metrics).map(([label, minimum]) => ({
        label,
        hits: minimum,
        found: 100,
        percent: minimum,
        minimum,
        passed: true,
      })),
    },
  });
  const valid = [
    coverage('server-coverage.json', 'server/coverage/lcov.info', { lines: 80, branches: 80 }),
    coverage('sdk-coverage.json', 'packages/study_room_sdk/coverage/lcov.info', { lines: 80, branches: 80 }),
    coverage('ui-coverage.json', 'packages/study_room_ui/coverage/lcov.info', { lines: 70 }),
  ];
  assert.equal(Object.keys(validateCoverageEvidenceFiles(valid, { sha, runUrl })).length, 3);
  assert.throws(
    () => validateCoverageEvidenceFiles([...valid, valid[0]], { sha, runUrl }),
    /filename set is incorrect/,
  );
  const substituted = structuredClone(valid);
  substituted[0].name = 'alternate-coverage.json';
  assert.throws(
    () => validateCoverageEvidenceFiles(substituted, { sha, runUrl }),
    /filename set is incorrect/,
  );
  const weakened = structuredClone(valid);
  weakened[1].value.results[1].minimum = 70;
  assert.throws(
    () => validateCoverageEvidenceFiles(weakened, { sha, runUrl }),
    /branches threshold is not 80/,
  );
  const extraMetric = structuredClone(valid);
  extraMetric[2].value.results.push({ label: 'branches', hits: 1, found: 1, percent: 100, minimum: 0, passed: true });
  assert.throws(
    () => validateCoverageEvidenceFiles(extraMetric, { sha, runUrl }),
    /metric set or order is incorrect/,
  );
  const forgedPercent = structuredClone(valid);
  forgedPercent[0].value.results[0].percent = 99;
  assert.throws(
    () => validateCoverageEvidenceFiles(forgedPercent, { sha, runUrl }),
    /percent does not match hits\/found/,
  );
});

test('Golden acceptance rejects empty, invalid, or duplicate baseline hashes', () => {
  const sha = 'c'.repeat(40);
  const runUrl = 'https://github.com/example/repo/actions/runs/43';
  const golden = {
    schemaVersion: 1,
    commitSha: sha,
    runUrl,
    runGoldens: true,
    scenarioCount: goldenScenarios.length,
    baselines: goldenScenarios.map((name, index) => ({
      name,
      sizeBytes: index + 1,
      sha256: index.toString(16).padStart(64, '0'),
    })),
  };
  assert.equal(validateGoldenEvidence(golden, { sha, runUrl, scenarios: goldenScenarios }), golden);
  const empty = structuredClone(golden);
  empty.baselines[0].sizeBytes = 0;
  assert.throws(() => validateGoldenEvidence(empty, { sha, runUrl, scenarios: goldenScenarios }), /size is invalid/);
  const uppercase = structuredClone(golden);
  uppercase.baselines[0].sha256 = 'A'.repeat(64);
  assert.throws(() => validateGoldenEvidence(uppercase, { sha, runUrl, scenarios: goldenScenarios }), /SHA-256 is invalid/);
  const duplicate = structuredClone(golden);
  duplicate.baselines[1].sha256 = duplicate.baselines[0].sha256;
  assert.throws(() => validateGoldenEvidence(duplicate, { sha, runUrl, scenarios: goldenScenarios }), /reuses another/);
});

test('RC evidence rejects a final main ref that moved away from the frozen SHA', async () => {
  const sha = 'a'.repeat(40);
  assert.equal(requireMainRefSha({ object: { sha } }, sha, 'Final'), sha);
  assert.throws(
    () => requireMainRefSha({ object: { sha: 'b'.repeat(40) } }, sha, 'Final'),
    /Final main is .*expected frozen RC/,
  );
  const collector = await readFile(resolve('tool/collect-rc-evidence.mjs'), 'utf8');
  assert.match(collector, /main-ref-final\.json/);
  assert.equal([...collector.matchAll(/'\/git\/ref\/heads\/main'/g)].length, 2);
});

test('RC evidence binds the default-branch ruleset target to main repository metadata', async () => {
  const metadata = { full_name: 'example/study-room', default_branch: 'main' };
  assert.equal(validateRepositoryMetadata(metadata, 'example/study-room'), metadata);
  assert.throws(
    () => validateRepositoryMetadata({ ...metadata, default_branch: 'release' }, 'example/study-room'),
    /default branch is release, expected main/,
  );
  assert.throws(
    () => validateRepositoryMetadata({ ...metadata, full_name: 'other/repo' }, 'example/study-room'),
    /identifies other\/repo/,
  );
  const collector = await readFile(resolve('tool/collect-rc-evidence.mjs'), 'utf8');
  assert.match(collector, /repository\.json/);
  assert.match(collector, /validateRepositoryMetadata\(repositoryMetadata, repository\)/);
});

test('failed RC diagnostics never use an unvalidated rc_sha in a path or artifact name', async () => {
  const workflow = await readFile(resolve('.github/workflows/rc-evidence.yml'), 'utf8');
  const failureSection = workflow.slice(workflow.indexOf('- name: Prepare failed collection diagnostics'));
  assert.match(
    failureSection,
    /FAILURE_DIRECTORY: artifacts\/rc-evidence-failure-\$\{\{ github\.run_id \}\}-\$\{\{ github\.run_attempt \}\}/,
  );
  assert.match(
    failureSection,
    /name: rc-evidence-failure-\$\{\{ github\.run_id \}\}-\$\{\{ github\.run_attempt \}\}/,
  );
  assert.match(failureSection, /commitSha: process\.env\.RC_SHA/);
  assert.doesNotMatch(failureSection, /(?:name:|path:|FAILURE_DIRECTORY:)[^\n]*inputs\.rc_sha/);
  assert.doesNotMatch(workflow, /group:[^\n]*inputs\.rc_sha/);
});

test('RC evidence hashes downloaded UI screenshots with the shared file helper', async () => {
  const collector = await readFile(resolve('tool/collect-rc-evidence.mjs'), 'utf8');
  assert.match(
    collector,
    /uiFiles\.push\(\{[^\n]*sha256: await sha256File\(path\)/,
  );
  assert.doesNotMatch(collector, /await sha256\(path\)/);
});

test('release ruleset declares exactly the 16 GitHub Actions checks', () => {
  const ruleset = buildRuleset(15368);
  validateRuleset(ruleset, 15368);
  const statusRule = ruleset.rules.find((rule) => rule.type === 'required_status_checks');
  assert.equal(requiredChecks.length, 16);
  assert.deepEqual(
    statusRule.parameters.required_status_checks.map((check) => check.context),
    requiredChecks,
  );
  assert.ok(statusRule.parameters.required_status_checks.every(
    (check) => check.integration_id === 15368 && !check.context.includes('/'),
  ));
});

test('release ruleset validator rejects context and source drift', () => {
  const ruleset = structuredClone(buildRuleset(15368));
  const statusRule = ruleset.rules.find((rule) => rule.type === 'required_status_checks');
  statusRule.parameters.required_status_checks[0].context = 'CI/dart-dependency-security';
  statusRule.parameters.required_status_checks[1].integration_id = null;
  assert.throws(() => validateRuleset(ruleset, 15368), /contexts do not match.*GitHub Actions integration/);
});

test('release ruleset validator rejects bypass, exclusions, extra rules, and create-policy drift', () => {
  const ruleset = structuredClone(buildRuleset(15368));
  ruleset.bypass_actors.push({ actor_id: 5, actor_type: 'Team', bypass_mode: 'always' });
  ruleset.conditions.ref_name.exclude.push('refs/heads/escape');
  ruleset.rules.push({ type: 'pull_request', parameters: {} });
  ruleset.rules.find((rule) => rule.type === 'required_status_checks')
    .parameters.do_not_enforce_on_create = false;
  assert.throws(
    () => validateRuleset(ruleset, 15368),
    /bypass_actors.*exclusions.*exactly deletion.*initial branch creation/,
  );
});

test('LCOV checker writes a machine-readable accepted summary', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'study-room-lcov-'));
  const source = join(directory, 'lcov.info');
  const output = join(directory, 'coverage.json');
  await writeFile(source, [
    'SF:example.dart',
    'DA:1,1',
    'DA:2,1',
    'BRDA:1,0,0,1',
    'BRDA:1,0,1,1',
    'end_of_record',
    '',
  ].join('\n'));
  const result = spawnSync(
    process.execPath,
    [resolve('tool/check-lcov.mjs'), source, '100', '100', '--output', output],
    { encoding: 'utf8' },
  );
  assert.equal(result.status, 0, result.stderr);
  const summary = JSON.parse(await readFile(output, 'utf8'));
  assert.equal(summary.passed, true);
  assert.deepEqual(summary.results.map((entry) => entry.percent), [100, 100]);
});

test('LCOV checker rejects invalid thresholds and missing output values', () => {
  const source = resolve('tool/check-lcov.mjs');
  const invalidThreshold = spawnSync(process.execPath, [source, 'missing.info', 'NaN'], { encoding: 'utf8' });
  assert.notEqual(invalidThreshold.status, 0);
  assert.match(invalidThreshold.stderr, /Line minimum must be a number/);
  const missingOutput = spawnSync(process.execPath, [source, 'missing.info', '80', '--output'], { encoding: 'utf8' });
  assert.notEqual(missingOutput.status, 0);
  assert.match(missingOutput.stderr, /--output requires a file path/);
});

test('Golden evidence requires exactly eight non-empty PNG files', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'study-room-golden-'));
  const output = join(directory, 'golden.json');
  const png = Buffer.from('89504e470d0a1a0a', 'hex');
  await Promise.all(goldenScenarios.map((name) => writeFile(join(directory, name), png)));
  const result = spawnSync(
    process.execPath,
    [resolve('tool/golden-evidence.mjs'), directory, output],
    { encoding: 'utf8', env: { ...process.env, STUDY_ROOM_RUN_GOLDENS: 'true', GITHUB_SHA: 'a'.repeat(40) } },
  );
  assert.equal(result.status, 0, result.stderr);
  const evidence = JSON.parse(await readFile(output, 'utf8'));
  assert.equal(evidence.scenarioCount, 8);
  assert.equal(evidence.commitSha, 'a'.repeat(40));
  await writeFile(join(directory, 'unexpected.png'), png);
  const extra = spawnSync(
    process.execPath,
    [resolve('tool/golden-evidence.mjs'), directory, output],
    { encoding: 'utf8', env: { ...process.env, STUDY_ROOM_RUN_GOLDENS: 'true' } },
  );
  assert.notEqual(extra.status, 0);
  assert.match(extra.stderr, /baseline set differs/);
});

test('two-instance evidence serializes the observed concurrent session statuses', async () => {
  const source = await readFile(resolve('server/tool/e2e-two-instance.mjs'), 'utf8');
  assert.match(source, /concurrentSessionStatuses:\s*concurrentStatuses/);
  assert.doesNotMatch(source, /^\s*concurrentSessionStatuses,\s*$/m);
});

test('Compose builds the shared server image once and preserves container image IDs', async () => {
  const compose = await readFile(resolve('docker-compose.yml'), 'utf8');
  assert.equal([...compose.matchAll(/^\s+build:\s*$/gm)].length, 1);
  assert.equal([
    ...compose.matchAll(/^\s+image: \$\{STUDY_ROOM_SERVER_IMAGE:-study-room-server:0\.4\.0-rc\.1\}\s*$/gm),
  ].length, 4);
  const evidence = await readFile(resolve('server/tool/e2e-service-images.mjs'), 'utf8');
  assert.match(evidence, /imageInspectError/);
  assert.match(evidence, /containerInspectError/);
  assert.match(evidence, /imageId,/);
  assert.match(evidence, /--compose-ps/);
  assert.match(evidence, /com\.docker\.compose\.image/);
});

test('platform release artifacts can replace a prior upload when a run attempt is rerun', async () => {
  const workflow = await readFile(resolve('.github/workflows/platform-builds.yml'), 'utf8');
  const uploadStep = workflow.slice(workflow.indexOf('uses: actions/upload-artifact@v4'));
  assert.match(uploadStep, /name: study-room-\$\{\{ matrix\.target \}\}-\$\{\{ github\.sha \}\}/);
  assert.match(uploadStep, /overwrite: true/);
});

test('platform artifact validation requires an exact single packaged deliverable', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'study-room-platform-'));
  const artifactDirectory = join(directory, 'artifacts', 'releases');
  const manifestDirectory = join(directory, 'artifacts', 'manifests');
  await mkdir(artifactDirectory, { recursive: true });
  await mkdir(manifestDirectory, { recursive: true });
  const artifactPath = join(artifactDirectory, 'study-room-android.apk');
  await writeFile(artifactPath, 'android artifact');
  const relativeArtifact = 'artifacts/releases/study-room-android.apk';
  const sha = 'd'.repeat(40);
  const run = {
    id: 44,
    run_attempt: 2,
    html_url: 'https://github.com/example/repo/actions/runs/44',
  };
  const manifest = {
    schemaVersion: 1,
    commitSha: sha,
    platform: 'android',
    runId: '44',
    runAttempt: '2',
    runUrl: run.html_url,
    startedAtUtc: '2026-08-12T01:00:00.000Z',
    endedAtUtc: '2026-08-12T01:01:00.000Z',
    durationSeconds: 60,
    artifactRoot: relativeArtifact,
    totalSizeBytes: 16,
    files: [{
      path: relativeArtifact,
      sizeBytes: 16,
      sha256: await sha256File(artifactPath),
    }],
  };
  const manifestPath = join(manifestDirectory, 'android.json');
  await writeFile(manifestPath, `${JSON.stringify(manifest)}\n`);
  assert.equal(
    (await validatePlatformArtifact(directory, 'android', sha, run)).verifiedFiles.length,
    1,
  );
  await writeFile(join(artifactDirectory, 'undeclared.txt'), 'not declared');
  await assert.rejects(
    validatePlatformArtifact(directory, 'android', sha, run),
    /files do not exactly match its manifest/,
  );
  const wrongRoot = structuredClone(manifest);
  wrongRoot.artifactRoot = 'artifacts/releases/not-the-apk.zip';
  await writeFile(manifestPath, `${JSON.stringify(wrongRoot)}\n`);
  await assert.rejects(
    validatePlatformArtifact(directory, 'android', sha, run),
    /artifact root is not the main artifact path/,
  );
  const duplicateMain = structuredClone(manifest);
  duplicateMain.files.push({
    ...duplicateMain.files[0],
    path: 'artifacts/releases/second.apk',
  });
  await writeFile(manifestPath, `${JSON.stringify(duplicateMain)}\n`);
  await assert.rejects(
    validatePlatformArtifact(directory, 'android', sha, run),
    /exactly one \.apk main artifact/,
  );
});

test('all Compose image captures are bound to their compose-ps snapshot', async () => {
  const workflow = await readFile(resolve('.github/workflows/integration.yml'), 'utf8');
  assert.equal(
    [...workflow.matchAll(/e2e-service-images\.mjs \\\s+--compose-ps artifacts\/compose-ps\.json --output artifacts\/service-images\.json/g)].length,
    5,
  );
  const validator = await readFile(resolve('tool/release/evidence-validation.mjs'), 'utf8');
  assert.match(validator, /container ID does not match compose-ps\.json/);
  const images = {
    services: {
      'api-1': { containerId: 'a'.repeat(64) },
      'api-2': { containerId: 'b'.repeat(64) },
    },
  };
  const rows = [
    { Service: 'api-1', ID: 'a'.repeat(64) },
    { Service: 'api-2', ID: 'b'.repeat(64) },
  ];
  assert.equal(validateComposeContainerSnapshot(images, rows, 'core'), images);
  assert.throws(
    () => validateComposeContainerSnapshot(images, [{ ...rows[0], ID: 'a'.repeat(12) }, rows[1]], 'core'),
    /api-1 container ID does not match/,
  );
});

test('Compose evidence requires a non-empty timestamped Docker log', () => {
  assert.deepEqual(
    validateComposeLog('api-1  | 2026-08-12T01:02:03.123456789Z ready\n', 'core'),
    { lineCount: 1 },
  );
  assert.throws(() => validateComposeLog('   \n', 'core'), /Compose log is empty/);
  assert.throws(() => validateComposeLog('api-1  | ready\n', 'core'), /does not contain Docker timestamps/);
});

test('rolling replacement drains nginx upstreams and records a full soak proxy probe', async () => {
  const workflow = await readFile(resolve('.github/workflows/integration.yml'), 'utf8');
  const nginx = await readFile(resolve('deploy/nginx.conf'), 'utf8');
  const collector = await readFile(resolve('tool/collect-rc-evidence.mjs'), 'utf8');
  const soak = await readFile(resolve('server/tool/e2e-soak.mjs'), 'utf8');
  assert.match(nginx, /include \/etc\/nginx\/conf\.d\/study-room-upstream\.conf/);
  assert.ok([...workflow.matchAll(/drain_and_replace api-[12]/g)].length >= 4);
  assert.match(workflow, /E2E_STOP_PATH=\/artifacts\/rolling-probe\.stop/);
  assert.match(workflow, /E2E_RESULT_PATH=\/artifacts\/soak-proxy\.json/);
  assert.match(collector, /soak proxy probe had failures/);
  assert.match(soak, /connectResilient\(proxyApi1, ownerToken\)/);
  assert.match(soak, /connectResilient\(proxyApi2, ownerToken\)/);
  assert.doesNotMatch(nginx, /__e2e/);
  const e2eNginx = await readFile(resolve('deploy/nginx-e2e.test.conf'), 'utf8');
  assert.match(e2eNginx, /server_name api-1-proxy/);
  assert.match(e2eNginx, /server_name api-2-proxy/);
});

test('RC evidence always uploads failure diagnostics after a failed finalization', async () => {
  const workflow = await readFile(resolve('.github/workflows/rc-evidence.yml'), 'utf8');
  assert.match(
    workflow,
    /- name: Upload failed collection diagnostics\s+if: failure\(\)/,
  );
});

test('RC issue artifact comment does not claim acceptance before the workflow succeeds', async () => {
  const workflow = await readFile(resolve('.github/workflows/rc-evidence.yml'), 'utf8');
  assert.match(workflow, /RC evidence artifact uploaded for/);
  assert.match(
    workflow,
    /Acceptance condition: this exact RC evidence workflow must conclude successfully/,
  );
  assert.doesNotMatch(workflow, /RC evidence accepted for/);
});

test('graceful shutdown evidence requires a uniquely tagged flushed span', async () => {
  const workflow = await readFile(resolve('.github/workflows/integration.yml'), 'utf8');
  const otel = await readFile(resolve('server/tool/e2e-otel.mjs'), 'utf8');
  const gracefulStep = workflow.slice(workflow.indexOf('id: graceful_otel'));
  assert.match(workflow, /shutdown_marker="graceful-\$\{E2E_RUN_ID\}-\$\(openssl rand -hex 16\)"/);
  assert.match(
    workflow,
    /"x-study-room-e2e-trace-marker": process\.env\.E2E_TRACE_MARKER/,
  );
  assert.match(workflow, /docker compose exec -T -e E2E_TRACE_MARKER="\$shutdown_marker" api-2/);
  assert.match(workflow, /OTEL_BSP_SCHEDULE_DELAY: 60000/);
  assert.match(workflow, /E2E_OTEL_FORBIDDEN_MARKER="\$shutdown_marker"/);
  assert.match(workflow, /E2E_RESULT_PATH=\/artifacts\/otel-before-sigterm\.json/);
  assert.ok(
    gracefulStep.indexOf('E2E_OTEL_FORBIDDEN_MARKER="$shutdown_marker"')
      < gracefulStep.indexOf('docker compose stop --timeout 15 api-1'),
  );
  assert.match(
    workflow,
    /baseline_spans=\$\(jq -c '\{"api-1": \.instanceSpanCounts\["api-1"\]\}'/,
  );
  assert.match(workflow, /for _ in \$\(seq 1 30\); do[\s\S]*E2E_OTEL_EXPECTED_MARKER/);
  assert.match(workflow, /E2E_OTEL_EXPECTED_MARKER="\$shutdown_marker"/);
  assert.match(otel, /expectedMarkerFound/);
  assert.match(otel, /forbiddenMarkerFound/);
  assert.match(otel, /study_room\.e2e\.trace_marker/);
  assert.match(otel, /Object\.hasOwn\(minimumInstanceSpanCounts, instanceId\)/);
  assert.match(workflow, /E2E_RESULT_PATH=\/artifacts\/graceful-api-2\.json/);
});

test('OpenTelemetry verifier allows an unchanged instance without an explicit minimum', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'study-room-otel-'));
  const traces = join(directory, 'traces.jsonl');
  const request = {
    resourceSpans: ['api-1', 'api-2'].map((instanceId) => ({
      resource: {
        attributes: [
          { key: 'service.name', value: { stringValue: 'study-room-server' } },
          { key: 'service.instance.id', value: { stringValue: instanceId } },
        ],
      },
      scopeSpans: [{ spans: [{ traceId: instanceId === 'api-1' ? 'a'.repeat(32) : 'b'.repeat(32) }] }],
    })),
  };
  await writeFile(traces, `${JSON.stringify(request)}\n`);
  const result = spawnSync(process.execPath, [resolve('server/tool/e2e-otel.mjs')], {
    encoding: 'utf8',
    env: {
      ...process.env,
      E2E_OTEL_TRACES_PATH: traces,
      E2E_OTEL_MINIMUM_INSTANCE_SPANS: JSON.stringify({ 'api-1': 0 }),
    },
  });
  assert.equal(result.status, 0, result.stderr);
});

test('OpenTelemetry verifier accepts an expected marker for the selected instance', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'study-room-otel-expected-marker-'));
  const traces = join(directory, 'traces.jsonl');
  const marker = 'graceful-run-expected';
  const request = {
    resourceSpans: ['api-1', 'api-2'].map((instanceId) => ({
      resource: {
        attributes: [
          { key: 'service.name', value: { stringValue: 'study-room-server' } },
          { key: 'service.instance.id', value: { stringValue: instanceId } },
        ],
      },
      scopeSpans: [{ spans: [{
        traceId: instanceId === 'api-1' ? 'c'.repeat(32) : 'd'.repeat(32),
        attributes: instanceId === 'api-1' ? [{
          key: 'study_room.e2e.trace_marker',
          value: { stringValue: marker },
        }] : [],
      }] }],
    })),
  };
  await writeFile(traces, `${JSON.stringify(request)}\n`);
  const result = spawnSync(process.execPath, [resolve('server/tool/e2e-otel.mjs')], {
    encoding: 'utf8',
    env: {
      ...process.env,
      E2E_OTEL_TRACES_PATH: traces,
      E2E_OTEL_EXPECTED_MARKER: marker,
      E2E_OTEL_EXPECTED_MARKER_INSTANCE: 'api-1',
    },
  });
  assert.equal(result.status, 0, result.stderr);
});

test('OpenTelemetry verifier rejects a forbidden marker before shutdown', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'study-room-otel-forbidden-marker-'));
  const traces = join(directory, 'traces.jsonl');
  const marker = 'graceful-run-forbidden';
  const request = {
    resourceSpans: ['api-1', 'api-2'].map((instanceId) => ({
      resource: {
        attributes: [
          { key: 'service.name', value: { stringValue: 'study-room-server' } },
          { key: 'service.instance.id', value: { stringValue: instanceId } },
        ],
      },
      scopeSpans: [{ spans: [{
        traceId: instanceId === 'api-1' ? 'e'.repeat(32) : 'f'.repeat(32),
        attributes: instanceId === 'api-1' ? [{
          key: 'study_room.e2e.trace_marker',
          value: { stringValue: marker },
        }] : [],
      }] }],
    })),
  };
  await writeFile(traces, `${JSON.stringify(request)}\n`);
  const result = spawnSync(process.execPath, [resolve('server/tool/e2e-otel.mjs')], {
    encoding: 'utf8',
    env: {
      ...process.env,
      E2E_OTEL_TRACES_PATH: traces,
      E2E_OTEL_FORBIDDEN_MARKER: marker,
      E2E_OTEL_FORBIDDEN_MARKER_INSTANCE: 'api-1',
    },
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /forbidden study_room\.e2e\.trace_marker/);
});
