#!/usr/bin/env node
import { createHash } from 'node:crypto';
import { mkdir, readFile, readdir, stat, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';

import { goldenScenarios } from './release/required-checks.mjs';

const [baselineArgument, outputArgument] = process.argv.slice(2);
if (!baselineArgument || !outputArgument) {
  throw new Error('Usage: node tool/golden-evidence.mjs <baseline-directory> <output.json>');
}
if (process.env.STUDY_ROOM_RUN_GOLDENS !== 'true') {
  throw new Error('STUDY_ROOM_RUN_GOLDENS=true is required to create accepted Golden evidence');
}

const baselineDirectory = resolve(baselineArgument);
const outputPath = resolve(outputArgument);
const actualNames = (await readdir(baselineDirectory)).filter((name) => name.endsWith('.png')).sort();
const expectedNames = [...goldenScenarios].sort();
if (JSON.stringify(actualNames) !== JSON.stringify(expectedNames)) {
  throw new Error(`Golden baseline set differs from the declared eight scenarios: ${actualNames.join(', ')}`);
}
const baselines = [];
for (const name of goldenScenarios) {
  const path = join(baselineDirectory, name);
  const metadata = await stat(path);
  const content = await readFile(path);
  if (!metadata.isFile() || metadata.size === 0) throw new Error(`${name} is not a non-empty file`);
  if (content.subarray(0, 8).toString('hex') !== '89504e470d0a1a0a') {
    throw new Error(`${name} is not a PNG file`);
  }
  baselines.push({
    name,
    sizeBytes: metadata.size,
    sha256: createHash('sha256').update(content).digest('hex'),
  });
}
const result = {
  schemaVersion: 1,
  commitSha: process.env.GITHUB_SHA ?? null,
  runUrl: process.env.GITHUB_SERVER_URL && process.env.GITHUB_REPOSITORY && process.env.GITHUB_RUN_ID
    ? `${process.env.GITHUB_SERVER_URL}/${process.env.GITHUB_REPOSITORY}/actions/runs/${process.env.GITHUB_RUN_ID}`
    : null,
  runGoldens: true,
  scenarioCount: baselines.length,
  baselines,
};
await mkdir(dirname(outputPath), { recursive: true });
await writeFile(outputPath, `${JSON.stringify(result, null, 2)}\n`);
console.log(`Recorded ${baselines.length} Golden baselines in ${outputPath}.`);
