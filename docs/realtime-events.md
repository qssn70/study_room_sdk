# Realtime Events

The reference server exposes a Socket.IO namespace at `/realtime`.

Connect with the same JWT used for REST using the Socket.IO auth payload:

```javascript
io('http://localhost:3000/realtime', {
  auth: { token: jwt },
});
```

Query-string tokens are rejected.

Join a room topic:

```json
{
  "event": "room.join",
  "data": {
    "roomId": "room-1"
  }
}
```

The server obtains `appId` from the verified JWT and checks room membership.
Use `room.leave` with the same `{ "roomId": "room-1" }` payload to leave the
Socket.IO channel.

Update this socket's presence after subscribing:

```json
{
  "event": "presence.update",
  "data": {
    "roomId": "room-1",
    "status": "focusing"
  }
}
```

Clients may send `online`, `focusing`, `idle`, or `away`; `offline` is owned by
the server. The socket must still be subscribed and the identity must still be
an access member. Multiple sockets are aggregated as follows: no connections
is `offline`, all-away is `away`, then `focusing` takes priority, followed by
`idle` and `online`.

Events are emitted as `study-room.event`:

- `room.state`: full room state.
- `member.updated`: member presence changed.
- `chat.message`: new chat message.
- `session.updated`: study session changed.

Every event has a room-aware envelope:

```json
{
  "type": "member.updated",
  "roomId": "room-1",
  "payload": {
    "id": "user-1",
    "displayName": "Lin",
    "avatarUrl": "",
    "status": "focusing"
  }
}
```

The Flutter SDK exposes all-room streams plus `roomStateFor(roomId)`,
`roomSnapshot(roomId)`, `roomMemberEventsStream`, and
`memberEventsFor(roomId)`. The old flat `memberEventsStream` remains available
but is deprecated. On reconnect, the SDK re-subscribes every joined room and
re-sends each room's latest desired Presence.

