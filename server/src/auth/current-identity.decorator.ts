import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import { ExternalIdentity } from '../domain';
import { AuthenticatedRequest } from './authenticated-request';

export const CurrentIdentity = createParamDecorator(
  (_data: unknown, context: ExecutionContext): ExternalIdentity => {
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    if (!request.identity) {
      throw new Error('Authenticated identity is unavailable');
    }
    return request.identity;
  },
);
