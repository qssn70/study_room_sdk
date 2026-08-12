import { trace } from '@opentelemetry/api';
import { RequestContextMiddleware } from '../src/common/request-context.middleware';

describe('RequestContextMiddleware', () => {
  it('adds a validated test marker to the active HTTP span', () => {
    const middleware = new RequestContextMiddleware();
    const span = { setAttribute: jest.fn() };
    const activeSpan = jest.spyOn(trace, 'getActiveSpan').mockReturnValue(span as never);
    const previousProfile = process.env.STUDY_ROOM_RUNTIME_PROFILE;
    process.env.STUDY_ROOM_RUNTIME_PROFILE = 'test';
    const request = {
      header: jest.fn().mockReturnValue(undefined),
      headers: { 'x-study-room-e2e-trace-marker': 'graceful-run-123' },
    };
    const response = { setHeader: jest.fn() };
    const next = jest.fn();

    try {
      middleware.use(request as never, response as never, next);
      expect(span.setAttribute).toHaveBeenCalledWith(
        'study_room.e2e.trace_marker',
        'graceful-run-123',
      );
      expect(next).toHaveBeenCalledTimes(1);
    } finally {
      activeSpan.mockRestore();
      if (previousProfile === undefined) delete process.env.STUDY_ROOM_RUNTIME_PROFILE;
      else process.env.STUDY_ROOM_RUNTIME_PROFILE = previousProfile;
    }
  });
});
