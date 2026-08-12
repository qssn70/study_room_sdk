#!/usr/bin/env node
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';

import { GitHubApi } from './release/github-api.mjs';
import { requiredChecks } from './release/required-checks.mjs';
import { buildRuleset, rulesetName, validateRuleset } from './release/ruleset.mjs';

function argumentsFor(values) {
  const options = { apply: false, repository: process.env.GITHUB_REPOSITORY, output: null };
  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (value === '--apply') options.apply = true;
    else if (value === '--dry-run') options.apply = false;
    else if (value === '--repository') options.repository = values[++index];
    else if (value === '--output') options.output = values[++index];
    else throw new Error(`Unknown argument: ${value}`);
  }
  return options;
}

function integrationFor(checkRuns) {
  const byName = new Map();
  for (const check of checkRuns) {
    const current = byName.get(check.name);
    if (!current || check.id > current.id) byName.set(check.name, check);
  }
  const missing = requiredChecks.filter((name) => !byName.has(name));
  if (missing.length) {
    throw new Error(`Required checks have not run on the default branch: ${missing.join(', ')}`);
  }
  const integrationIds = new Set(
    requiredChecks.map((name) => {
      const check = byName.get(name);
      if (check.app?.slug !== 'github-actions' || !Number.isSafeInteger(check.app?.id)) {
        throw new Error(`${name} is not owned by the GitHub Actions app`);
      }
      if (check.status !== 'completed' || check.conclusion !== 'success') {
        throw new Error(`${name} is not successful on the default branch`);
      }
      return check.app.id;
    }),
  );
  if (integrationIds.size !== 1) {
    throw new Error('Required checks are owned by more than one GitHub integration');
  }
  return [...integrationIds][0];
}

const options = argumentsFor(process.argv.slice(2));
if (!options.repository) throw new Error('--repository owner/name is required');
if (options.apply && !process.env.GITHUB_TOKEN) {
  throw new Error('GITHUB_TOKEN with Administration: write is required for --apply');
}

const api = new GitHubApi({ repository: options.repository });
const repository = (await api.request('')).json;
if (repository.default_branch !== 'main') {
  throw new Error(`Repository default branch is ${repository.default_branch}, expected main`);
}
const branch = (await api.request(`/branches/${encodeURIComponent(repository.default_branch)}`)).json;
const checkRuns = (await api.request(
  `/commits/${branch.commit.sha}/check-runs?per_page=100`,
)).json.check_runs;
const integrationId = integrationFor(checkRuns);
const desired = buildRuleset(integrationId);
const existingRulesets = (await api.request('/rulesets?per_page=100')).json;
const namedRulesets = existingRulesets.filter((ruleset) => ruleset.name === rulesetName);
if (namedRulesets.length > 1) throw new Error(`More than one ${rulesetName} ruleset exists`);
const existing = namedRulesets[0];

let readBack;
let readBackValidationError = null;
if (options.apply) {
  const path = existing ? `/rulesets/${existing.id}` : '/rulesets';
  const method = existing ? 'PUT' : 'POST';
  const applied = await api.request(path, {
    method,
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(desired),
  });
  readBack = (await api.request(`/rulesets/${applied.json.id}`)).json;
  validateRuleset(readBack, integrationId);
} else {
  readBack = existing
    ? (await api.request(`/rulesets/${existing.id}`)).json
    : null;
  if (readBack) {
    try {
      validateRuleset(readBack, integrationId);
    } catch (error) {
      readBackValidationError = error.message;
    }
  }
}

const result = {
  schemaVersion: 1,
  mode: options.apply ? 'apply' : 'dry-run',
  repository: options.repository,
  defaultBranch: repository.default_branch,
  defaultBranchSha: branch.commit.sha,
  integration: { id: integrationId, slug: 'github-actions' },
  existingRulesetId: existing?.id ?? null,
  desired,
  readBack,
  readBackValid: readBack === null ? null : readBackValidationError === null,
  readBackValidationError,
};
const serialized = `${JSON.stringify(result, null, 2)}\n`;
if (options.output) {
  const output = resolve(options.output);
  await mkdir(dirname(output), { recursive: true });
  await writeFile(output, serialized);
}
process.stdout.write(serialized);
if (readBackValidationError) process.exitCode = 1;
