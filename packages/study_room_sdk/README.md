# study_room_sdk

Typed Flutter/Dart client for Study Room API 0.4.1. It provides explicit HTTP and Socket.IO lifecycle management, expiring-token refresh, room approval workflows, cursor pagination, structured errors, connection state, reconnect resynchronization, local study backups, and optional idempotent creates.

```dart
final sdk = StudyRoomSdk(
  StudyRoomSdkConfig(
    apiBaseUri: Uri.parse('https://study.example.com'),
    realtimeUri: Uri.parse('wss://study.example.com/v1/realtime'),
    tokenProvider: (request) async => StudyRoomAccessToken(
      token: await tokenService.issueToken(forceRefresh: request.forceRefresh),
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

`rooms.create`, `chat.send`, and `sessions.start` accept an optional `idempotencyKey`. Reuse a key only for retries of the same normalized request. Keys are 1–128 characters from `[A-Za-z0-9._:-]`; omitting the key preserves 0.4.0 behavior.

`MemoryStudyStore` implements the optional `StudyBackupStore` capability. `StudyDataBackup` is versioned plaintext JSON without a user ID or namespace. The receiving Store selects the destination identity; the host must encrypt and protect exported data in storage and transit.

See the repository [migration guide](https://github.com/qssn70/study_room_sdk/blob/main/docs/migration-0.3-to-0.4.md) when upgrading from 0.3.

Licensed under Apache-2.0.
