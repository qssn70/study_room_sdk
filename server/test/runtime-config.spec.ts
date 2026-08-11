import { trustProxyHops } from '../src/common/runtime-config';

describe('runtime configuration', () => {
  it.each([
    [undefined, 0],
    ['', 0],
    ['0', 0],
    ['1', 1],
    ['12', 12],
  ])('parses a valid trust-proxy hop count (%s)', (value, expected) => {
    expect(trustProxyHops(value)).toBe(expected);
  });

  it.each(['-1', '1.5', ' 1', 'abc', '9007199254740992'])(
    'rejects an unsafe trust-proxy hop count (%s)',
    (value) => {
      expect(() => trustProxyHops(value)).toThrow(
        'STUDY_ROOM_TRUST_PROXY_HOPS must be a non-negative safe integer',
      );
    },
  );
});
