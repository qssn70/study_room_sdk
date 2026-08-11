import { readFileSync } from 'fs';
import { resolve } from 'path';
import Ajv2020 from 'ajv/dist/2020';
import addFormats from 'ajv-formats';
import { load } from 'js-yaml';
import { toRoomWire } from '../src/generated/contract-types';

type OpenApiDocument = {
  openapi: string;
  info: { version: string };
  paths: Record<string, Record<string, unknown>>;
  components: {
    securitySchemes: Record<string, unknown>;
    schemas: Record<string, {
      type?: string;
      additionalProperties?: boolean;
      minProperties?: number;
      properties?: Record<string, Record<string, unknown>>;
    }>;
    responses: Record<string, { headers?: Record<string, unknown> }>;
  };
};

describe('authoritative contracts', () => {
  const root = resolve(__dirname, '..', '..');
  const openapi = load(readFileSync(resolve(root, 'contracts', 'openapi.yaml'), 'utf8')) as OpenApiDocument;
  const realtime = JSON.parse(
    readFileSync(resolve(root, 'contracts', 'realtime-events.schema.json'), 'utf8'),
  ) as {
    required: string[];
    properties: { schemaVersion: { const: number }; type: { enum: string[] } };
    oneOf: Array<{ $ref: string }>;
  };

  it('defines the complete versioned HTTP surface and separate security schemes', () => {
    expect(openapi.openapi).toBe('3.1.0');
    expect(openapi.info.version).toBe('0.4.0-beta.1');
    expect(openapi.paths).toEqual(expect.objectContaining({
      '/admin/v1/apps': expect.any(Object),
      '/v1/rooms': expect.any(Object),
      '/v1/rooms/{roomId}/active-sessions': expect.any(Object),
      '/health/live': expect.any(Object),
      '/health/ready': expect.any(Object),
      '/metrics': expect.any(Object),
    }));
    expect(openapi.components.securitySchemes).toEqual(expect.objectContaining({
      userBearer: expect.any(Object),
      adminBearer: expect.any(Object),
    }));
  });

  it('keeps object response and request schemas strict', () => {
    const objects = Object.entries(openapi.components.schemas)
      .filter(([, schema]) => schema.type === 'object');
    expect(objects.length).toBeGreaterThan(10);
    expect(objects.filter(([, schema]) => schema.additionalProperties !== false)).toEqual([]);
    expect(openapi.components.schemas.UpdateApplicationRequest.minProperties).toBe(1);
    expect(openapi.components.schemas.CreateApplicationRequest.properties?.chatRetentionDays?.maximum).toBe(36500);
    expect(openapi.components.schemas.CreateRoomRequest.properties?.title?.pattern).toBe('\\S');
    expect(openapi.components.schemas.SendMessageRequest.properties?.text?.pattern).toBe('\\S');
    expect(openapi.components.responses.TooManyRequests.headers).toHaveProperty('Retry-After');
  });

  it('compiles a discriminated realtime union and rejects mismatched payloads', () => {
    const ajv = new Ajv2020({ allErrors: true, strict: true });
    // npm may hoist ajv-formats beside a compatible but separately installed Ajv instance.
    addFormats(ajv as unknown as Parameters<typeof addFormats>[0]);
    const validate = ajv.compile(realtime);
    expect(realtime.required).toEqual(expect.arrayContaining(['roomId', 'roomVersion']));
    expect(realtime.oneOf).toHaveLength(realtime.properties.type.enum.length);
    expect(validate({
      schemaVersion: 1,
      eventId: '00000000-0000-4000-8000-000000000001',
      type: 'membership.updated',
      roomId: '00000000-0000-4000-8000-000000000002',
      roomVersion: 1,
      occurredAt: '2026-08-09T12:00:00.000Z',
      payload: { roomId: '00000000-0000-4000-8000-000000000002', active: false },
    })).toBe(true);
    expect(validate({
      schemaVersion: 1,
      eventId: '00000000-0000-4000-8000-000000000001',
      type: 'membership.updated',
      roomId: '00000000-0000-4000-8000-000000000002',
      roomVersion: null,
      occurredAt: '2026-08-09T12:00:00.000Z',
      payload: { text: 'wrong payload' },
    })).toBe(false);
  });

  it('generates concrete TypeScript and Dart wire types', () => {
    const typescript = readFileSync(resolve(root, 'server', 'src', 'generated', 'contract-types.ts'), 'utf8');
    const requestDtos = readFileSync(resolve(root, 'server', 'src', 'generated', 'request-dtos.ts'), 'utf8');
    const dart = readFileSync(resolve(root, 'packages', 'study_room_sdk', 'lib', 'src', 'generated_contract.dart'), 'utf8');
    expect(typescript).toContain('export interface operations');
    expect(typescript).toContain('export type RealtimeEnvelopeWire =');
    expect(typescript).toMatch(/readonly id: string;/);
    const generatedRoom = toRoomWire({
      id: '00000000-0000-4000-8000-000000000001',
      appId: 'app-1',
      title: 'Focus',
      version: 1,
      members: [],
    });
    expect(generatedRoom.title).toBe('Focus');
    expect(dart).toContain('final class ApplicationWire');
    expect(dart).toContain('sealed class RealtimeEnvelopeWire');
    expect(dart).not.toContain('typedef ApplicationWire = Map');
    expect(requestDtos).toContain('export class CreateApplicationBodyDto');
    expect(requestDtos).toContain('export class DecideJoinRequestParamsDto');
    expect(requestDtos).toContain('export class ListActiveSessionsQueryDto');
    expect(requestDtos).toContain('@Type(() => Number)');
  });
});
