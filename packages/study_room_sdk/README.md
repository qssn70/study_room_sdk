# study_room_sdk

Typed Flutter/Dart client for Study Room API 0.4. It provides explicit HTTP and Socket.IO lifecycle management, expiring-token refresh, room approval workflows, cursor pagination, structured errors, connection state, and reconnect resynchronization.

```dart
final sdk = StudyRoomSdk(
  StudyRoomSdkConfig(
    apiBaseUri: Uri.parse('https://study.example.com'),
    realtimeUri: Uri.parse('wss://study.example.com/v1/realtime'),
    tokenProvider: (request) async => StudyRoomAccessToken(
      value: await tokenService.value(forceRefresh: request.forceRefresh),
      expiresAt: await tokenService.expiresAt(),
    ),
  ),
);

await sdk.start();
final rooms = await sdk.rooms.list();
final room = await sdk.rooms.subscribe(rooms.items.first.id);
await sdk.setAway(room.id, true);
final snapshot = sdk.syncState;
await sdk.close();
```

Services are available through `rooms`, `joinRequests`, `members`, `sessions`, and `chat`. Every page exposes immutable `items` and a nullable `nextCursor`. `syncState` and `syncStates` expose the last atomic room, active-session, recent-chat, and approval snapshot; call `resync()` to refresh it explicitly. All network methods accept an optional `StudyRoomCancellationToken`. Inject `StudyRoomTransport` and `StudyRoomRealtimeConnector` for tests or custom networking.

See the repository [migration guide](https://github.com/qssn70/study_room_sdk/blob/main/docs/migration-0.3-to-0.4.md) when upgrading from 0.3.

Licensed under Apache-2.0.
