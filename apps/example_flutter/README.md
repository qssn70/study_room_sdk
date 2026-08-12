# Study Room 0.4 example

Reference Flutter host for Web, Android, iOS, Windows, macOS, and Linux. The default route is a two-user owner/member workbench backed by two independent SDK instances. It covers room creation, join approval, subscriptions, chat, sessions, Presence, removal, leaving, ownership transfer, and deletion. The offline focus workspace remains available from the timer icon.

```sh
flutter run -d chrome --web-port 8080 \
  --dart-define=STUDY_ROOM_API_URL=http://localhost:3000 \
  --dart-define=STUDY_ROOM_REALTIME_URL=ws://localhost:3000/v1/realtime \
  --dart-define=STUDY_ROOM_DEV_TOKEN_URL=http://localhost:4000/token
```

Start the repository's explicit Compose `dev` profile first. The workbench requests short-lived owner/member tokens from the development JWKS fixture, caches them only in memory, and honors SDK refresh requests. The endpoint fields are editable from the settings button. Production applications must refresh tokens through their own backend and must not expose a token-minting endpoint to clients.
