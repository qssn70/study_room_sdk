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

Use `StudyFocusKitView` for the complete experience, or compose `PomodoroTimerView`, `TodayGoalView`, `StudyStatsView`, `StudyAnalyticsView`, `StudyReportView`, `BackgroundSoundView`, `StudyBackgroundLayer`, and `SilentCompanionList`.

`StudyFocusKitView` includes the three visual styles from `docs/UI` and defaults to the recommended immersive dock layout:

```dart
StudyFocusKitView(
  visualStyle: StudyFocusVisualStyle.immersiveDock,
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
cd packages/study_room_sdk && dart test
cd ../study_room_ui && flutter test
cd ../../apps/example_flutter && flutter test
cd ../../server && npm test
```

The reference API listens on `http://localhost:3000`. OpenAPI docs are served from `/docs/openapi`.

## License Layout

- Flutter SDK and UI packages are intended for Apache-2.0 distribution.
- The reference backend in `server/` follows the repository GPL-3.0 license.
- Commercial/private backend licensing can be handled separately.

See `docs/getting-started.md` for integration details.
