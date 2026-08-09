# HTTP API contract

[`contracts/openapi.yaml`](../contracts/openapi.yaml) is the authoritative OpenAPI 3.1 contract. `npm run generate:contracts` produces low-level TypeScript and Dart wire types; `npm run check:contracts` fails when generated files drift.

All successful application endpoints are under `/v1`:

- `POST/GET /v1/rooms`, `GET/DELETE /v1/rooms/{roomId}`
- `POST/GET/DELETE /v1/rooms/{roomId}/join-requests`
- `PATCH /v1/rooms/{roomId}/join-requests/{requestId}`
- `GET /v1/join-requests`
- `DELETE /v1/rooms/{roomId}/members/me`
- `DELETE /v1/rooms/{roomId}/members/{userId}`
- `PUT /v1/rooms/{roomId}/owner`
- `POST /v1/rooms/{roomId}/sessions`, `GET /v1/rooms/{roomId}/active-sessions`, `PATCH /v1/sessions/{sessionId}`
- `GET/POST /v1/rooms/{roomId}/messages`

Management uses `POST/GET /admin/v1/apps` and `GET/PATCH /admin/v1/apps/{appId}`. Application IDs are immutable and applications are disabled rather than deleted.

Room titles contain 1–100 characters after trimming. Messages contain 1–2000 characters. Cursor pages default to 50 and cap at 100. A room has exactly one owner; an owner must transfer ownership or delete the room before leaving.

Every error has this shape and returns its request ID in both JSON and `x-request-id`:

```json
{
  "code": "membership_required",
  "message": "Room membership is required",
  "details": null,
  "requestId": "6e997d45-2d84-4cb8-a724-f03b70c9b193"
}
```

`details` is omitted when there is no safe structured detail.
