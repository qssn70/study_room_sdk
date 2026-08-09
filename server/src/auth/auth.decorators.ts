import { SetMetadata } from '@nestjs/common';

export const PUBLIC_ROUTE = 'study-room:public';
export const ADMIN_SCOPE = 'study-room:admin-scope';
export const Public = () => SetMetadata(PUBLIC_ROUTE, true);
export const AdminScope = (scope: string) => SetMetadata(ADMIN_SCOPE, scope);
