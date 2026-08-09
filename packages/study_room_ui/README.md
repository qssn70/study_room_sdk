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

The package ships Simplified Chinese and English resources and follows the host locale unless the host overrides `MaterialApp.locale`.

Licensed under Apache-2.0.
