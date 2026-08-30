import { access, mkdir, mkdtemp, readFile, rm, stat, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { createServer as createNetServer } from 'node:net';
import { basename, extname, resolve, sep } from 'node:path';
import { spawn } from 'node:child_process';
import { tmpdir } from 'node:os';

import { closeServer, terminateProcess } from './browser-process.mjs';

const root = resolve(
  process.env.E2E_BROWSER_ROOT
    ?? 'artifacts/browser',
);
const resultPath = resolve(
  process.env.E2E_BROWSER_RESULT_PATH
    ?? 'artifacts/browser-result.json',
);
const logPath = resolve(
  process.env.E2E_BROWSER_LOG_PATH
    ?? 'artifacts/browser-console.json',
);
const browserPort = Number(process.env.E2E_BROWSER_PORT ?? 4173);
const timeoutMs = Number(process.env.E2E_BROWSER_TIMEOUT_MS ?? 90_000);
const browserUrl = `http://127.0.0.1:${browserPort}/`;
const logs = [];
let reportedResult = null;

const contentTypes = new Map([
  ['.html', 'text/html; charset=utf-8'],
  ['.js', 'text/javascript; charset=utf-8'],
  ['.map', 'application/json; charset=utf-8'],
]);

function delay(milliseconds) {
  return new Promise((resolveDelay) => setTimeout(resolveDelay, milliseconds));
}

async function freePort() {
  const server = createNetServer();
  await new Promise((resolveListen, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolveListen);
  });
  const address = server.address();
  await new Promise((resolveClose) => server.close(resolveClose));
  return address.port;
}

async function chromeExecutable() {
  const candidates = [
    process.env.CHROME_EXECUTABLE,
    process.env.GOOGLE_CHROME_BIN,
    '/usr/bin/google-chrome',
    '/usr/bin/google-chrome-stable',
    '/usr/bin/chromium',
    '/usr/bin/chromium-browser',
  ].filter(Boolean);
  for (const candidate of candidates) {
    try {
      await access(candidate);
      return candidate;
    } catch {
      // Continue through the supported CI Chrome locations.
    }
  }
  throw new Error(`Chrome executable not found; checked ${candidates.join(', ')}`);
}

async function staticServer() {
  const rootPrefix = `${root}${sep}`;
  const server = createServer(async (request, response) => {
    try {
      const url = new URL(request.url ?? '/', browserUrl);
      const relative = decodeURIComponent(url.pathname === '/' ? '/index.html' : url.pathname);
      const path = resolve(root, `.${relative}`);
      if (path !== root && !path.startsWith(rootPrefix)) {
        response.writeHead(403).end('Forbidden');
        return;
      }
      if (!(await stat(path)).isFile()) {
        response.writeHead(404).end('Not found');
        return;
      }
      response.writeHead(200, {
        'content-type': contentTypes.get(extname(path)) ?? 'application/octet-stream',
        'cache-control': 'no-store',
      });
      response.end(await readFile(path));
    } catch {
      response.writeHead(404).end('Not found');
    }
  });
  await new Promise((resolveListen, reject) => {
    server.once('error', reject);
    server.listen(browserPort, '127.0.0.1', resolveListen);
  });
  return server;
}

async function waitForPage(debuggingPort, deadline) {
  while (Date.now() < deadline) {
    try {
      const response = await fetch(`http://127.0.0.1:${debuggingPort}/json/list`);
      if (response.ok) {
        const pages = await response.json();
        const page = pages.find((item) => item.type === 'page');
        if (page?.webSocketDebuggerUrl) return page;
      }
    } catch {
      // Chrome is still starting.
    }
    await delay(250);
  }
  throw new Error('Chrome DevTools endpoint did not become ready');
}

