# Deployment Notes

## Environment

- `PORT`: API port, default `3000`.
- `STUDY_ROOM_JWT_SECRET`: shared secret for local JWT verification.
- `DATABASE_URL`: PostgreSQL connection string.
- `REDIS_URL`: Redis connection string.

## Persistence

The first reference implementation uses in-memory repositories to keep local SDK adoption simple. Replace the room, session, and chat services with PostgreSQL-backed repositories before production. Use Redis for presence expiry and Socket.IO scaling.

## Production Checklist

- Use HTTPS/WSS.
- Use short JWT expiry and rotate signing keys.
- Replace shared secret verification with JWKS if multiple apps sign tokens.
- Add PostgreSQL migrations for rooms, members, sessions, and chat messages.
- Add Redis presence expiry and cleanup jobs.
- Configure Socket.IO Redis adapter for multi-instance deployments.

