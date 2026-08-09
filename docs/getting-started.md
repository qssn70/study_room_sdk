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

The backend only accepts HS256 tokens with a future `exp`. Configure
`STUDY_ROOM_JWT_SECRET` explicitly; Docker Compose supplies `dev-secret` for
local development.

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
await sdk.client.joinRoom('room-2');

sdk.client.roomStateFor('room-1').listen((room) {
  // This stream cannot be overwritten by room-2 events.
});
sdk.client.memberEventsFor('room-1').listen((event) {
  print('${event.roomId}: ${event.member.status.name}');
});

sdk.client.updatePresence('room-1', PresenceStatus.focusing);
final history = await sdk.client.chat('room-1').loadHistory();

// Exits both local tracking and the realtime channel before REST leave.
await sdk.client.leaveRoom('room-1');
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
  currentUserId: 'user-1',
  localStorageNamespace: 'your-app',
  room: room,
  showCompanions: true,
  onPresenceChanged: (status) {
    sdk.client.updatePresence(room.id, status);
  },
  onPresenceError: (error, stackTrace) {
    reportError(error, stackTrace);
  },
)
```

Omit `store` to use isolated SharedPreferences persistence:

```dart
StudyFocusKitView(
  currentUserId: 'user-1',
  localStorageNamespace: 'your-app',
  room: room,
)
```

On wide landscape screens the kit exposes four desktop pages: Focus,
Analytics, 30-day History with task CRUD, and Settings. Use `desktopSection`
for controlled navigation, `onDesktopSectionChanged` for notifications, and
`desktopPageBuilder` to wrap or replace a default page. On smaller screens the
same Pomodoro, goal, analytics, sound, background, and companion modules remain
available.

Personal analytics and tasks are local to the current user and are not sent to
the room. Pomodoro state drives `focusing`/`idle`; inactive, hidden, and paused
application lifecycle states drive `away`. Duplicate callbacks are suppressed.

Use `SharedPreferencesStudyStore` from `study_room_ui` for default Flutter
persistence. Its required `StudyStorageScope.user` or `StudyStorageScope.guest`
keeps users and host namespaces separate. On upgrade, legacy `study_focus:*`
keys are migrated once to the first non-guest user; guest data never claims
legacy keys. Core SDK logic depends only on `StudyStore`, so host apps can
provide their own isolated storage implementation.

### Custom Store migration for 0.3.0

`StudyStore` is intentionally source-breaking in 0.3.0. Existing custom stores
must add the change stream, task deletion, and settings methods:

```dart
final changes = StreamController<StudyStoreChange>.broadcast();

@override
Stream<StudyStoreChange> get changes => changes.stream;

@override
Future<void> deleteTaskRecord(DateTime date, String taskId) async {
  await database.deleteTask(date, taskId);
  changes.add(StudyStoreChange(StudyStoreChangeKind.tasks, date: date));
}

@override
Future<StudyFocusSettings> loadSettings() => database.loadFocusSettings();

@override
Future<void> saveSettings(StudyFocusSettings value) async {
  await database.saveFocusSettings(value);
  changes.add(StudyStoreChange(StudyStoreChangeKind.settings));
}
```

Apply the same rule to existing goal, day-record, and task writes: broadcast
exactly once after persistence succeeds, never before it and never after a
failed write. Date-bearing changes must use the affected local date. Custom
stores remain responsible for user and tenant isolation.

Background sounds use bundled `study_room_ui` assets and `just_audio` by default. Pass custom `StudySoundTrack.network`, `StudySoundTrack.file`, or `StudySoundTrack.uri` values to add host-provided sources.

Backgrounds are configured with `StudyBackground.color`, `StudyBackground.image`, or `StudyBackground.gradient`. `maskOpacity` is clamped to `0.0..0.85` to keep foreground UI readable.

Use stable `StudyBackgroundOption.id` values when supplying a custom
background catalog. Deleted or unknown sound/background/navigation values
fall back safely; restored sound settings never start playback automatically.

`SilentCompanionList` reuses `StudyRoom.members` and filters out the current user and offline members. It only shows avatars, nicknames, and status visuals.