function cdp(webSocketUrl) {
  const socket = new WebSocket(webSocketUrl);
  const pending = new Map();
  let nextId = 1;
  const opened = new Promise((resolveOpen, reject) => {
    socket.addEventListener('open', resolveOpen, { once: true });
    socket.addEventListener('error', reject, { once: true });
  });
  socket.addEventListener('message', (event) => {
    const message = JSON.parse(event.data);
    if (message.id != null) {
      const handler = pending.get(message.id);
      if (!handler) return;
      pending.delete(message.id);
      if (message.error) handler.reject(new Error(JSON.stringify(message.error)));
      else handler.resolve(message.result);
      return;
    }
    if (message.method === 'Runtime.consoleAPICalled') {
      logs.push({
        type: 'console',
        level: message.params.type,
        values: message.params.args.map((argument) => argument.value ?? argument.description),
      });
    }
    if (message.method === 'Runtime.exceptionThrown') {
      logs.push({
        type: 'exception',
        details: message.params.exceptionDetails,
      });
    }
  });
  return {
    opened,
    async send(method, params = {}) {
      await opened;
      const id = nextId++;
      const result = new Promise((resolveResult, reject) => {
        pending.set(id, { resolve: resolveResult, reject });
      });
      socket.send(JSON.stringify({ id, method, params }));
      return result;
    },
    close() {
      socket.close();
    },
  };
}

async function waitForResult(client, deadline) {
  await client.send('Runtime.enable');
  while (Date.now() < deadline) {
    const evaluation = await client.send('Runtime.evaluate', {
      expression: 'globalThis.__studyRoomE2eResult ?? null',
      returnByValue: true,
    });
    const value = evaluation.result?.value;
    if (typeof value === 'string' && value.length > 0) {
      return JSON.parse(value);
    }
    await delay(500);
  }
  throw new Error('Browser SDK E2E did not publish a result before timeout');
}

async function main() {
  await access(resolve(root, 'index.html'));
  await access(resolve(root, 'main.js'));
  await mkdir(resolve(resultPath, '..'), { recursive: true });
  await mkdir(resolve(logPath, '..'), { recursive: true });
  const server = await staticServer();
  const debuggingPort = await freePort();
  const profile = await mkdtemp(resolve(tmpdir(), 'study-room-chrome-'));
  const executable = await chromeExecutable();
  const chrome = spawn(executable, [
    '--headless=new',
    '--no-sandbox',
    '--disable-dev-shm-usage',
    '--disable-background-networking',
    `--remote-debugging-port=${debuggingPort}`,
    `--user-data-dir=${profile}`,
    browserUrl,
  ], { stdio: ['ignore', 'pipe', 'pipe'] });
  chrome.stdout.on('data', (value) => logs.push({ type: 'chrome-stdout', value: value.toString() }));
  chrome.stderr.on('data', (value) => logs.push({ type: 'chrome-stderr', value: value.toString() }));
  const deadline = Date.now() + timeoutMs;
  let client;
  try {
    const page = await waitForPage(debuggingPort, deadline);
    client = cdp(page.webSocketDebuggerUrl);
    reportedResult = await waitForResult(client, deadline);
    await writeFile(resultPath, `${JSON.stringify(reportedResult, null, 2)}\n`);
    if (reportedResult.success !== true) {
      throw new Error(`Browser SDK E2E failed: ${reportedResult.error ?? 'unknown error'}`);
    }
    console.log(`Chrome SDK E2E passed: ${JSON.stringify(reportedResult.assertions)}`);
  } finally {
    client?.close();
    const cleanupErrors = [];
    try {
      await terminateProcess(chrome);
    } catch (error) {
      chrome.unref();
      cleanupErrors.push(error);
    }
    try {
      await closeServer(server);
    } catch (error) {
      cleanupErrors.push(error);
    }
    try {
      await rm(profile, {
        recursive: true,
        force: true,
        maxRetries: 5,
        retryDelay: 100,
      });
    } catch (error) {
      cleanupErrors.push(error);
    }
    for (const error of cleanupErrors) {
      logs.push({
        type: 'cleanup-error',
        value: error?.stack ?? error?.message ?? String(error),
      });
    }
    await writeFile(logPath, `${JSON.stringify({
      schemaVersion: 1,
      scenario: 'real-chrome-sdk-cors-socketio',
      page: browserUrl,
      result: reportedResult,
      logs,
    }, null, 2)}\n`);
    if (cleanupErrors.length > 0) {
      console.warn(`Chrome SDK E2E cleanup warning: ${cleanupErrors
        .map((error) => error?.message ?? String(error))
        .join('; ')}`);
    }
  }
}

await main().catch(async (error) => {
  if (reportedResult == null) {
    await mkdir(resolve(resultPath, '..'), { recursive: true });
    await writeFile(resultPath, `${JSON.stringify({
      schemaVersion: 1,
      scenario: 'real-chrome-sdk-cors-socketio',
      success: false,
      error: error.stack ?? error.message,
    }, null, 2)}\n`);
  }
  console.error(error);
  process.exitCode = 1;
});
