import {
  applyE2eTraceMarker,
  e2eTraceMarkerAttribute,
  e2eTraceMarkerHeader,
} from '../src/telemetry-marker';

describe('OpenTelemetry E2E trace marker', () => {
  const marker = 'graceful-resilience-123-1-0123456789abcdef';

  it('sets a validated server span attribute in the test runtime profile', () => {
    const span = { setAttribute: jest.fn() };

    expect(applyE2eTraceMarker(span, { [e2eTraceMarkerHeader]: marker }, 'test')).toBe(true);
    expect(span.setAttribute).toHaveBeenCalledWith(e2eTraceMarkerAttribute, marker);
  });

  it.each([undefined, 'production', 'dev'])(
    'ignores the marker outside the test runtime profile (%s)',
    (runtimeProfile) => {
      const span = { setAttribute: jest.fn() };

      expect(applyE2eTraceMarker(
        span,
        { [e2eTraceMarkerHeader]: marker },
        runtimeProfile,
      )).toBe(false);
      expect(span.setAttribute).not.toHaveBeenCalled();
    },
  );

  it.each([
    ['', 'empty'],
    ['contains a space', 'invalid characters'],
    ['-starts-with-punctuation', 'invalid first character'],
    ['x'.repeat(129), 'too long'],
    [[marker], 'multiple header values'],
  ] as Array<[string | string[], string]>)('ignores %s (%s)', (value) => {
    const span = { setAttribute: jest.fn() };

    expect(applyE2eTraceMarker(span, { [e2eTraceMarkerHeader]: value }, 'test')).toBe(false);
    expect(span.setAttribute).not.toHaveBeenCalled();
  });
});
