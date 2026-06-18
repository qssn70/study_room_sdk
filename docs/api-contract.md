# API Contract

All endpoints require `Authorization: Bearer <jwt>`.

## Rooms

- `GET /rooms/:roomId`: returns the current room state for the caller's `appId`.
- `POST /rooms/:roomId/join`: adds or refreshes the caller as an online member.
- `POST /rooms/:roomId/leave`: removes the caller from the online member list.

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
      "status": "online"
    }
  ]
}
```

## Sessions

- `POST /rooms/:roomId/sessions/start`
- `POST /sessions/:sessionId/pause`
- `POST /sessions/:sessionId/resume`
- `POST /sessions/:sessionId/finish`

Session statuses are `idle`, `running`, `paused`, and `finished`.

## Chat

- `GET /rooms/:roomId/chat`: returns `{ "messages": [...] }`.
- `POST /rooms/:roomId/chat` with `{ "text": "hello" }`: sends a trimmed message.

