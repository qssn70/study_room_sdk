## 0.4.0-rc.1

- Renamed the public `StudyRoomAccessToken.value` constructor argument and field to `token`; the beta name has no compatibility alias.
- Aligned the SDK and generated contract version with the 0.4 release candidate.

## 0.4.0-beta.1

- Added generated OpenAPI/realtime wire adapters and contract drift checks.
- Added active-session paging, authoritative away presence, atomic reconnect synchronization, buffered event replay, and degraded recovery.
- Added refresh-aware token requests, generation-safe lifecycle management, abortable HTTP/realtime operations, and structured connect/ack errors.

## 0.4.0-alpha.1

- Replaced the 0.3 API with versioned `/v1` rooms, approval, members, sessions, and cursor-based chat services.
- Added `StudyRoomAccessToken`, refresh-aware `tokenProvider`, explicit `start()`/`close()`, timeouts, cancellation, injectable transports, and structured exceptions.
- Added acknowledged Socket.IO subscriptions, connection-state streams, expiry reconnection, and authoritative REST resynchronization.
- Preserved the 0.3 local focus data model and persisted-key compatibility.
