import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { resolve } from 'node:path';

async function availablePort(): Promise<number> {
  const server = createServer();
  await new Promise<void>((resolveListen, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => resolveListen());
  });
  const address = server.address();
  if (address === null || typeof address === 'string') throw new Error('Could not allocate a test port');
  await new Promise<void>((resolveClose, reject) => server.close((error) => (
    error ? reject(error) : resolveClose()
  )));
  return address.port;
}

async function waitUntilReady(url: string): Promise<void> {
  const deadline = Date.now() + 10_000;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(`${url}/health`);
      if (response.ok) return;
    } catch {
      // The fixture process may still be starting.
    }
    await new Promise((resolveDelay) => setTimeout(resolveDelay, 50));
  }
  throw new Error('Development JWKS fixture did not become ready');
}

describe('Development JWKS token CORS', () => {
  it('allows credential-free browser token requests without exposing test controls', async () => {
    const port = await availablePort();
    const fixture = spawn(process.execPath, [resolve(__dirname, '..', 'tool', 'dev-jwks.mjs')], {
      env: {
        ...process.env,
        PORT: `${port}`,
        E2E_FIXTURE_CONTROL_TOKEN: 'cors-test-control',
      },
      stdio: 'ignore',
    });
    const base = `http://127.0.0.1:${port}`;
    try {
      await waitUntilReady(base);
      const preflight = await fetch(`${base}/token`, {
        method: 'OPTIONS',
        headers: {
          origin: 'http://localhost:8080',
          'access-control-request-method': 'POST',
          'access-control-request-headers': 'content-type',
        },
      });
      expect(preflight.status).toBe(204);
      expect(preflight.headers.get('access-control-allow-origin')).toBe('*');
      expect(preflight.headers.get('access-control-allow-methods')).toContain('POST');
      expect(preflight.headers.get('access-control-allow-headers')).toContain('content-type');
      expect(preflight.headers.get('access-control-allow-credentials')).toBeNull();

      const token = await fetch(`${base}/token`, {
        method: 'POST',
        headers: { origin: 'http://localhost:8080', 'content-type': 'application/json' },
        body: JSON.stringify({ sub: 'browser-user', displayName: 'Browser User' }),
      });
      expect(token.status).toBe(200);
      expect(token.headers.get('access-control-allow-origin')).toBe('*');
      expect(token.headers.get('access-control-allow-credentials')).toBeNull();
      await expect(token.json()).resolves.toMatchObject({
        accessToken: expect.any(String),
        expiresAt: expect.any(String),
      });

      const invalidToken = await fetch(`${base}/token`, {
        method: 'POST',
        headers: { origin: 'http://localhost:8080', 'content-type': 'application/json' },
        body: '{',
      });
      expect(invalidToken.status).toBe(400);
      expect(invalidToken.headers.get('access-control-allow-origin')).toBe('*');

      const control = await fetch(`${base}/__test/keys/demo/rotate`, {
        method: 'POST',
        headers: {
          origin: 'http://localhost:8080',
          authorization: 'Bearer cors-test-control',
        },
      });
      expect(control.status).toBe(200);
      expect(control.headers.get('access-control-allow-origin')).toBeNull();

      const controlPreflight = await fetch(`${base}/__test/keys/demo/rotate`, {
        method: 'OPTIONS',
        headers: { origin: 'http://localhost:8080' },
      });
      expect(controlPreflight.status).toBe(404);
      expect(controlPreflight.headers.get('access-control-allow-origin')).toBeNull();
    } finally {
      fixture.kill('SIGTERM');
      await new Promise<void>((resolveExit) => {
        if (fixture.exitCode !== null) resolveExit();
        else fixture.once('exit', () => resolveExit());
      });
    }
  });
});
