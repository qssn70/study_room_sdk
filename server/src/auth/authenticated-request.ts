import { Request } from 'express';
import { AdminIdentity, ExternalIdentity } from '../domain';

export interface AuthenticatedRequest extends Request {
  identity?: ExternalIdentity;
  adminIdentity?: AdminIdentity;
  requestId?: string;
}
