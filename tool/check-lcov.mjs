import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';

const arguments_ = process.argv.slice(2);
const outputIndex = arguments_.indexOf('--output');
if (outputIndex !== -1 && arguments_.indexOf('--output', outputIndex + 1) !== -1) {
  throw new Error('--output may only be supplied once');
}
const outputPath = outputIndex === -1 ? null : arguments_[outputIndex + 1];
if (outputIndex !== -1 && (!outputPath || outputPath.startsWith('--'))) {
  throw new Error('--output requires a file path');
}
if (outputIndex !== -1) arguments_.splice(outputIndex, 2);
const [path, lineMinimumText, branchMinimumText] = arguments_;
if (!path || !lineMinimumText || arguments_.length > 3) {
  throw new Error(
    'Usage: node tool/check-lcov.mjs <lcov.info> <line-minimum> [branch-minimum] [--output summary.json]',
  );
}
function minimum(value, label) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0 || parsed > 100) {
    throw new Error(`${label} minimum must be a number from 0 through 100`);
  }
  return parsed;
}

const lineMinimum = minimum(lineMinimumText, 'Line');
const branchMinimum = branchMinimumText === undefined
  ? null
  : minimum(branchMinimumText, 'Branch');
const source = await readFile(path, 'utf8');
const lines = source.split(/\r?\n/);
const lineRecords = lines.filter((line) => line.startsWith('DA:'));
const lineHits = lineRecords.filter((line) => Number(line.split(',')[1]) > 0).length;
const branchRecords = lines.filter((line) => line.startsWith('BRDA:'));
const branchHits = branchRecords.filter((line) => {
  const hits = line.split(',')[3];
  return hits !== '-' && Number(hits) > 0;
}).length;

function coverage(label, hits, found, minimum) {
  if (found === 0) throw new Error(`${label} coverage data is missing`);
  const percent = hits / found * 100;
  console.log(`${label}: ${hits}/${found} (${percent.toFixed(2)}%, required ${minimum}%)`);
  return { label, hits, found, percent, minimum, passed: percent + Number.EPSILON >= minimum };
}

const results = [coverage('lines', lineHits, lineRecords.length, lineMinimum)];
if (branchMinimum !== null) {
  results.push(coverage('branches', branchHits, branchRecords.length, branchMinimum));
}
if (outputPath) {
  const output = resolve(outputPath);
  await mkdir(dirname(output), { recursive: true });
  await writeFile(output, `${JSON.stringify({
    schemaVersion: 1,
    commitSha: process.env.GITHUB_SHA ?? null,
    runUrl: process.env.GITHUB_SERVER_URL && process.env.GITHUB_REPOSITORY && process.env.GITHUB_RUN_ID
      ? `${process.env.GITHUB_SERVER_URL}/${process.env.GITHUB_REPOSITORY}/actions/runs/${process.env.GITHUB_RUN_ID}`
      : null,
    source: path.replaceAll('\\', '/'),
    results,
    passed: results.every((result) => result.passed),
  }, null, 2)}\n`);
}
if (results.some((result) => !result.passed)) process.exitCode = 1;
