# Local backup and create idempotency

## Study data backup

`StudyBackupStore` is an optional capability and does not change the existing
`StudyStore` contract. `MemoryStudyStore` and `SharedPreferencesStudyStore`
implement it.

```dart
if (store case final StudyBackupStore backupStore) {
  final backup = await backupStore.exportBackup();
  final jsonText = jsonEncode(backup.toJson());

  final decoded = StudyDataBackup.fromJson(
    Map<String, dynamic>.from(jsonDecode(jsonText) as Map),
  );
  await backupStore.importBackup(
    decoded,
    mode: StudyBackupImportMode.merge,
  );
}
```

Schema version 1 contains the export timestamp, daily goals and records, tasks
grouped by date, and focus settings. It deliberately contains no user ID or
namespace: importing into a Store selects the destination identity. This also
allows a deliberate cross-user restore chosen by the host.

`merge` overwrites matching dates and matching task IDs while retaining other
local dates and tasks. `replace` clears study data only in the destination scope
before importing and preserves SharedPreferences migration markers. Imports
validate the whole document before writing. SharedPreferences imports roll back
all touched values and publish no change events if any write fails.

The JSON is plaintext personal study information. The SDK does not encrypt,
upload, retain, or authorize it. Hosts must provide encryption at rest and in
transit, access control, retention policy, and user-facing consent.

## Idempotent creates

The following calls accept an optional key:

```dart
final room = await sdk.rooms.create(
  'Exam preparation',
  idempotencyKey: operationId,
);
final message = await sdk.chat.send(
  room.id,
  'Starting now',
  idempotencyKey: messageOperationId,
);
final session = await sdk.sessions.start(
  room.id,
  idempotencyKey: sessionOperationId,
);
```

Keys must contain 1–128 characters from `[A-Za-z0-9._:-]`. Generate a new key
for each intended create and reuse it only while retrying the same normalized
request. Omitting a key keeps 0.4.0 behavior.

The server isolates keys by tenant, user, and operation. The first request
creates the resource, audit entry, idempotency record, and realtime event in one
transaction. A matching retry returns the resource's current representation
without publishing another event. Reusing a key for a different request returns
`409 / idempotency_conflict`; if the original resource is no longer available,
the response is `409 / idempotency_result_unavailable`. Records expire after 24
hours, so callers must not use the retention window as permanent deduplication.
