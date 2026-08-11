# Getting started with 0.4

## Start the reference backend

```sh
cp .env.dev.example .env.dev
# Replace POSTGRES_PASSWORD and E2E_FIXTURE_CONTROL_TOKEN, then:
docker compose --env-file .env.dev --profile dev up --build
```

The explicit `dev` profile runs two API instances behind `http://localhost:3000`, internal PostgreSQL and Redis services, the demo seed, and the development JWKS fixture at `http://localhost:4000`. Running Compose without `--profile dev` does not start the fixture or seed and requires an external HTTPS administrator JWKS configuration.

```sh
curl -X POST http://localhost:4000/token \
  -H "content-type: application/json" \
  -d '{"sub":"user-1","displayName":"Lin"}'
```

The token includes `sub`, `appId`, `displayName`, `iss`, `aud`, and `exp` and is signed with an ephemeral RS256 key. Production tokens must come from your identity service. Register each production app through the separately authenticated `/admin/v1/apps` API.

## Connect Flutter

```dart
final sdk = StudyRoomSdk(
  StudyRoomSdkConfig(
    apiBaseUri: Uri.parse('http://localhost:3000'),
    realtimeUri: Uri.parse('ws://localhost:3000/v1/realtime'),
    tokenProvider: (request) => identityService.studyRoomToken(
      forceRefresh: request.forceRefresh,
      minimumValidity: request.minimumValidity,
    ),
    requestTimeout: const Duration(seconds: 15),
  ),
);

await sdk.start();
final created = await sdk.rooms.create('Focus room');
await sdk.rooms.subscribe(created.id);
await sdk.setAway(created.id, false);
await sdk.chat.send(created.id, 'Ready to study');
final messages = await sdk.chat.history(created.id, limit: 50);
final activeSessions = await sdk.sessions.listActive(created.id);
```

Other users call `sdk.joinRequests.request(roomId)`. Owners load `sdk.joinRequests.forRoom(roomId)` and approve or reject a request. Owners can remove members or transfer ownership through `sdk.members`; an owner cannot leave until ownership is transferred or the room is deleted.

Always close the SDK with the host lifecycle:

```dart
await sdk.close();
```

## Add reusable UI

Register the package delegates and locales, or merge them with the host app's delegates:

```dart
MaterialApp(
  locale: hostOverride,
  localizationsDelegates: StudyRoomLocalizations.localizationsDelegates,
  supportedLocales: StudyRoomLocalizations.supportedLocales,
  home: StudyRoomLobbyView(sdk: sdk, currentUserId: currentUserId),
)
```

Use `JoinRequestInboxView` for owners and `RoomMemberManagementView` for member removal and ownership transfer. `StudyFocusKitView` remains local-first and preserves the 0.3 SharedPreferences keys for the same `localStorageNamespace` and `currentUserId`.

See the example application for the owner/member route and the [migration guide](migration-0.3-to-0.4.md) for all breaking API changes.
