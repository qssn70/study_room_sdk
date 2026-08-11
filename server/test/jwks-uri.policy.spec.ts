import { JwksUriPolicy, JwksUriPolicyError } from '../src/applications/jwks-uri.policy';

describe('JwksUriPolicy runtime profiles', () => {
  const policy = new JwksUriPolicy();

  beforeEach(() => {
    delete process.env.STUDY_ROOM_RUNTIME_PROFILE;
    delete process.env.STUDY_ROOM_ALLOW_INSECURE_JWKS;
  });

  it('defaults to production and rejects HTTP even when the insecure flag is set', () => {
    process.env.STUDY_ROOM_ALLOW_INSECURE_JWKS = 'true';
    expect(() => policy.assertAllowed('http://localhost/jwks')).toThrow('must use HTTPS in production');
    expect(() => policy.assertAllowed('http://jwks:4000/keys')).toThrow('must use HTTPS in production');
    expect(policy.assertAllowed('https://issuer.example/jwks').protocol).toBe('https:');
  });

  it.each(['dev', 'test'] as const)(
    'allows local HTTP only with an explicit insecure opt-in in the %s profile',
    (profile) => {
      process.env.STUDY_ROOM_RUNTIME_PROFILE = profile;
      expect(() => policy.assertAllowed('http://localhost/jwks')).toThrow(
        'STUDY_ROOM_ALLOW_INSECURE_JWKS=true',
      );
      process.env.STUDY_ROOM_ALLOW_INSECURE_JWKS = 'true';
      for (const uri of [
        'http://localhost/jwks',
        'http://127.0.0.1/jwks',
        'http://127.24.1.9/jwks',
        'http://[::1]/jwks',
        'http://jwks:4000/jwks',
      ]) {
        expect(policy.assertAllowed(uri).protocol).toBe('http:');
      }
    },
  );

  it('rejects remote HTTP and unsupported URL schemes in dev/test', () => {
    process.env.STUDY_ROOM_RUNTIME_PROFILE = 'test';
    process.env.STUDY_ROOM_ALLOW_INSECURE_JWKS = 'true';
    expect(() => policy.assertAllowed('http://remote.example/jwks')).toThrow('only for localhost');
    expect(() => policy.assertAllowed('file:///tmp/jwks.json')).toThrow('must use HTTPS');
    expect(() => policy.assertAllowed('not a URL')).toThrow('must be an absolute URL');
  });

  it('rejects unknown runtime profiles', () => {
    process.env.STUDY_ROOM_RUNTIME_PROFILE = 'staging';
    expect(() => policy.assertAllowed('https://issuer.example/jwks')).toThrow(JwksUriPolicyError);
  });
});
