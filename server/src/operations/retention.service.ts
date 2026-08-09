import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class RetentionService {
  private readonly logger = new Logger(RetentionService.name);

  constructor(private readonly prisma: PrismaService) {}

  @Cron('0 3 * * *')
  async clean() {
    await this.prisma.$transaction(async (tx) => {
      const [lock] = await tx.$queryRaw<Array<{ locked: boolean }>>(
        Prisma.sql`SELECT pg_try_advisory_xact_lock(193701481) AS locked`,
      );
      if (!lock?.locked) return;
      const applications = await tx.application.findMany({
        where: {
          enabled: true,
          OR: [{ chatRetentionDays: { not: null } }, { sessionRetentionDays: { not: null } }],
        },
      });
      for (const application of applications) {
        if (application.chatRetentionDays !== null) {
          const before = new Date(Date.now() - application.chatRetentionDays * 86_400_000);
          const deleted = await tx.chatMessage.deleteMany({
            where: { appId: application.appId, sentAt: { lt: before } },
          });
          if (deleted.count) this.logger.log(`Deleted ${deleted.count} expired chat messages for ${application.appId}`);
        }
        if (application.sessionRetentionDays !== null) {
          const before = new Date(Date.now() - application.sessionRetentionDays * 86_400_000);
          const deleted = await tx.studySession.deleteMany({
            where: { appId: application.appId, finishedAt: { lt: before } },
          });
          if (deleted.count) this.logger.log(`Deleted ${deleted.count} expired sessions for ${application.appId}`);
        }
      }
    }, { timeout: 60_000 });
  }
}
