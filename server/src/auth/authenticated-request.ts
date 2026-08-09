import { ExternalIdentity } from '../domain';

export interface AuthenticatedRequest {
  headers: Record<string, string | string[] | undefined>;
  identity?: ExternalIdentity;
}
