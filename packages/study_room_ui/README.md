# study_room_ui

Reusable Flutter widgets for `study_room_sdk`: a responsive room lobby, join-request status, owner approval inbox, member removal and ownership transfer, plus the local-first focus workspace.

```dart
MaterialApp(
  localizationsDelegates: StudyRoomLocalizations.localizationsDelegates,
  supportedLocales: StudyRoomLocalizations.supportedLocales,
  home: StudyRoomLobbyView(
    sdk: sdk,
    currentUserId: currentUserId,
  ),
)
```

Use `JoinRequestInboxView` and `RoomMemberManagementView` on owner routes. `StudyFocusKitView` supports responsive phone/desktop layouts, keyboard focus, text scaling, offline gradients, bundled audio, local analytics, and user-scoped SharedPreferences persistence.

The focus workspace is split into independent coordinator, responsive-layout,
desktop, timer/goal, persistence, audio, background, and public compatibility
libraries. Package-internal immutable models and action callbacks connect those
libraries; the internal contracts are intentionally not exported from the
package barrel.

The package ships Simplified Chinese and English resources and follows the host locale unless the host overrides `MaterialApp.locale`.

## Golden tests

The eight-scenario Golden harness is skipped by default for local portability.
Ubuntu CI must enable it explicitly; missing baselines or visual differences then
fail the run:

```sh
flutter test test/golden/study_room_golden_harness_test.dart \
  --dart-define=STUDY_ROOM_RUN_GOLDENS=true
```

Create or deliberately update baselines only on Ubuntu with the CI-pinned
Flutter 3.44.1 toolchain:

```sh
flutter test test/golden/study_room_golden_harness_test.dart \
  --dart-define=STUDY_ROOM_RUN_GOLDENS=true --update-goldens
```

Licensed under Apache-2.0.
