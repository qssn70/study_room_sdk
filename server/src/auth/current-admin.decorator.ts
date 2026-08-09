import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import { AdminIdentity } from '../domain';
import { AuthenticatedRequest } from './authenticated-request';

export const CurrentAdmin = createParamDecorator(
  (_data: unknown, context: ExecutionContext): AdminIdentity => {
    const admin = context.switchToHttp().getRequest<AuthenticatedRequest>().adminIdentity;
    if (!admin) throw new Error('Authenticated admin identity is unavailable');
    return admin;
  },
);
