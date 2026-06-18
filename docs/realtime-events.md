# Realtime Events

The reference server exposes a Socket.IO namespace at `/realtime`.

Connect with the same JWT used for REST:

```text
ws://localhost:3000/realtime?token=<jwt>
```

Join a room topic:

```json
{
  "event": "room.join",
  "data": {
    "appId": "app-1",
    "roomId": "room-1"
  }
}
```

Events are emitted as `study-room.event`:

- `room.state`: full room state.
- `member.updated`: member presence changed.
- `chat.message`: new chat message.
- `session.updated`: study session changed.

The Flutter SDK exposes these through `roomStateStream`, `memberEventsStream`, `chatMessagesStream`, and `sessionEventsStream`.

