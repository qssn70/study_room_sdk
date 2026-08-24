import { access, readdir, readFile } from 'node:fs/promises';
import { dirname, extname, resolve } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const ignoredDirectories = new Set([
  '.dart_tool',
  '.git',
  'build',
  'coverage',
  'doc',
  'node_modules',
]);
const markdownFiles = [];

async function collect(directory) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    if (entry.isDirectory() && ignoredDirectories.has(entry.name)) continue;
    const path = resolve(directory, entry.name);
    if (entry.isDirectory()) await collect(path);
    else if (entry.isFile() && extname(entry.name).toLowerCase() === '.md') {
      markdownFiles.push(path);
    }
  }
}

function localTarget(rawTarget) {
  const trimmed = rawTarget.trim();
  const target = trimmed.startsWith('<') && trimmed.includes('>')
    ? trimmed.slice(1, trimmed.indexOf('>'))
    : trimmed.split(/\s+(?=["'])/, 1)[0];
  if (!target
      || target.startsWith('#')
      || target.startsWith('//')
      || /^[a-z][a-z0-9+.-]*:/i.test(target)) {
    return null;
  }
  const withoutFragment = target.split('#', 1)[0].split('?', 1)[0];
  if (!withoutFragment) return null;
  try {
    return decodeURIComponent(withoutFragment);
  } catch {
    return withoutFragment;
  }
}

await collect(root);
const failures = [];
for (const file of markdownFiles.sort()) {
  const source = await readFile(file, 'utf8');
  const links = /!?\[[^\]]*\]\(([^)]+)\)/g;
  for (const match of source.matchAll(links)) {
    const target = localTarget(match[1]);
    if (target == null) continue;
    const path = target.startsWith('/')
      ? resolve(root, `.${target}`)
      : resolve(dirname(file), target);
    try {
      await access(path);
    } catch {
      const line = source.slice(0, match.index).split('\n').length;
      failures.push(`${file.slice(root.length + 1)}:${line} -> ${match[1]}`);
    }
  }
}

if (failures.length > 0) {
  throw new Error(`Broken local Markdown links:\n${failures.join('\n')}`);
}
console.log(`Validated local links in ${markdownFiles.length} Markdown files.`);
