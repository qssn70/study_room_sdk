import 'reflect-metadata';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import Ajv2020 from 'ajv/dist/2020';
import addFormats from 'ajv-formats';
import { plainToInstance } from 'class-transformer';
import { validateSync } from 'class-validator';
import { load } from 'js-yaml';
import {
  CreateApplicationBodyDto,
  CreateRoomBodyDto,
  DecideJoinRequestParamsDto,
  ListApplicationsQueryDto,
  ListRoomsQueryDto,
  RemoveRoomMemberParamsDto,
  SendMessageBodyDto,
  UpdateApplicationBodyDto,
} from '../src/generated/request-dtos';

const errorsFor = (value: object) => validateSync(value).flatMap((error) => [
  error.property,
  ...Object.values(error.constraints ?? {}),
]);

type DtoConstructor = new () => object;

const rewriteRefs = (value: unknown): unknown => {
  if (Array.isArray(value)) return value.map(rewriteRefs);
  if (!value || typeof value !== 'object') return value;
  return Object.fromEntries(Object.entries(value).map(([key, item]) => [
    key,
    key === '$ref' && typeof item === 'string'
      ? item.replace('#/components/schemas/', '#/$defs/')
      : rewriteRefs(item),
  ]));
};

describe('generated OpenAPI request DTOs', () => {
  it('converts query integers without converting JSON body integers', () => {
    const query = plainToInstance(ListApplicationsQueryDto, { limit: '25' });
    expect(query.limit).toBe(25);
    expect(errorsFor(query)).toEqual([]);

    const body = plainToInstance(CreateApplicationBodyDto, {
      appId: 'app-1',
      issuer: 'https://issuer.example',
      audience: 'study-room-api',
      jwksUri: 'https://issuer.example/jwks.json',
      chatRetentionDays: '25',
    });
    expect(body.chatRetentionDays).toBe('25');
    expect(errorsFor(body)).toContain('chatRetentionDays');
  });

  it('enforces empty patch, retention, and non-whitespace request constraints', () => {
    expect(errorsFor(plainToInstance(UpdateApplicationBodyDto, {})))
      .toContain('__minimumDefinedProperties');
    expect(errorsFor(plainToInstance(UpdateApplicationBodyDto, { enabled: false }))).toEqual([]);
    expect(errorsFor(plainToInstance(UpdateApplicationBodyDto, { chatRetentionDays: 36500 }))).toEqual([]);
    expect(errorsFor(plainToInstance(UpdateApplicationBodyDto, { chatRetentionDays: 36501 })))
      .toContain('chatRetentionDays');

    expect(errorsFor(plainToInstance(CreateRoomBodyDto, { title: '   ' }))).toContain('title');
    expect(errorsFor(plainToInstance(CreateRoomBodyDto, { title: ` ${'a'.repeat(100)}` }))).toContain('title');
    expect(errorsFor(plainToInstance(SendMessageBodyDto, { text: '\t\n' }))).toContain('text');
  });

  it('merges path parameters, accepts generic UUIDs, and limits user IDs to 256 characters', () => {
    const versionOneUuid = '6ba7b810-9dad-11d1-80b4-00c04fd430c8';
    expect(errorsFor(plainToInstance(ListRoomsQueryDto, { cursor: versionOneUuid }))).toEqual([]);

    const missingRequestId = plainToInstance(DecideJoinRequestParamsDto, { roomId: versionOneUuid });
    expect(errorsFor(missingRequestId)).toContain('requestId');

    const validMember = plainToInstance(RemoveRoomMemberParamsDto, {
      roomId: versionOneUuid,
      userId: 'u'.repeat(256),
    });
    expect(errorsFor(validMember)).toEqual([]);
    const invalidMember = plainToInstance(RemoveRoomMemberParamsDto, {
      roomId: versionOneUuid,
      userId: 'u'.repeat(257),
    });
    expect(errorsFor(invalidMember)).toContain('userId');
  });

  it('matches Ajv acceptance for boundary request-body samples', () => {
    const document = load(readFileSync(resolve(__dirname, '..', '..', 'contracts', 'openapi.yaml'), 'utf8')) as {
      components: { schemas: Record<string, unknown> };
    };
    const definitions = rewriteRefs(document.components.schemas) as Record<string, unknown>;
    const ajv = new Ajv2020({ allErrors: true, strict: true });
    addFormats(ajv as unknown as Parameters<typeof addFormats>[0]);
    const cases: Array<{
      schema: string;
      dto: DtoConstructor;
      samples: unknown[];
    }> = [
      {
        schema: 'CreateApplicationRequest',
        dto: CreateApplicationBodyDto,
        samples: [
          { appId: 'app-1', issuer: 'issuer', audience: 'api', jwksUri: 'https://issuer.example/jwks' },
          { appId: 'a'.repeat(65), issuer: 'issuer', audience: 'api', jwksUri: 'https://issuer.example/jwks' },
          { appId: 'app-1', issuer: 'issuer', audience: 'api', jwksUri: 'not a uri' },
          { appId: 'app-1', issuer: 'issuer', audience: 'api', jwksUri: 'urn:example:jwks' },
          { appId: 'app-1', issuer: 'issuer', audience: 'api', jwksUri: 'ftp://issuer.example/jwks' },
          { appId: 'app-1', issuer: 'issuer', audience: 'api', jwksUri: 'https://issuer.example/jwks', chatRetentionDays: 36500 },
          { appId: 'app-1', issuer: 'issuer', audience: 'api', jwksUri: 'https://issuer.example/jwks', chatRetentionDays: 36501 },
          { appId: 'app-1', issuer: 'issuer', audience: 'api', jwksUri: 'https://issuer.example/jwks', chatRetentionDays: '30' },
          { appId: 'app-1', issuer: 'issuer', audience: 'api', jwksUri: 'https://issuer.example/jwks', unexpected: true },
        ],
      },
      {
        schema: 'UpdateApplicationRequest',
        dto: UpdateApplicationBodyDto,
        samples: [{}, { enabled: false }, { chatRetentionDays: null }, { sessionRetentionDays: 0 }, { unexpected: true }],
      },
      {
        schema: 'CreateRoomRequest',
        dto: CreateRoomBodyDto,
        samples: [{ title: 'Focus' }, { title: '   ' }, { title: 'a'.repeat(100) }, { title: 'a'.repeat(101) }],
      },
      {
        schema: 'SendMessageRequest',
        dto: SendMessageBodyDto,
        samples: [{ text: 'Hello' }, { text: '\t\n' }, { text: 'a'.repeat(2000) }, { text: 'a'.repeat(2001) }],
      },
    ];

    for (const entry of cases) {
      const validateSchema = ajv.compile({
        ...(rewriteRefs(document.components.schemas[entry.schema]) as object),
        $defs: definitions,
      });
      for (const sample of entry.samples) {
        const ajvAccepted = validateSchema(structuredClone(sample)) as boolean;
        const dto = plainToInstance(entry.dto, structuredClone(sample));
        const dtoAccepted = validateSync(dto, {
          forbidNonWhitelisted: true,
          whitelist: true,
        }).length === 0;
        expect({ schema: entry.schema, sample, dtoAccepted }).toEqual({
          schema: entry.schema,
          sample,
          dtoAccepted: ajvAccepted,
        });
      }
    }
  });
});
