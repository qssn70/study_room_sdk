import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { ADMIN_SCOPE, PUBLIC_ROUTE } from './auth.decorators';
import { AuthenticatedRequest } from './authenticated-request';
import { AuthService } from './auth.service';

@Injectable()
export class AuthGuard implements CanActivate {
  constructor(private readonly auth: AuthService, private readonly reflector: Reflector) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    if (context.getType() !== 'http') return true;
    const targets = [context.getHandler(), context.getClass()];
    if (this.reflector.getAllAndOverride<boolean>(PUBLIC_ROUTE, targets)) return true;
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const header = request.headers.authorization;
    const authorization = Array.isArray(header) ? header[0] : header;
    const scope = this.reflector.getAllAndOverride<string>(ADMIN_SCOPE, targets);
    if (scope) {
      request.adminIdentity = await this.auth.verifyAdminBearer(authorization, scope);
    } else {
      request.identity = await this.auth.verifyBearer(authorization);
    }
    return true;
  }
}
