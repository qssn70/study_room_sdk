export const e2eTraceMarkerHeader = 'x-study-room-e2e-trace-marker';
export const e2eTraceMarkerAttribute = 'study_room.e2e.trace_marker';

const e2eTraceMarkerPattern = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/;

type TraceMarkerHeaders = Record<string, string | string[] | undefined>;
type TraceMarkerSpan = {
  setAttribute(name: string, value: string): unknown;
};

export function applyE2eTraceMarker(
  span: TraceMarkerSpan,
  headers: TraceMarkerHeaders,
  runtimeProfile: string | undefined,
): boolean {
  if (runtimeProfile !== 'test') return false;
  const marker = headers[e2eTraceMarkerHeader];
  if (typeof marker !== 'string' || !e2eTraceMarkerPattern.test(marker)) return false;
  span.setAttribute(e2eTraceMarkerAttribute, marker);
  return true;
}
