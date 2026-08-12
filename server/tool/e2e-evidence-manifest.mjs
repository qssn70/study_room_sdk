import { createHash } from 'node:crypto';
import { readdir, readFile, stat, writeFile } from 'node:fs/promises';
import { join, relative, resolve, sep } from 'node:path';

const artifactDirectory = resolve(process.env.EVIDENCE_ARTIFACT_DIR ?? 'artifacts');
const outputPath = resolve(process.env.EVIDENCE_OUTPUT_PATH ?? join(artifactDirectory, 'evidence-manifest.json'));
const imagesPath = resolve(
  process.env.EVIDENCE_IMAGES_PATH ?? join(artifactDirectory, 'service-images.json'),
);
const startedAtPath = resolve(
  process.env.EVIDENCE_STARTED_AT_PATH ?? join(artifactDirectory, 'job-started-at-epoch'),
);
const scenario = process.env.EVIDENCE_SCENARIO ?? 'unknown';

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

async function sha256(path) {
  return createHash('sha256').update(await readFile(path)).digest('hex');
}

async function readImages() {
  try {
    const evidence = JSON.parse(await readFile(imagesPath, 'utf8'));
    const services = evidence && typeof evidence === 'object' && !Array.isArray(evidence)
      ? (evidence.services ?? {})
      : {};
    const entries = Object.entries(services).map(([service, image]) => ({ service, ...image }));
    return {
      entries,
      assertions: evidence?.assertions ?? null,
      unavailableReason: entries.length === 0 ? 'No Compose images were available to inspect' : null,
    };
  } catch (error) {
    return {
      entries: [],
      assertions: null,
      unavailableReason: error instanceof Error ? error.message : String(error),
    };
  }
}

async function readStartedAt() {
  try {
    const value = Number((await readFile(startedAtPath, 'utf8')).trim());
    if (!Number.isSafeInteger(value) || value <= 0) throw new Error('invalid epoch value');
    return { epochSeconds: value, unavailableReason: null };
  } catch (error) {
    return {
      epochSeconds: null,
      unavailableReason: error instanceof Error ? error.message : String(error),
    };
  }
}

const endedAtEpochSeconds = Math.floor(Date.now() / 1000);
const startedAt = await readStartedAt();
const images = await readImages();
const artifactFiles = (await filesUnder(artifactDirectory))
  .filter((path) => resolve(path) !== outputPath)
  .sort();
const artifacts = [];
for (const path of artifactFiles) {
  const metadata = await stat(path);
  artifacts.push({
    path: relative(artifactDirectory, path).split(sep).join('/'),
    sizeBytes: metadata.size,
    sha256: await sha256(path),
  });
}

const serverUrl = process.env.GITHUB_SERVER_URL;
const repository = process.env.GITHUB_REPOSITORY;
const runId = process.env.GITHUB_RUN_ID;
const runUrl = serverUrl && repository && runId
  ? `${serverUrl}/${repository}/actions/runs/${runId}`
  : null;
const commitSha = process.env.GITHUB_SHA ?? null;
const manifest = {
  schemaVersion: 1,
  scenario,
  commitSha,
  commitShaUnavailableReason: commitSha === null ? 'GITHUB_SHA is not available' : null,
  runUrl,
  runUrlUnavailableReason: runUrl === null
    ? 'GITHUB_SERVER_URL, GITHUB_REPOSITORY, or GITHUB_RUN_ID is not available'
    : null,
  runIdentity: {
    runId: runId ?? null,
    runAttempt: process.env.GITHUB_RUN_ATTEMPT ?? null,
    workflow: process.env.GITHUB_WORKFLOW ?? null,
    job: process.env.GITHUB_JOB ?? null,
  },
  timing: {
    startedAt: startedAt.epochSeconds === null
      ? null
      : new Date(startedAt.epochSeconds * 1000).toISOString(),
    endedAt: new Date(endedAtEpochSeconds * 1000).toISOString(),
    durationSeconds: startedAt.epochSeconds === null
      ? null
      : Math.max(0, endedAtEpochSeconds - startedAt.epochSeconds),
    unavailableReason: startedAt.unavailableReason,
  },
  images,
  artifacts,
};

await writeFile(outputPath, `${JSON.stringify(manifest, null, 2)}\n`);
console.log(`Evidence manifest recorded ${artifacts.length} files for ${scenario}.`);
