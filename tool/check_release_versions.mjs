import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const expected = process.argv[2]
  ?? process.env.GITHUB_REF_NAME?.replace(/^v/, '')
  ?? '0.4.1';

const jsonVersion = async (path) => JSON.parse(
  await readFile(resolve(root, path), 'utf8'),
).version;
const yamlVersion = async (path) => {
  const value = await readFile(resolve(root, path), 'utf8');
  return value.match(/^version:\s*([^\s]+)$/m)?.[1];
};
const content = async (path) => readFile(resolve(root, path), 'utf8');

const versions = new Map([
  ['root package', await jsonVersion('package.json')],
  ['server package', await jsonVersion('server/package.json')],
  ['SDK package', await yamlVersion('packages/study_room_sdk/pubspec.yaml')],
  ['UI package', await yamlVersion('packages/study_room_ui/pubspec.yaml')],
  ['example app', await yamlVersion('apps/example_flutter/pubspec.yaml')],
  ['UI example', await yamlVersion('packages/study_room_ui/example/pubspec.yaml')],
]);

const openapi = await content('contracts/openapi.yaml');
versions.set('OpenAPI contract', openapi.match(/^\s{2}version:\s*([^\s]+)$/m)?.[1]);
const generatedDart = await content(
  'packages/study_room_sdk/lib/src/generated_contract.dart',
);
versions.set(
  'generated Dart contract',
  generatedDart.match(/studyRoomContractVersion = ["']([^"']+)["']/)?.[1],
);
const generatedTypescript = await content('server/src/generated/contract-types.ts');
versions.set(
  'generated TypeScript contract',
  generatedTypescript.match(/contractVersion = ["']([^"']+)["']/)?.[1],
);

const realtime = JSON.parse(await content('contracts/realtime-events.schema.json'));
if (realtime.properties?.schemaVersion?.const !== 1) {
  throw new Error('Realtime schemaVersion must remain 1 for the 0.4.1 release');
}

const mismatches = [...versions].filter(([, version]) => version !== expected);
if (mismatches.length > 0) {
  throw new Error([
    `Release version mismatch; expected ${expected}:`,
    ...mismatches.map(([name, version]) => `- ${name}: ${version ?? 'missing'}`),
  ].join('\n'));
}

if (process.env.GITHUB_REF_TYPE === 'tag'
    && process.env.GITHUB_REF_NAME !== `v${expected}`) {
  throw new Error(
    `Release tag ${process.env.GITHUB_REF_NAME} does not match v${expected}`,
  );
}

console.log(`Release versions are aligned at ${expected}; realtime schemaVersion is 1.`);
