# Study Room SDK

Flutter SDK, optional Flutter widgets, and a NestJS reference backend for adding online study rooms to another app.

## Packages

- `packages/study_room_sdk`: core Flutter SDK for auth, REST, realtime streams, room state, study sessions, and chat.
- `packages/study_room_ui`: optional Flutter widgets built on the SDK domain models.
- `apps/example_flutter`: minimal integration example.
- `server`: NestJS reference backend with REST and Socket.IO realtime endpoints.

## Minimal Study Focus Kit

The Flutter packages also include a local-first focus kit that can be embedded without changing the backend:

- Pomodoro timer with 25/5, 50/10, and custom configs.
- Today goal, study records, personal analytics, and day/week/month reports.
- Background sound library with Rain, White noise, Cafe, Library, and Keyboard built-in loops plus custom sources.
- Color, image, and gradient backgrounds with a readability mask.
- Optional silent companion list based on existing `StudyRoom.members` and `PresenceStatus`.
- A four-page desktop workspace for focus, analytics, 30-day history/tasks, and settings.
- User-scoped persistence for tasks, sound/volume, background/mask, and desktop navigation.

Use `StudyFocusKitView` for the complete experience, or compose `PomodoroTimerView`, `TodayGoalView`, `StudyStatsView`, `StudyAnalyticsView`, `StudyReportView`, `BackgroundSoundView`, `StudyBackgroundLayer`, and `SilentCompanionList`.

`StudyFocusKitView` includes the three visual styles documented in
[`docs/ui-design`](docs/ui-design/) and defaults to the recommended immersive
dock layout:

```dart
StudyFocusKitView(
  visualStyle: StudyFocusVisualStyle.immersiveDock,
  currentUserId: currentUser.id,
  localStorageNamespace: 'my-app',
)
```

The default background is exposed as `studyFocusDefaultBackground`, backed by
`studyFocusDefaultBackgroundImageUrl`:

```text
https://images.unsplash.com/photo-1419242902214-272b3f66ee7a?q=80&w=2000&auto=format&fit=crop
```

Apps can still override it with any supported `StudyBackground`:

```dart
StudyFocusKitView(
  background: StudyBackground.image(image: myImageProvider),
)
```

Downstream apps can switch freely between:

- `StudyFocusVisualStyle.split`: portrait top/bottom split layout.
- `StudyFocusVisualStyle.centered`: portrait core-centered layout.
- `StudyFocusVisualStyle.immersiveDock`: recommended immersive bottom-docked layout.

## Quick Start

```sh
docker compose up --build
cd server && npm ci
cd ..
cd packages/study_room_sdk && dart test
cd ../study_room_ui && flutter test
cd ../../apps/example_flutter && flutter test
cd ../../server && npm test
```

The reference API listens on `http://localhost:3000`. OpenAPI docs are served from `/docs/openapi`.

Version 0.3 requires expiring HS256 JWTs for both REST and Socket.IO. It adds
multi-room realtime subscriptions, room-aware member events, chat history,
and `online`/`focusing`/`idle`/`away`/`offline` presence aggregation. Local
focus data is isolated by `localStorageNamespace` and `currentUserId`; an
empty user id uses a separate guest scope.

## License Layout

- Flutter SDK and UI packages are intended for Apache-2.0 distribution.
- The reference backend in `server/` follows the repository GPL-3.0 license.
- Commercial/private backend licensing can be handled separately.

See the [documentation index](docs/README.md) for integration details, API
contracts, deployment guidance, realtime events, and UI design notes.
