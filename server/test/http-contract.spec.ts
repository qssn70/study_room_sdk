import {
  ConflictException,
  ForbiddenException,
  HttpException,
  INestApplication,
  NotFoundException,
  UnauthorizedException,
  ValidationPipe,
} from '@nestjs/common';
import { Test } from '@nestjs/testing';
import Ajv2020 from 'ajv/dist/2020';
import addFormats from 'ajv-formats';
import { load } from 'js-yaml';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import request from 'supertest';
import { ApplicationsController } from '../src/applications/applications.controller';
import { ApplicationsService } from '../src/applications/applications.service';
import { ChatController } from '../src/chat/chat.controller';
import { ChatService } from '../src/chat/chat.service';
import { ApiExceptionFilter } from '../src/common/api-exception.filter';
import { RequestContextMiddleware } from '../src/common/request-context.middleware';
import { MetricsService } from '../src/operations/metrics.service';
import { OperationsController } from '../src/operations/operations.controller';
import { PrismaService } from '../src/prisma/prisma.service';
import { RealtimePublisher } from '../src/realtime/realtime.publisher';
import { RedisService } from '../src/redis/redis.service';
import { RoomsController } from '../src/rooms/rooms.controller';
import { RoomsService } from '../src/rooms/rooms.service';
import { SessionsController } from '../src/sessions/sessions.controller';
import { SessionsService } from '../src/sessions/sessions.service';

type OpenApi = {
  paths: Record<string, Record<string, Operation | unknown>>;
  components: {
    responses: Record<string, ResponseSpec>;
    schemas: Record<string, unknown>;
  };
};
type Operation = { operationId: string; responses: Record<string, ResponseSpec> };
type ResponseSpec = {
  $ref?: string;
  content?: Record<string, { schema?: unknown }>;
  headers?: Record<string, unknown>;
};
type SuccessCase = {
  operationId: string;
  method: 'get' | 'post' | 'put' | 'patch' | 'delete';
  url: string;
  status: number;
  body?: Record<string, unknown>;
};

const roomId = '00000000-0000-4000-8000-000000000001';
const requestId = '00000000-0000-4000-8000-000000000002';
const sessionId = '00000000-0000-4000-8000-000000000003';
const messageId = '00000000-0000-4000-8000-000000000004';
const occurredAt = '2026-08-09T00:00:00.000Z';
const member = { id: 'owner-1', displayName: 'Owner', avatarUrl: '', role: 'owner', status: 'online' };
const room = { id: roomId, appId: 'app-1', title: 'Focus', version: 1, members: [member] };
const joinRequest = {
  id: requestId, roomId, userId: 'applicant-1', displayName: 'Applicant', status: 'pending',
  createdAt: occurredAt, updatedAt: occurredAt,
};
const session = {
  id: sessionId, roomId, userId: 'owner-1', status: 'running', startedAt: occurredAt,
  finishedAt: null, updatedAt: occurredAt,
};
const message = {
  id: messageId, roomId, senderId: 'owner-1', senderName: 'Owner', text: 'Hello', sentAt: occurredAt,
};
const application = {
  appId: 'app-1', issuer: 'https://issuer.example', audience: 'study-room',
  jwksUri: 'https://issuer.example/jwks', enabled: true,
  chatRetentionDays: null, sessionRetentionDays: null, createdAt: occurredAt, updatedAt: occurredAt,
};

