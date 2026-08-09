import {
  generateKeyPairSync,
  randomUUID,
  sign,
  timingSafeEqual,
} from 'node:crypto';
import { createServer } from 'node:http';

const port = Number(process.env.PORT ?? 4000);
const fixtureControlToken = process.env.E2E_FIXTURE_CONTROL_TOKEN ?? '';
const allowShortLivedTokens = process.env.E2E_ALLOW_SHORT_LIVED_TOKENS === 'true';

function signingKey(prefix, algorithm) {
  const kid = `${prefix}-${randomUUID()}`;
  const pair = algorithm === 'ES256'
    ? generateKeyPairSync('ec', { namedCurve: 'P-256' })
    : generateKeyPairSync('rsa', { modulusLength: 2048 });
  return {
    algorithm,
    privateKey: pair.privateKey,
    publicJwk: {
      ...pair.publicKey.export({ format: 'jwk' }),
      use: 'sig',
      alg: algorithm,
      kid,
    },
    kid,
  };
}

function keyRing(name, algorithm = 'RS256') {
  const initial = signingKey(name, algorithm);
  return { name, algorithm, current: initial, published: [initial] };
}

const rings = new Map([
  ['demo', keyRing('demo', 'RS256')],
  ['demo-alt', keyRing('demo-alt', 'ES256')],
  ['admin', keyRing('admin', 'RS256')],
]);

function encode(value) {
  return Buffer.from(JSON.stringify(value)).toString('base64url');
}

function jwt(ring, payload, scenario = 'valid') {
  const key = ring.current;
  const headerKid = scenario === 'unknown-kid' ? `unknown-${key.kid}` : key.kid;
  const signingInput = `${encode({ alg: key.algorithm, typ: 'JWT', kid: headerKid })}.${encode(payload)}`;
  const signature = key.algorithm === 'ES256'
    ? sign('SHA256', Buffer.from(signingInput), { key: key.privateKey, dsaEncoding: 'ieee-p1363' })
    : sign('RSA-SHA256', Buffer.from(signingInput), key.privateKey);
  return `${signingInput}.${signature.toString('base64url')}`;
}

function json(response, status, value) {
  const body = JSON.stringify(value);
  response.writeHead(status, {
    'content-type': 'application/json',
    'content-length': Buffer.byteLength(body),
    'cache-control': 'no-store',
  });
  response.end(body);
}

async function bodyFor(request) {
  const chunks = [];
  let length = 0;
  for await (const chunk of request) {
    length += chunk.length;
    if (length > 16_384) throw new Error('Request body is too large');
    chunks.push(chunk);
  }
  return chunks.length ? JSON.parse(Buffer.concat(chunks).toString('utf8')) : {};
}

function controlled(request) {
  if (!fixtureControlToken) return false;
  const authorization = request.headers.authorization ?? '';
  const supplied = authorization.startsWith('Bearer ') ? authorization.slice(7) : '';
  const expected = Buffer.from(fixtureControlToken);
  const actual = Buffer.from(supplied);
  return expected.length === actual.length && timingSafeEqual(expected, actual);
}

function tokenLifetime(input, scenario) {
  if (scenario === 'expired') return -60;
  const minimum = allowShortLivedTokens ? 1 : 60;
  return Math.min(Math.max(Number(input.lifetimeSeconds ?? 3600), minimum), 86_400);
}

function tokenPayload(input) {
  const type = input.type === 'admin' ? 'admin' : 'user';
  const appId = String(input.appId ?? 'demo');
  const ring = rings.get(type === 'admin' ? 'admin' : appId);
  if (!ring || (type === 'user' && appId === 'admin')) throw new Error('Unknown token application');

  const allowedScenarios = new Set([
    'valid', 'expired', 'wrong-issuer', 'wrong-audience', 'wrong-app-id',
    'unknown-kid', 'missing-scope',
  ]);
  const scenario = String(input.scenario ?? 'valid');
  if (!allowedScenarios.has(scenario)) throw new Error('Unknown token scenario');

  const now = Math.floor(Date.now() / 1000);
  const exp = now + tokenLifetime(input, scenario);
  if (type === 'admin') {
    const payload = {
      sub: String(input.sub ?? 'local-admin'),
      iss: scenario === 'wrong-issuer' ? 'http://invalid-issuer.test/admin' : 'http://jwks:4000/admin',
      aud: scenario === 'wrong-audience' ? 'invalid-admin-audience' : 'study-room-admin',
      scope: scenario === 'missing-scope' ? 'metrics:read' : 'apps:manage metrics:read',
      iat: now,
      exp,
    };
    return { ring, payload, scenario, exp };
  }

  const payload = {
    sub: String(input.sub ?? 'user-1'),
    appId: scenario === 'wrong-app-id' ? (appId === 'demo' ? 'demo-alt' : 'demo') : appId,
    displayName: String(input.displayName ?? 'Demo User'),
    avatarUrl: String(input.avatarUrl ?? ''),
    iss: scenario === 'wrong-issuer' ? `http://invalid-issuer.test/apps/${appId}` : `http://jwks:4000/apps/${appId}`,
    aud: scenario === 'wrong-audience' ? 'invalid-study-room-audience' : 'study-room-api',
    iat: now,
    exp,
  };
  return { ring, payload, scenario, exp };
}

function keyMetadata(ring) {
  return { currentKid: ring.current.kid, publishedKids: ring.published.map((key) => key.kid) };
}

createServer(async (request, response) => {
  try {
    const url = new URL(request.url ?? '/', `http://${request.headers.host ?? 'localhost'}`);
    if (request.method === 'GET' && url.pathname === '/health') {
      return json(response, 200, { status: 'ok' });
    }

    const applicationJwks = url.pathname.match(/^\/apps\/([^/]+)\/jwks\.json$/);
    if (request.method === 'GET' && applicationJwks) {
      const ring = rings.get(decodeURIComponent(applicationJwks[1]));
      return ring
        ? json(response, 200, { keys: ring.published.map((key) => key.publicJwk) })
        : json(response, 404, { error: 'unknown_application' });
    }
    if (request.method === 'GET' && url.pathname === '/admin/jwks.json') {
      const ring = rings.get('admin');
      return json(response, 200, { keys: ring.published.map((key) => key.publicJwk) });
    }

    if (request.method === 'POST' && url.pathname === '/token') {
      const input = await bodyFor(request);
      const { ring, payload, scenario, exp } = tokenPayload(input);
      return json(response, 200, {
        accessToken: jwt(ring, payload, scenario),
        expiresAt: new Date(exp * 1000).toISOString(),
        kid: scenario === 'unknown-kid' ? `unknown-${ring.current.kid}` : ring.current.kid,
      });
    }

    const control = url.pathname.match(/^\/__test\/keys\/([^/]+)\/(rotate|retire)$/);
    if (request.method === 'POST' && control) {
      if (!controlled(request)) return json(response, 401, { error: 'fixture_control_required' });
      const target = decodeURIComponent(control[1]);
      const action = control[2];
      const ring = rings.get(target);
      if (!ring) return json(response, 404, { error: 'unknown_key_ring' });
      if (action === 'rotate') {
        const next = signingKey(ring.name, ring.algorithm);
        ring.published.push(next);
        ring.current = next;
      } else {
        ring.published = [ring.current];
      }
      return json(response, 200, keyMetadata(ring));
    }

    json(response, 404, { error: 'not_found' });
  } catch (error) {
    json(response, 400, { error: error instanceof Error ? error.message : 'invalid_request' });
  }
}).listen(port, '0.0.0.0', () => {
  console.log(`Development-only JWKS fixture listening on :${port}`);
});
