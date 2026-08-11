import { SetMetadata } from '@nestjs/common';

export const SKIP_RATE_LIMIT = 'study-room:skip-rate-limit';

export const SkipRateLimit = () => SetMetadata(SKIP_RATE_LIMIT, true);
