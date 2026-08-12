import { mkdir, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';

export class GitHubApi {
  constructor({ repository, token = process.env.GITHUB_TOKEN }) {
    if (!/^[^/]+\/[^/]+$/.test(repository ?? '')) {
      throw new Error('repository must use owner/name form');
    }
    this.repository = repository;
    this.token = token;
    this.baseUrl = `https://api.github.com/repos/${repository}`;
  }

  async request(path, options = {}) {
    const url = path.startsWith('https://') ? path : `${this.baseUrl}${path}`;
    const parsedUrl = new URL(url);
    const includeAuthorization = parsedUrl.origin === new URL(this.baseUrl).origin;
    const headers = {
      accept: 'application/vnd.github+json',
      'x-github-api-version': '2022-11-28',
      'user-agent': 'study-room-release-evidence',
      ...(this.token && includeAuthorization ? { authorization: `Bearer ${this.token}` } : {}),
      ...options.headers,
    };
    const response = await fetch(url, { ...options, headers, redirect: 'follow' });
    const text = await response.text();
    if (!response.ok) {
      throw new Error(`GitHub ${options.method ?? 'GET'} ${url} returned ${response.status}: ${text}`);
    }
    return { response, text, json: text ? JSON.parse(text) : null };
  }

  async saveJson(path, outputPath) {
    const result = await this.request(path);
    await mkdir(dirname(outputPath), { recursive: true });
    await writeFile(outputPath, result.text);
    return result.json;
  }

  async download(url, outputPath) {
    const parsedUrl = new URL(url);
    const includeAuthorization = parsedUrl.origin === new URL(this.baseUrl).origin;
    const headers = {
      accept: 'application/octet-stream, image/*, application/vnd.github+json',
      'x-github-api-version': '2022-11-28',
      'user-agent': 'study-room-release-evidence',
      ...(this.token && includeAuthorization ? { authorization: `Bearer ${this.token}` } : {}),
    };
    const response = await fetch(url, { headers, redirect: 'follow' });
    if (!response.ok) {
      throw new Error(`GitHub download ${url} returned ${response.status}: ${await response.text()}`);
    }
    await mkdir(dirname(outputPath), { recursive: true });
    await writeFile(outputPath, Buffer.from(await response.arrayBuffer()));
    return response;
  }
}

export async function writeJson(path, value) {
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify(value, null, 2)}\n`);
}
