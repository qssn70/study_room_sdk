import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { load } from 'js-yaml';

type ComposeService = {
  profiles?: string[];
  depends_on?: Record<string, { required?: boolean }>;
};

type ComposeDocument = {
  'x-api-environment': Record<string, string>;
  services: Record<string, ComposeService>;
};

describe('Compose JWKS fixture isolation', () => {
  const root = resolve(__dirname, '..', '..');
  const composeText = readFileSync(resolve(root, 'docker-compose.yml'), 'utf8');
  const compose = load(composeText) as ComposeDocument;
  const productionEnv = readFileSync(resolve(root, '.env.example'), 'utf8');
  const developmentEnv = readFileSync(resolve(root, '.env.dev.example'), 'utf8');
  const testEnv = readFileSync(resolve(root, '.env.test.example'), 'utf8');
  const seed = readFileSync(resolve(root, 'server', 'prisma', 'seed.mjs'), 'utf8');

  it('keeps fixture and seed services out of the default profile', () => {
    expect(compose.services.jwks.profiles).toEqual(['dev', 'test']);
    expect(compose.services.seed.profiles).toEqual(['dev', 'test']);
    expect(compose.services.e2e.profiles).toEqual(['test']);
    for (const apiName of ['api-1', 'api-2']) {
      const dependencies = compose.services[apiName].depends_on ?? {};
      expect(Object.keys(dependencies)).toEqual(
        expect.arrayContaining(['migrate', 'redis']),
      );
      expect(Object.keys(dependencies)).not.toEqual(
        expect.arrayContaining(['jwks', 'seed', 'e2e']),
      );
    }
  });

  it('contains no default insecure JWKS or fixture control secret', () => {
    expect(compose['x-api-environment'].STUDY_ROOM_RUNTIME_PROFILE).toContain('production');
    expect(compose['x-api-environment'].STUDY_ROOM_ALLOW_INSECURE_JWKS).toContain('false');
    expect(compose['x-api-environment'].STUDY_ROOM_ADMIN_JWKS_URL).not.toContain('http://jwks');
    expect(composeText).not.toContain('local-fixture-control');
    expect(composeText).not.toMatch(/STUDY_ROOM_ALLOW_INSECURE_JWKS:\s*["']?true/);
  });

  it('documents safe production defaults and explicit dev/test opt-ins', () => {
    expect(productionEnv).toContain('STUDY_ROOM_RUNTIME_PROFILE=production');
    expect(productionEnv).toContain('STUDY_ROOM_ALLOW_INSECURE_JWKS=false');
    expect(productionEnv).toMatch(/STUDY_ROOM_ADMIN_JWKS_URL=https:\/\//);
    expect(developmentEnv).toContain('STUDY_ROOM_RUNTIME_PROFILE=dev');
    expect(developmentEnv).toContain('STUDY_ROOM_ALLOW_INSECURE_JWKS=true');
    expect(testEnv).toContain('STUDY_ROOM_RUNTIME_PROFILE=test');
    expect(testEnv).toContain('STUDY_ROOM_ALLOW_INSECURE_JWKS=true');
  });

  it('prevents the demo seed from running outside an explicitly insecure dev/test profile', () => {
    expect(seed).toContain("!['dev', 'test'].includes(runtimeProfile)");
    expect(seed).toContain("process.env.STUDY_ROOM_ALLOW_INSECURE_JWKS !== 'true'");
  });
});
