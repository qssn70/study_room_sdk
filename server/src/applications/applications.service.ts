import { BadRequestException, Injectable, NotFoundException, OnModuleInit } from '@nestjs/common';
import { Application, Prisma } from '@prisma/client';
import { CreateApplicationBodyDto, UpdateApplicationBodyDto } from '../generated/request-dtos';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';
import { JwksUriPolicy, JwksUriPolicyError } from './jwks-uri.policy';

export const APPLICATION_CHANGE_CHANNEL = 'study-room:applications';

@Injectable()
export class ApplicationsService implements OnModuleInit {
  private readonly cache = new Map<string, { value: Application; expiresAt: number }>();
  private readonly cacheTtlMs = 5 * 60 * 1000;

  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly jwksUriPolicy: JwksUriPolicy,
  ) {}

  async onModuleInit() {
    const applications = await this.prisma.application.findMany({
      select: { appId: true, jwksUri: true },
    });
    for (const application of applications) {
      this.jwksUriPolicy.assertAllowed(
        application.jwksUri,
        `JWKS URI for application ${application.appId}`,
      );
    }
    await this.redis.subscribe(APPLICATION_CHANGE_CHANNEL, (message) => {
      const event = JSON.parse(message) as { appId: string };
      this.cache.delete(event.appId);
    });
  }

  async create(input: CreateApplicationBodyDto, actorId: string): Promise<Application> {
    this.validateJwksUri(input.jwksUri);
    const application = await this.prisma.$transaction(async (tx) => {
      const created = await tx.application.create({
        data: { ...input, enabled: input.enabled ?? true },
      });
      await tx.auditLog.create({
        data: { appId: created.appId, actorId, action: 'application.created', resourceId: created.appId },
      });
      return created;
    });
    await this.changed(application);
    return application;
  }

  async update(appId: string, input: UpdateApplicationBodyDto, actorId: string) {
    if (input.jwksUri !== undefined) this.validateJwksUri(input.jwksUri);
    const application = await this.prisma.$transaction(async (tx) => {
      const updated = await tx.application.update({ where: { appId }, data: input });
      await tx.auditLog.create({
        data: {
          appId,
          actorId,
          action: 'application.updated',
          resourceId: appId,
          metadata: input as unknown as Prisma.InputJsonValue,
        },
      });
      return updated;
    }).catch((error: unknown) => {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2025') {
        throw new NotFoundException('Application not found');
      }
      throw error;
    });
    await this.changed(application);
    return application;
  }

  async get(appId: string): Promise<Application> {
    const cached = this.cache.get(appId);
    if (cached && cached.expiresAt > Date.now()) return cached.value;
    const value = await this.prisma.application.findUnique({ where: { appId } });
    if (!value) throw new NotFoundException('Application not found');
    this.cache.set(appId, { value, expiresAt: Date.now() + this.cacheTtlMs });
    return value;
  }

  async getEnabled(appId: string): Promise<Application> {
    const application = await this.get(appId);
    if (!application.enabled) throw new NotFoundException('Application not found');
    return application;
  }

  async list(cursor?: string, limit = 50) {
    const take = Math.min(Math.max(limit, 1), 100);
    const items = await this.prisma.application.findMany({
      orderBy: { appId: 'asc' },
      ...(cursor ? { cursor: { appId: cursor }, skip: 1 } : {}),
      take: take + 1,
    });
    const hasMore = items.length > take;
    if (hasMore) items.pop();
    return { items, nextCursor: hasMore ? items.at(-1)?.appId ?? null : null };
  }

  private async changed(application: Application) {
    this.cache.delete(application.appId);
    await this.redis.publish(
      APPLICATION_CHANGE_CHANNEL,
      JSON.stringify({ appId: application.appId, enabled: application.enabled }),
    );
  }

  private validateJwksUri(value: string) {
    try {
      this.jwksUriPolicy.assertAllowed(value);
    } catch (error) {
      if (error instanceof JwksUriPolicyError) throw new BadRequestException(error.message);
      throw error;
    }
  }
}
