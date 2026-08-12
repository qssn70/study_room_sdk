# Migrating from 0.3 to 0.4

0.4 is intentionally protocol-incompatible. Deploy it as a separate environment, migrate clients, then switch traffic. The 0.3 in-memory server has no data migration.

## Server and token changes

- Change REST paths from unversioned routes to `/v1`; change the Socket.IO namespace from `/realtime` to `/v1/realtime`.
- Replace the shared HS256 secret with an application registered through `/admin/v1/apps` and an RS256/ES256 JWKS.
- Include `sub`, `appId`, `displayName`, `iss`, `aud`, and `exp` in user tokens. Admin JWTs use a separate JWKS and require `apps:manage`.
- A client no longer joins a room immediately. It submits a join request and waits for the owner to approve it.

## Flutter changes

```dart
// 0.3: implicit clients and long-lived string token
// 0.4: explicit SDK lifecycle and expiring token provider
final sdk = StudyRoomSdk(
  StudyRoomSdkConfig(
    apiBaseUri: apiUri,
    realtimeUri: realtimeUri,
    tokenProvider: (request) async => StudyRoomAccessToken(
      token: await auth.studyRoomToken(forceRefresh: request.forceRefresh),
      expiresAt: await auth.studyRoomTokenExpiry(),
    ),
  ),
);
await sdk.start();
try {
  final rooms = await sdk.rooms.list();
  await sdk.rooms.subscribe(rooms.items.first.id);
} finally {
  await sdk.close();
}
```

Use `rooms`, `joinRequests`, `members`, `sessions`, and `chat` services instead of the 0.3 flat clients. Chat history and active sessions return immutable cursor pages. Presence is authoritative: running/paused sessions derive focusing/idle, while hosts may only call `setAway(roomId, bool)`. Handle `StudyRoomException`, observe `connectionStates`, and consume `syncStates` after reconnects.

### Updating from a 0.4 beta

The release candidate names the public access-token field `token`. Replace every
`StudyRoomAccessToken(value: ...)` argument with
`StudyRoomAccessToken(token: ...)`, and replace reads of `.value` with `.token`.
There is no deprecated `value` alias.

The local focus feature keeps the existing SharedPreferences key layout. Existing goals, tasks, sounds, background settings, and study records remain available when the same `localStorageNamespace` and `currentUserId` are used.
