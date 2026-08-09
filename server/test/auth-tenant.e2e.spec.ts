import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import jwt, { SignOptions } from 'jsonwebtoken';
import request from 'supertest';
import { AppModule } from '../src/app.module';

describe('HTTP authentication and tenant isolation', () => {
  let app: INestApplication;

  const token = (
    userId: string,
    appId: string,
    options: SignOptions = { expiresIn: '5m' },
  ) =>
    jwt.sign(
      { sub: userId, appId, displayName: userId, avatarUrl: '' },
      'test-secret',
      options,
    );

  beforeAll(async () => {
    process.env.STUDY_ROOM_JWT_SECRET = 'test-secret';
    const module = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = module.createNestApplication();
    await app.init();
  });

  afterAll(async () => {
    await app.close();
    delete process.env.STUDY_ROOM_JWT_SECRET;
  });

  it('returns 401 for missing, malformed, and expired bearer tokens', async () => {
    const wrongSignature = jwt.sign(
      {
        sub: 'user-1',
        appId: 'app-1',
        displayName: 'Lin',
        avatarUrl: '',
      },
      'wrong-secret',
      { expiresIn: '5m' },
    );

    await request(app.getHttpServer()).get('/rooms/room-1').expect(401);
    await request(app.getHttpServer())
      .get('/rooms/room-1')
      .set('Authorization', 'Bearer invalid')
      .expect(401);
    await request(app.getHttpServer())
      .get('/rooms/room-1')
      .set('Authorization', `Bearer ${wrongSignature}`)
      .expect(401);
    await request(app.getHttpServer())
      .get('/rooms/room-1')
      .set('Authorization', `Bearer ${token('expired', 'app-1', { expiresIn: -1 })}`)
      .expect(401);
  });

  it('enforces room membership and session ownership', async () => {
    const owner = token('owner', 'app-1');
    const peer = token('peer', 'app-1');
    const otherTenant = token('attacker', 'app-2');

    await request(app.getHttpServer())
      .post('/rooms/secure-room/join')
      .set('Authorization', `Bearer ${owner}`)
      .expect(201);
    await request(app.getHttpServer())
      .get('/rooms/secure-room')
      .set('Authorization', `Bearer ${peer}`)
      .expect(403);
    await request(app.getHttpServer())
      .post('/rooms/secure-room/chat')
      .set('Authorization', `Bearer ${peer}`)
      .send({ text: 'no access' })
      .expect(403);

    const started = await request(app.getHttpServer())
      .post('/rooms/secure-room/sessions/start')
      .set('Authorization', `Bearer ${owner}`)
      .expect(201);

    await request(app.getHttpServer())
      .post('/rooms/secure-room/join')
      .set('Authorization', `Bearer ${peer}`)
      .expect(201);
    await request(app.getHttpServer())
      .post(`/sessions/${started.body.id}/pause`)
      .set('Authorization', `Bearer ${peer}`)
      .expect(403);
    await request(app.getHttpServer())
      .post(`/sessions/${started.body.id}/pause`)
      .set('Authorization', `Bearer ${otherTenant}`)
      .expect(404);
    await request(app.getHttpServer())
      .post(`/sessions/${started.body.id}/pause`)
      .set('Authorization', `Bearer ${owner}`)
      .expect(201);
    await request(app.getHttpServer())
      .post('/rooms/secure-room/leave')
      .set('Authorization', `Bearer ${owner}`)
      .expect(201);
    await request(app.getHttpServer())
      .post(`/sessions/${started.body.id}/finish`)
      .set('Authorization', `Bearer ${owner}`)
      .expect(201);
  });
});
