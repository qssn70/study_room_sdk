# API Contract

All endpoints require `Authorization: Bearer <jwt>`. Tokens must use HS256,
contain a future `exp`, and include non-empty `sub`, `appId`, and `displayName`
claims. The server derives tenant and user identity exclusively from the JWT.

## Rooms

- `GET /rooms/:roomId`: returns the current room state for a room member.
- `POST /rooms/:roomId/join`: adds or refreshes the caller's access membership.
- `POST /rooms/:roomId/leave`: removes the caller's access membership.

Joining is the only room operation available before membership is established.
Chat, room reads, session starts, and realtime subscriptions require membership.

Room response:

```json
{
  "id": "room-1",
  "appId": "app-1",
  "title": "Room room-1",
  "members": [
    {
      "id": "user-1",
      "displayName": "Lin",
      "avatarUrl": "",
      "status": "offline"
    }
  ]
}
```

Presence is connection-derived. A member with no realtime connections is
`offline`; joining the Socket.IO room changes the effective status to
`online`. Disconnecting does not remove access membership.

## Sessions

- `POST /rooms/:roomId/sessions/start`
- `POST /sessions/:sessionId/pause`
- `POST /sessions/:sessionId/resume`
- `POST /sessions/:sessionId/finish`

Session statuses are `idle`, `running`, `paused`, and `finished`.
Only the session creator can pause, resume, or finish a session.
Starting/resuming a session changes the connected creator to `focusing`;
pausing/finishing changes them to `idle`. A creator can still finish after
leaving the room.

## Chat

- `GET /rooms/:roomId/chat`: returns `{ "messages": [...] }`.
- `POST /rooms/:roomId/chat` with `{ "text": "hello" }`: sends a trimmed message.

Both operations require room access membership. `ChatClient.loadHistory()`
returns messages in server order.

