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
Ubuntu CI enables it explicitly; missing baselines, unexpected baseline files,
or visual differences fail the run:

```sh
flutter test test/golden/study_room_golden_harness_test.dart \
  --dart-define=STUDY_ROOM_RUN_GOLDENS=true
```

Create or deliberately update baselines only through the repository's **CI**
workflow so they use the pinned Ubuntu and Flutter 3.44.1 environment:

1. Open the **CI** workflow in GitHub Actions and choose **Run workflow** for the
   commit that needs baselines.
2. Enable **Generate the eight Ubuntu Golden baselines for review** and start
   the run.
3. Download the `golden-baselines-<commit SHA>` artifact. The generation job
   verifies that all eight expected PNGs exist and immediately runs the normal
   comparison test against them.
4. Review every image for clipping, overlap, blank output, font anomalies, and
   unintended visual changes. Then place only the approved PNGs in
   `test/golden/baselines/` and commit them.

Pull requests, pushes to `main`, and manual runs without that option are always
comparison-only and never update accepted images. Failed comparison runs upload
a `golden-failure-<commit SHA>` artifact containing expected, actual, and diff
images for diagnosis.

Licensed under Apache-2.0.
