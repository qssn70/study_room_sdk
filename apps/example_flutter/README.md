# Study Room 0.4 example

Reference Flutter host for Web, Android, iOS, Windows, macOS, and Linux. The default route demonstrates the offline focus workspace; the live route exercises room creation, join approval, member removal, and ownership transfer.

```sh
flutter run -d chrome \
  --dart-define=STUDY_ROOM_API_URL=http://localhost:3000 \
  --dart-define=STUDY_ROOM_REALTIME_URL=ws://localhost:3000/v1/realtime \
  --dart-define=STUDY_ROOM_TOKEN=<jwt> \
  --dart-define=STUDY_ROOM_TOKEN_EXPIRES_AT=<unix-seconds> \
  --dart-define=STUDY_ROOM_USER_ID=<token-sub>
```

Obtain a development token from the Compose JWKS fixture as described in the repository README. Production applications must refresh tokens through their own backend.
