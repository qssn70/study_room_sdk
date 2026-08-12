import { execFileSync } from 'node:child_process';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';

const argumentsMap = new Map();
for (let index = 2; index < process.argv.length; index += 2) {
  argumentsMap.set(process.argv[index], process.argv[index + 1]);
}
const outputPath = resolve(
  argumentsMap.get('--output')
    ?? process.env.EVIDENCE_SERVICE_IMAGES_PATH
    ?? 'artifacts/service-images.json',
);
const composePsPath = argumentsMap.get('--compose-ps');

function docker(...args) {
  return execFileSync('docker', args, { encoding: 'utf8' }).trim();
}

function parseComposePs(value) {
  if (!value) return [];
  try {
    const parsed = JSON.parse(value);
    return Array.isArray(parsed) ? parsed : [parsed];
  } catch {
    return value.split(/\r?\n/).filter(Boolean).map((line) => JSON.parse(line));
  }
}

function composeImageId(row) {
  if (typeof row.Image === 'string' && row.Image.startsWith('sha256:')) {
    return row.Image;
  }
  if (typeof row.Labels !== 'string') return null;
  for (const label of row.Labels.split(',')) {
    const [name, ...parts] = label.split('=');
    if (name === 'com.docker.compose.image') {
      const value = parts.join('=');
      return value.startsWith('sha256:') ? value : null;
    }
  }
  return null;
}

const composeRows = parseComposePs(
  composePsPath
    ? await readFile(resolve(composePsPath), 'utf8')
    : docker('compose', 'ps', '--all', '--format', 'json'),
);
const services = {};
for (const row of composeRows) {
  const service = row.Service;
  const containerId = row.ID;
  if (typeof service !== 'string' || typeof containerId !== 'string' || !containerId) continue;
  let container = null;
  let containerInspectError = null;
  try {
    container = JSON.parse(docker('container', 'inspect', containerId))[0];
  } catch (error) {
    containerInspectError = error instanceof Error ? error.message : String(error);
  }
  const imageId = container?.Image ?? composeImageId(row);
  let image = null;
  let imageInspectError = null;
  if (imageId) {
    try {
      image = JSON.parse(docker('image', 'inspect', imageId))[0];
    } catch (error) {
      imageInspectError = error instanceof Error ? error.message : String(error);
    }
  }
  services[service] = {
    containerId,
    imageId,
    containerInspectError,
    repoDigests: image?.RepoDigests ?? [],
    repoTags: image?.RepoTags ?? [],
    imageInspectError,
  };
}

const api1ImageId = services['api-1']?.imageId ?? null;
const api2ImageId = services['api-2']?.imageId ?? null;
const evidence = {
  schemaVersion: 1,
  services,
  assertions: {
    apiImagesPresent: Boolean(api1ImageId && api2ImageId),
    apiImageIdsMatch: Boolean(api1ImageId && api2ImageId && api1ImageId === api2ImageId),
  },
};

await mkdir(dirname(outputPath), { recursive: true });
await writeFile(outputPath, `${JSON.stringify(evidence, null, 2)}\n`);
console.log(`Recorded image evidence for ${Object.keys(services).length} Compose services.`);
