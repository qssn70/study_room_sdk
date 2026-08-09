# Realtime protocol

Connect to the Socket.IO namespace `/v1/realtime` with a user JWT in `auth.token`. Query-string tokens are rejected. The server automatically joins private user and application channels; clients cannot choose arbitrary channel names.

Room access is an acknowledged operation:

```json
{ "event": "room.subscribe", "data": { "roomId": "7e0ae45f-b8ea-4e39-a51f-c77139b78019" } }
```

The ack is either `{ "ok": true }` or `{ "ok": false, "error": { "code": "...", "message": "..." } }`. `room.unsubscribe` and `presence.set-away` use the same ack convention. Clients send `{ "roomId": "...", "away": true|false }`; online/offline and focusing/idle are derived by the server from connections and active sessions.

Server events are emitted as `study-room.event` and validated by [`contracts/realtime-events.schema.json`](../contracts/realtime-events.schema.json):

```json
{
  "schemaVersion": 1,
  "eventId": "b8dccbd6-8f84-46ac-bb62-77be33a2614f",
  "type": "chat.message.created",
  "roomId": "7e0ae45f-b8ea-4e39-a51f-c77139b78019",
  "roomVersion": null,
  "occurredAt": "2026-08-09T12:00:00.000Z",
  "payload": {}
}
```

`roomId` and `roomVersion` are always present in the envelope, but either can be `null` when the event has no corresponding room or room snapshot version. Room structure, membership, and Presence events carry the current room version. Chat, session, and pending join-request events use `roomVersion: null`; clients must not use those events to order or replace room snapshots.

Events are best effort and are not a history log. After connecting or reconnecting, the Flutter SDK re-authenticates, resubscribes with ack, and fetches each joined room from REST. REST/ PostgreSQL state wins over an event. Event IDs can be used for short-lived client deduplication.

Presence is stored per socket in Redis with a 60-second TTL and refreshed every 20 seconds. Membership removal invokes a cross-instance `socketsLeave`; application disabling and JWT expiry disconnect matching sockets across instances.