describe('running HTTP responses conform to OpenAPI', () => {
  const root = resolve(__dirname, '..', '..');
  const openapi = load(readFileSync(resolve(root, 'contracts', 'openapi.yaml'), 'utf8')) as OpenApi;
  const ajv = new Ajv2020({ allErrors: true, strict: true });
  // The workspace may hoist ajv-formats beside a separate, runtime-compatible Ajv package instance.
  addFormats(ajv as unknown as Parameters<typeof addFormats>[0]);
  const schemaDefs = rewriteRefs(openapi.components.schemas);
  const validators = new Map<string, ReturnType<typeof ajv.compile>>();

  const applications = {
    create: jest.fn(async () => application),
    list: jest.fn(async () => ({ items: [application], nextCursor: null })),
    get: jest.fn(async () => application),
    update: jest.fn(async () => ({ ...application, enabled: false })),
  };
  const rooms = {
    create: jest.fn(async () => room),
    list: jest.fn(async () => ({ items: [room], nextCursor: null })),
    get: jest.fn(async () => room),
    requestJoin: jest.fn(async () => joinRequest),
    ownerUserId: jest.fn(async () => 'owner-1'),
    listMyJoinRequests: jest.fn(async () => ({ items: [joinRequest], nextCursor: null })),
    listRoomJoinRequests: jest.fn(async () => ({ items: [joinRequest], nextCursor: null })),
    cancelJoinRequest: jest.fn(async () => undefined),
    decideJoinRequest: jest.fn(async () => ({
      request: { ...joinRequest, status: 'approved' }, roomVersion: 2,
    })),
    snapshot: jest.fn(async () => room),
    leave: jest.fn(async () => room),
    removeMember: jest.fn(async () => room),
    transferOwnership: jest.fn(async () => room),
    delete: jest.fn(async () => ({ userIds: ['owner-1'], roomVersion: 2 })),
  };
  const sessions = {
    start: jest.fn(async () => session),
    listActive: jest.fn(async () => ({ items: [session], nextCursor: null })),
    update: jest.fn(async () => ({ ...session, status: 'paused' })),
  };
  const chat = {
    history: jest.fn(async () => ({ items: [message], nextCursor: null })),
    send: jest.fn(async () => message),
  };
  const realtime = {
    publishRoom: jest.fn(), publishUser: jest.fn(), evictUser: jest.fn(async () => undefined),
  };
  const prisma = { $queryRaw: jest.fn(async () => [1]) };
  const redis = { ping: jest.fn(async () => true) };
  const metrics = { registry: { metrics: jest.fn(async () => '# HELP study_room_test 1\n') } };
  let app: INestApplication;

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({
      controllers: [ApplicationsController, RoomsController, SessionsController, ChatController, OperationsController],
      providers: [
        { provide: ApplicationsService, useValue: applications },
        { provide: RoomsService, useValue: rooms },
        { provide: SessionsService, useValue: sessions },
        { provide: ChatService, useValue: chat },
        { provide: RealtimePublisher, useValue: realtime },
        { provide: PrismaService, useValue: prisma },
        { provide: RedisService, useValue: redis },
        { provide: MetricsService, useValue: metrics },
      ],
    }).compile();
    app = moduleRef.createNestApplication();
    const context = new RequestContextMiddleware();
    app.use((req: any, res: any, next: () => void) => context.use(req, res, next));
    app.use((req: any, _res: any, next: () => void) => {
      req.identity = {
        userId: 'owner-1', appId: 'app-1', displayName: 'Owner', avatarUrl: '',
        expiresAt: new Date(Date.now() + 60_000),
      };
      req.adminIdentity = { subject: 'admin-1', scopes: ['apps:manage'], expiresAt: new Date(Date.now() + 60_000) };
      next();
    });
    app.useGlobalPipes(new ValidationPipe({ transform: true, whitelist: true, forbidNonWhitelisted: true }));
    app.useGlobalFilters(new ApiExceptionFilter());
    await app.init();
  });

  afterAll(async () => app.close());

  it('validates a real success response for every public operation', async () => {
    const cases: SuccessCase[] = [
      { operationId: 'listApplications', method: 'get', url: '/admin/v1/apps', status: 200 },
      { operationId: 'createApplication', method: 'post', url: '/admin/v1/apps', status: 201, body: {
        appId: 'app-1', issuer: application.issuer, audience: application.audience, jwksUri: application.jwksUri,
      } },
      { operationId: 'getApplication', method: 'get', url: '/admin/v1/apps/app-1', status: 200 },
      { operationId: 'updateApplication', method: 'patch', url: '/admin/v1/apps/app-1', status: 200, body: { enabled: false } },
      { operationId: 'listRooms', method: 'get', url: '/v1/rooms', status: 200 },
      { operationId: 'createRoom', method: 'post', url: '/v1/rooms', status: 201, body: { title: 'Focus' } },
      { operationId: 'getRoom', method: 'get', url: `/v1/rooms/${roomId}`, status: 200 },
      { operationId: 'deleteRoom', method: 'delete', url: `/v1/rooms/${roomId}`, status: 204 },
      { operationId: 'listRoomJoinRequests', method: 'get', url: `/v1/rooms/${roomId}/join-requests`, status: 200 },
      { operationId: 'requestRoomAccess', method: 'post', url: `/v1/rooms/${roomId}/join-requests`, status: 201 },
      { operationId: 'cancelRoomAccessRequest', method: 'delete', url: `/v1/rooms/${roomId}/join-requests`, status: 204 },
      { operationId: 'decideJoinRequest', method: 'patch', url: `/v1/rooms/${roomId}/join-requests/${requestId}`, status: 200, body: { decision: 'approved' } },
      { operationId: 'listMyJoinRequests', method: 'get', url: '/v1/join-requests', status: 200 },
      { operationId: 'removeRoomMember', method: 'delete', url: `/v1/rooms/${roomId}/members/member-1`, status: 204 },
      { operationId: 'leaveRoom', method: 'delete', url: `/v1/rooms/${roomId}/members/me`, status: 204 },
      { operationId: 'transferRoomOwnership', method: 'put', url: `/v1/rooms/${roomId}/owner`, status: 200, body: { userId: 'member-1' } },
      { operationId: 'listMessages', method: 'get', url: `/v1/rooms/${roomId}/messages`, status: 200 },
      { operationId: 'sendMessage', method: 'post', url: `/v1/rooms/${roomId}/messages`, status: 201, body: { text: 'Hello' } },
      { operationId: 'startSession', method: 'post', url: `/v1/rooms/${roomId}/sessions`, status: 201 },
      { operationId: 'listActiveSessions', method: 'get', url: `/v1/rooms/${roomId}/active-sessions`, status: 200 },
      { operationId: 'updateSession', method: 'patch', url: `/v1/sessions/${sessionId}`, status: 200, body: { status: 'paused' } },
      { operationId: 'getLiveness', method: 'get', url: '/health/live', status: 200 },
      { operationId: 'getReadiness', method: 'get', url: '/health/ready', status: 200 },
      { operationId: 'getMetrics', method: 'get', url: '/metrics', status: 200 },
    ];
    expect(new Set(cases.map((item) => item.operationId))).toEqual(new Set(allOperations().map((item) => item.operationId)));
    for (const item of cases) {
      let call = request(app.getHttpServer())[item.method](item.url);
      if (item.body) call = call.send(item.body);
      const response = await call.expect(item.status);
      validateActualResponse(item.operationId, item.status, response);
    }
  });

  it('validates representative real errors for every declared error status', async () => {
    const invalid = await request(app.getHttpServer()).post('/v1/rooms').send({ title: '' }).expect(400);
    validateActualResponse('createRoom', 400, invalid);

    rooms.list.mockRejectedValueOnce(new UnauthorizedException('Bad token'));
    const unauthorized = await request(app.getHttpServer()).get('/v1/rooms').expect(401);
    validateActualResponse('listRooms', 401, unauthorized);

    rooms.get.mockRejectedValueOnce(new ForbiddenException('Membership required'));
    const forbidden = await request(app.getHttpServer()).get(`/v1/rooms/${roomId}`).expect(403);
    validateActualResponse('getRoom', 403, forbidden);

    rooms.get.mockRejectedValueOnce(new NotFoundException('Room missing'));
    const missing = await request(app.getHttpServer()).get(`/v1/rooms/${roomId}`).expect(404);
    validateActualResponse('getRoom', 404, missing);

    rooms.create.mockRejectedValueOnce(new ConflictException('Already exists'));
    const conflict = await request(app.getHttpServer()).post('/v1/rooms').send({ title: 'Focus' }).expect(409);
    validateActualResponse('createRoom', 409, conflict);

    rooms.list.mockRejectedValueOnce(new HttpException('Rate limited', 429));
    const limited = await request(app.getHttpServer()).get('/v1/rooms').expect(429);
    validateActualResponse('listRooms', 429, limited);

    rooms.list.mockRejectedValueOnce(new Error('Unexpected'));
    const failed = await request(app.getHttpServer()).get('/v1/rooms').expect(500);
    validateActualResponse('listRooms', 500, failed);

    redis.ping.mockResolvedValueOnce(false);
    const unavailable = await request(app.getHttpServer()).get('/health/ready').expect(503);
    validateActualResponse('getReadiness', 503, unavailable);
  });

  function allOperations() {
    return Object.values(openapi.paths).flatMap((path) => Object.values(path))
      .filter((value): value is Operation => Boolean(value && typeof value === 'object' && 'operationId' in value));
  }

  function operation(operationId: string) {
    const found = allOperations().find((candidate) => candidate.operationId === operationId);
    if (!found) throw new Error(`Unknown operationId: ${operationId}`);
    return found;
  }

  function validateActualResponse(operationId: string, status: number, response: request.Response) {
    const declared = operation(operationId).responses[String(status)];
    if (!declared) throw new Error(`${operationId} does not declare response ${status}`);
    const spec = dereferenceResponse(declared);
    expect(spec.headers?.['x-request-id']).toBeDefined();
    expect(response.headers['x-request-id']).toEqual(expect.any(String));
    if (status === 204) {
      expect(response.text).toBe('');
      return;
    }
    const mediaType = String(response.headers['content-type']).split(';', 1)[0];
    const media = spec.content?.[mediaType];
    if (!media?.schema) throw new Error(`${operationId} ${status} does not declare ${mediaType}`);
    const key = `${operationId}:${status}:${mediaType}`;
    let validate = validators.get(key);
    if (!validate) {
      validate = ajv.compile({ ...rewriteRefs(media.schema), $defs: schemaDefs });
      validators.set(key, validate);
    }
    const value = mediaType === 'application/json' ? response.body : response.text;
    expect(validate(value)).toBe(true);
    if (!validate(value)) throw new Error(ajv.errorsText(validate.errors));
  }

  function dereferenceResponse(response: ResponseSpec) {
    if (!response.$ref) return response;
    const name = response.$ref.split('/').at(-1)!;
    const resolved = openapi.components.responses[name];
    if (!resolved) throw new Error(`Unknown response component: ${name}`);
    return resolved;
  }
});

function rewriteRefs(value: any): any {
  if (Array.isArray(value)) return value.map(rewriteRefs);
  if (!value || typeof value !== 'object') return value;
  return Object.fromEntries(Object.entries(value).map(([key, item]) => [
    key,
    key === '$ref' && typeof item === 'string'
      ? item.replace('#/components/schemas/', '#/$defs/')
      : rewriteRefs(item),
  ]));
}
