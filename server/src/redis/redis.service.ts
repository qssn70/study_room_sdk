/* istanbul ignore file -- Redis driver lifecycle is covered by the Compose integration suite. */
import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { createClient, RedisClientType } from 'redis';

type MessageHandler = (message: string) => void | Promise<void>;

@Injectable()
export class RedisService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(RedisService.name);
  private readonly url = process.env.REDIS_URL ?? 'redis://localhost:6379';
  readonly client: RedisClientType = this.createClient();
  readonly publisher: RedisClientType = this.createClient();
  readonly adapterSubscriber: RedisClientType = this.createClient();
  private readonly subscriber: RedisClientType = this.createClient();
  private readonly handlers = new Map<string, Set<MessageHandler>>();

  constructor() {
    for (const client of [this.client, this.publisher, this.adapterSubscriber, this.subscriber]) {
      client.on('error', (error) => this.logger.error(error.message));
    }
  }

  private createClient(): RedisClientType {
    return createClient({ url: this.url, disableOfflineQueue: true });
  }

  async onModuleInit() {
    await Promise.all([
      this.client.connect(),
      this.publisher.connect(),
      this.adapterSubscriber.connect(),
      this.subscriber.connect(),
    ]);
  }

  async subscribe(channel: string, handler: MessageHandler) {
    let handlers = this.handlers.get(channel);
    if (!handlers) {
      handlers = new Set();
      this.handlers.set(channel, handlers);
      await this.subscriber.subscribe(channel, async (message) => {
        for (const current of this.handlers.get(channel) ?? []) {
          try {
            await current(message);
          } catch (error) {
            this.logger.error(
              `Redis subscriber failed for ${channel}: ${error instanceof Error ? error.message : String(error)}`,
            );
          }
        }
      });
    }
    handlers.add(handler);
  }

  async publish(channel: string, message: string) {
    await this.publisher.publish(channel, message);
  }

  async ping(): Promise<boolean> {
    return (await this.client.ping()) === 'PONG';
  }

  async onModuleDestroy() {
    await Promise.allSettled([
      this.client.quit(),
      this.publisher.quit(),
      this.adapterSubscriber.quit(),
      this.subscriber.quit(),
    ]);
  }
}
