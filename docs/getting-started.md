# Getting Started

## Backend

Start the reference stack:

```sh
docker compose up --build
```

The Docker Compose file starts:

- NestJS API on `http://localhost:3000`
- PostgreSQL on `localhost:5432`
- Redis on `localhost:6379`

The current reference implementation keeps room/session/chat state in memory so the SDK contract is easy to run locally. `DATABASE_URL` and `REDIS_URL` are already wired in Docker Compose as the production persistence and presence extension points.

## Identity

The SDK expects your application server to issue a short-lived JWT. Required claims:

```json
{
  "sub": "user-1",
  "appId": "your-app",
  "displayName": "Lin",
  "avatarUrl": "https://example.com/avatar.png",
  "exp": 1781766000
}
```

For local development the backend verifies tokens with `STUDY_ROOM_JWT_SECRET`, defaulting to `dev-secret`.

## Flutter SDK

```dart
final sdk = StudyRoomSdk.initialize(
  StudyRoomConfig(
    apiBaseUrl: Uri.parse('http://localhost:3000'),
    realtimeUrl: Uri.parse('ws://localhost:3000/realtime'),
    tokenProvider: fetchJwtFromYourAppServer,
  ),
);

final room = await sdk.client.joinRoom('room-1');
sdk.client.roomStateStream.listen((room) {
  // Update host app state.
});
```

## Optional UI

Use `StudyRoomView` for a complete screen, or compose smaller widgets:

- `RoomHeader`
- `MemberGrid`
- `FocusTimer`
- `ChatPanel`

## Minimal Study Focus Kit

For a local-first personal study experience, embed the full kit:

```dart
StudyFocusKitView(
  store: MemoryStudyStore(),
  currentUserId: 'user-1',
  room: room,
  showCompanions: true,
)
```

The kit renders seven modules: Pomodoro, Today goal, Study records, Personal analytics, Background sound, Background, and Companions. Personal analytics are local to the current user and are not written into room presence or shown to other users.

Use `SharedPreferencesStudyStore` from `study_room_ui` for default Flutter persistence. Core SDK logic depends only on the `StudyStore` interface, so host apps can provide their own storage implementation.

Background sounds use bundled `study_room_ui` assets and `just_audio` by default. Pass custom `StudySoundTrack.network`, `StudySoundTrack.file`, or `StudySoundTrack.uri` values to add host-provided sources.

Backgrounds are configured with `StudyBackground.color`, `StudyBackground.image`, or `StudyBackground.gradient`. `maskOpacity` is clamped to `0.0..0.85` to keep foreground UI readable.

`SilentCompanionList` reuses `StudyRoom.members` and filters out the current user and offline members. It only shows avatars, nicknames, and status visuals.
