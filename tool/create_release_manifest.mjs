import { createHash } from 'node:crypto';
import { readFile, readdir, writeFile } from 'node:fs/promises';
import { basename, resolve } from 'node:path';

const output = resolve(process.argv[2] ?? 'artifacts/candidate/version-manifest.json');
const directory = resolve(output, '..');
const version = JSON.parse(await readFile(resolve('package.json'), 'utf8')).version;
const realtime = JSON.parse(
  await readFile(resolve('contracts/realtime-events.schema.json'), 'utf8'),
);
const files = [];
for (const name of (await readdir(directory)).sort()) {
  if (name === basename(output) || name === 'SHA256SUMS') continue;
  const data = await readFile(resolve(directory, name));
  files.push({
    name,
    sizeBytes: data.length,
    sha256: createHash('sha256').update(data).digest('hex'),
  });
}

const manifest = {
  schemaVersion: 1,
  version,
  tag: process.env.GITHUB_REF_NAME ?? `v${version}`,
  commitSha: process.env.GITHUB_SHA ?? null,
  generatedAt: new Date().toISOString(),
  contractVersion: version,
  realtimeSchemaVersion: realtime.properties?.schemaVersion?.const,
  exampleArtifacts: {
    classification: 'unsigned example smoke builds',
    attachedToRelease: false,
  },
  publication: {
    pubDev: 'manual-approval-required',
    imagePush: 'manual-approval-required',
    finalizeRelease: 'manual-approval-required',
    productionDeployment: 'manual-approval-required',
  },
  files,
};
await writeFile(output, `${JSON.stringify(manifest, null, 2)}\n`);
console.log(`Wrote ${output}`);
