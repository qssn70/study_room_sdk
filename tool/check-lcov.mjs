import { readFile } from 'node:fs/promises';

const [path, lineMinimumText, branchMinimumText] = process.argv.slice(2);
if (!path || !lineMinimumText) {
  throw new Error('Usage: node tool/check-lcov.mjs <lcov.info> <line-minimum> [branch-minimum]');
}
const source = await readFile(path, 'utf8');
const lines = source.split(/\r?\n/);
const lineRecords = lines.filter((line) => line.startsWith('DA:'));
const lineHits = lineRecords.filter((line) => Number(line.split(',')[1]) > 0).length;
const branchRecords = lines.filter((line) => line.startsWith('BRDA:'));
const branchHits = branchRecords.filter((line) => {
  const hits = line.split(',')[3];
  return hits !== '-' && Number(hits) > 0;
}).length;

function assertCoverage(label, hits, found, minimum) {
  if (found === 0) throw new Error(`${label} coverage data is missing`);
  const percent = hits / found * 100;
  console.log(`${label}: ${hits}/${found} (${percent.toFixed(2)}%, required ${minimum}%)`);
  if (percent + Number.EPSILON < minimum) process.exitCode = 1;
}

assertCoverage('lines', lineHits, lineRecords.length, Number(lineMinimumText));
if (branchMinimumText !== undefined) {
  assertCoverage('branches', branchHits, branchRecords.length, Number(branchMinimumText));
}
