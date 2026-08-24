import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_room_sdk/study_room_sdk.dart';

/// Stable SharedPreferences identity composed from a namespace and user/guest.
class StudyStorageScope {
  factory StudyStorageScope.user({
    required String userId,
    String namespace = 'default',
  }) {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'User id cannot be empty');
    }
    return StudyStorageScope._(
      namespace: _normalizeNamespace(namespace),
      userId: normalizedUserId,
      isGuest: false,
    );
  }

  factory StudyStorageScope.guest({String namespace = 'default'}) {
    return StudyStorageScope._(
      namespace: _normalizeNamespace(namespace),
      userId: '',
      isGuest: true,
    );
  }

  const StudyStorageScope._({
    required this.namespace,
    required this.userId,
    required this.isGuest,
  });

  final String namespace;
  final String userId;
  final bool isGuest;

  String get storagePrefix {
    final namespacePart = _encodeKeyPart(namespace);
    final identityPart = isGuest ? 'guest' : 'user:${_encodeKeyPart(userId)}';
    return 'study_focus:v2:$namespacePart:$identityPart';
  }

  String get migrationMarker {
    return 'study_focus:v2:migration:${_encodeKeyPart(namespace)}';
  }

  static String _normalizeNamespace(String namespace) {
    final normalized = namespace.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(
        namespace,
        'namespace',
        'Namespace cannot be empty',
      );
    }
    return normalized;
  }

  static String _encodeKeyPart(String value) {
    return base64Url.encode(utf8.encode(value)).replaceAll('=', '');
  }
}

/// Scoped SharedPreferences implementation of [StudyBackupStore].
///
/// The caller owns [preferences]. Store instances coordinate mutations across
/// the same scope, retain migration markers during replace imports, and expose
/// plaintext backups whose encryption and transport remain the host's duty.
class SharedPreferencesStudyStore implements StudyBackupStore {
  SharedPreferencesStudyStore(this.preferences, {required this.scope});

  static Future<void>? _activeMigration;

  final SharedPreferences preferences;
  final StudyStorageScope scope;
  final _changes = StreamController<StudyStoreChange>.broadcast(sync: true);

  @override
  Stream<StudyStoreChange> get changes => _changes.stream;

  static Future<void> migrateLegacyData(
    SharedPreferences preferences, {
    required StudyStorageScope scope,
  }) {
    if (scope.isGuest || preferences.getBool(scope.migrationMarker) == true) {
      return Future<void>.value();
    }
    final running = _activeMigration;
    if (running != null) {
      return running.then((_) => migrateLegacyData(preferences, scope: scope));
    }
    final migration = _performLegacyMigration(preferences, scope);
    _activeMigration = migration;
    return migration.whenComplete(() {
      if (identical(_activeMigration, migration)) {
        _activeMigration = null;
      }
    });
  }

  static Future<void> _performLegacyMigration(
    SharedPreferences preferences,
    StudyStorageScope scope,
  ) async {
    final legacyKeys = preferences
        .getKeys()
        .where(
          (key) =>
              key.startsWith('study_focus:goal:') ||
              key.startsWith('study_focus:record:') ||
              key.startsWith('study_focus:task:'),
        )
        .toList(growable: false);
    for (final legacyKey in legacyKeys) {
      final suffix = legacyKey.substring('study_focus:'.length);
      final targetKey = '${scope.storagePrefix}:$suffix';
      final value = preferences.getString(legacyKey);
      if (value != null && !preferences.containsKey(targetKey)) {
        final copied = await preferences.setString(targetKey, value);
        if (!copied) {
          throw StateError('Failed to migrate local study data');
        }
      }
    }
    for (final legacyKey in legacyKeys) {
      final removed = await preferences.remove(legacyKey);
      if (!removed) {
        throw StateError('Failed to remove migrated local study data');
      }
    }
    final marked = await preferences.setBool(scope.migrationMarker, true);
    if (!marked) {
      throw StateError('Failed to finish local study data migration');
    }
  }

  @override
  Future<TodayGoal> loadTodayGoal(DateTime date) async {
    final raw = preferences.getString(_goalKey(date));
    if (raw == null) {
      return const TodayGoal();
    }
    return TodayGoal.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> saveTodayGoal(DateTime date, TodayGoal goal) =>
      _StudyStoreMutationCoordinator.runDate(
        scope.storagePrefix,
        date,
        () async {
          await _writeString(_goalKey(date), jsonEncode(goal.toJson()));
          _changes.add(StudyStoreChange(StudyStoreChangeKind.goal, date: date));
        },
      );

  @override
  Future<StudyDayRecord> loadDayRecord(DateTime date) async {
    final raw = preferences.getString(_recordKey(date));
    if (raw == null) {
      return StudyDayRecord(date: _dateOnly(date));
    }
    return StudyDayRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<List<StudyDayRecord>> loadDayRecords({
    required DateTime start,
    required DateTime end,
  }) async {
    final records = <StudyDayRecord>[];
    var cursor = _dateOnly(start);
    final last = _dateOnly(end);
    while (!cursor.isAfter(last)) {
      records.add(await loadDayRecord(cursor));
      cursor = cursor.add(const Duration(days: 1));
    }
    return records;
  }

  @override
  Future<void> saveDayRecord(StudyDayRecord record) =>
      _StudyStoreMutationCoordinator.runDate(
        scope.storagePrefix,
        record.date,
        () => _saveDayRecord(record),
      );

  @override
  Future<void> addFocusSession(
    DateTime date,
    Duration duration, {
    int pomodoros = 1,
  }) => _StudyStoreMutationCoordinator.runDate(
    scope.storagePrefix,
    date,
    () async {
      final current = await loadDayRecord(date);
      await _saveDayRecord(
        current.copyWith(
          focusDuration: current.focusDuration + duration,
          pomodoroCount: current.pomodoroCount + pomodoros,
        ),
      );
    },
  );

  @override
  Future<List<StudyTaskRecord>> loadTaskRecords(DateTime date) async {
    final raw = preferences.getString(_taskKey(date));
    if (raw == null) {
      return const [];
    }
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(StudyTaskRecord.fromJson)
        .toList(growable: false);
  }

  @override
  Future<void> saveTaskRecord(DateTime date, StudyTaskRecord task) async {
    return _StudyStoreMutationCoordinator.runDate(
      scope.storagePrefix,
      date,
      () async {
        final tasks = List<StudyTaskRecord>.of(await loadTaskRecords(date));
        final index = tasks.indexWhere((existing) => existing.id == task.id);
        if (index == -1) {
          tasks.add(task);
        } else {
          tasks[index] = task;
        }
        await _saveTasks(date, tasks);
        _changes.add(StudyStoreChange(StudyStoreChangeKind.tasks, date: date));
      },
    );
  }

  @override
  Future<void> deleteTaskRecord(DateTime date, String taskId) {
    return _StudyStoreMutationCoordinator.runDate(
      scope.storagePrefix,
      date,
      () async {
        final tasks = List<StudyTaskRecord>.of(await loadTaskRecords(date))
          ..removeWhere((task) => task.id == taskId);
        await _saveTasks(date, tasks);
        _changes.add(StudyStoreChange(StudyStoreChangeKind.tasks, date: date));
      },
    );
  }

  @override
  Future<StudyFocusSettings> loadSettings() async {
    final raw = preferences.getString(_settingsKey);
    if (raw == null) {
      return StudyFocusSettings();
    }
    try {
      return StudyFocusSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return StudyFocusSettings();
    }
  }

  @override
  Future<void> saveSettings(StudyFocusSettings settings) =>
      _StudyStoreMutationCoordinator.runScope(scope.storagePrefix, () async {
        await _writeString(_settingsKey, jsonEncode(settings.toJson()));
        _changes.add(StudyStoreChange(StudyStoreChangeKind.settings));
      });

  @override
  Future<StudyDataBackup> exportBackup() =>
      _StudyStoreMutationCoordinator.runScope(
        scope.storagePrefix,
        _exportBackup,
      );

  @override
  Future<void> importBackup(
    StudyDataBackup backup, {
    StudyBackupImportMode mode = StudyBackupImportMode.merge,
  }) => _StudyStoreMutationCoordinator.runScope(
    scope.storagePrefix,
    () => _importBackup(backup, mode),
  );

  Future<StudyDataBackup> _exportBackup() async {
    final goals = <String, TodayGoal>{};
    final records = <StudyDayRecord>[];
    final tasks = <String, List<StudyTaskRecord>>{};
    final keys = _dataKeys().toList()..sort();
    for (final key in keys) {
      final raw = preferences.getString(key);
      if (raw == null) continue;
      final descriptor = _descriptorForKey(key);
      if (descriptor == null) continue;
      final value = jsonDecode(raw);
      switch (descriptor.kind) {
        case StudyStoreChangeKind.goal:
          if (value is! Map) {
            throw FormatException('Invalid stored goal: $key');
          }
          goals[descriptor.dateKey!] = TodayGoal.fromJson(
            Map<String, dynamic>.from(value),
          );
        case StudyStoreChangeKind.dayRecord:
          if (value is! Map) {
            throw FormatException('Invalid stored day record: $key');
          }
          records.add(
            StudyDayRecord.fromJson(Map<String, dynamic>.from(value)),
          );
        case StudyStoreChangeKind.tasks:
          if (value is! List) {
            throw FormatException('Invalid stored task list: $key');
          }
          tasks[descriptor.dateKey!] = value
              .map((task) {
                if (task is! Map) {
                  throw FormatException('Invalid stored task: $key');
                }
                return StudyTaskRecord.fromJson(
                  Map<String, dynamic>.from(task),
                );
              })
              .toList(growable: false);
        case StudyStoreChangeKind.settings:
          break;
      }
    }
    final rawSettings = preferences.getString(_settingsKey);
    final settings = rawSettings == null
        ? StudyFocusSettings()
        : StudyFocusSettings.fromJson(
            Map<String, dynamic>.from(jsonDecode(rawSettings) as Map),
          );
    return StudyDataBackup(
      exportedAt: DateTime.now().toUtc(),
      goalsByDate: goals,
      dayRecords: records,
      tasksByDate: tasks,
      settings: settings,
    );
  }

  Future<void> _importBackup(
    StudyDataBackup backup,
    StudyBackupImportMode mode,
  ) async {
    final tasksByDate = <String, List<StudyTaskRecord>>{};
    for (final entry in backup.tasksByDate.entries) {
      final date = _parseDateKey(entry.key);
      final tasks = mode == StudyBackupImportMode.merge
          ? List<StudyTaskRecord>.of(await loadTaskRecords(date))
          : <StudyTaskRecord>[];
      for (final importedTask in entry.value) {
        final index = tasks.indexWhere(
          (existingTask) => existingTask.id == importedTask.id,
        );
        if (index == -1) {
          tasks.add(importedTask);
        } else {
          tasks[index] = importedTask;
        }
      }
      tasksByDate[entry.key] = tasks;
    }
    final values = <String, String>{
      for (final entry in backup.goalsByDate.entries)
        _goalKey(_parseDateKey(entry.key)): jsonEncode(entry.value.toJson()),
      for (final record in backup.dayRecords)
        _recordKey(record.date): jsonEncode(record.toJson()),
      for (final entry in tasksByDate.entries)
        _taskKey(_parseDateKey(entry.key)): jsonEncode(
          entry.value.map((task) => task.toJson()).toList(growable: false),
        ),
      _settingsKey: jsonEncode(backup.settings.toJson()),
    };
    final existing = _dataKeys().toSet();
    final removals = mode == StudyBackupImportMode.replace
        ? existing.difference(values.keys.toSet())
        : <String>{};
    final touched = <String>{...values.keys, ...removals};
    final snapshot = <String, String?>{
      for (final key in touched) key: preferences.getString(key),
    };
    try {
      for (final key in removals) {
        if (!await preferences.remove(key)) {
          throw StateError('Failed to remove local study data');
        }
      }
      for (final entry in values.entries) {
        await _writeString(entry.key, entry.value);
      }
    } catch (error, stackTrace) {
      try {
        await _restoreSnapshot(snapshot);
      } catch (rollbackError) {
        Error.throwWithStackTrace(
          StateError(
            'Study backup import failed and rollback failed: $rollbackError',
          ),
          stackTrace,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    _publishImportedChanges(touched);
  }

  Future<void> _restoreSnapshot(Map<String, String?> snapshot) async {
    for (final entry in snapshot.entries) {
      final previous = entry.value;
      if (previous == null) {
        if (preferences.containsKey(entry.key) &&
            !await preferences.remove(entry.key)) {
          throw StateError('Failed to roll back imported study data');
        }
      } else if (!await preferences.setString(entry.key, previous)) {
        throw StateError('Failed to roll back imported study data');
      }
    }
  }

  void _publishImportedChanges(Set<String> touched) {
    final emitted = <String>{};
    for (final key in touched) {
      final descriptor = _descriptorForKey(key);
      if (descriptor == null) continue;
      final signature = '${descriptor.kind.name}:${descriptor.dateKey ?? ''}';
      if (!emitted.add(signature)) continue;
      _changes.add(
        StudyStoreChange(
          descriptor.kind,
          date: descriptor.dateKey == null
              ? null
              : _parseDateKey(descriptor.dateKey!),
        ),
      );
    }
  }

  Future<void> _saveDayRecord(StudyDayRecord record) async {
    await _writeString(_recordKey(record.date), jsonEncode(record.toJson()));
    _changes.add(
      StudyStoreChange(StudyStoreChangeKind.dayRecord, date: record.date),
    );
  }

  Future<void> _saveTasks(DateTime date, List<StudyTaskRecord> tasks) {
    return _writeString(
      _taskKey(date),
      jsonEncode(tasks.map((task) => task.toJson()).toList(growable: false)),
    );
  }

  Future<void> _writeString(String key, String value) async {
    if (!await preferences.setString(key, value)) {
      throw StateError('Failed to persist local study data');
    }
  }

  String _goalKey(DateTime date) =>
      '${scope.storagePrefix}:goal:${_dateKey(date)}';

  String _recordKey(DateTime date) =>
      '${scope.storagePrefix}:record:${_dateKey(date)}';

  String _taskKey(DateTime date) =>
      '${scope.storagePrefix}:task:${_dateKey(date)}';

  String get _settingsKey => '${scope.storagePrefix}:settings';

  Iterable<String> _dataKeys() =>
      preferences.getKeys().where((key) => _descriptorForKey(key) != null);

  _StoredDataDescriptor? _descriptorForKey(String key) {
    final prefix = '${scope.storagePrefix}:';
    if (!key.startsWith(prefix)) return null;
    final suffix = key.substring(prefix.length);
    if (suffix == 'settings') {
      return const _StoredDataDescriptor(StudyStoreChangeKind.settings);
    }
    for (final entry in const {
      'goal:': StudyStoreChangeKind.goal,
      'record:': StudyStoreChangeKind.dayRecord,
      'task:': StudyStoreChangeKind.tasks,
    }.entries) {
      if (suffix.startsWith(entry.key)) {
        final dateKey = suffix.substring(entry.key.length);
        _parseDateKey(dateKey);
        return _StoredDataDescriptor(entry.value, dateKey);
      }
    }
    return null;
  }
}

class _StoredDataDescriptor {
  const _StoredDataDescriptor(this.kind, [this.dateKey]);

  final StudyStoreChangeKind kind;
  final String? dateKey;
}

class _StudyStoreMutationCoordinator {
  static final _scopeTails = <String, Future<void>>{};
  static final _dateTails = <String, Future<void>>{};

  static Future<T> runDate<T>(
    String scope,
    DateTime date,
    Future<T> Function() action,
  ) {
    final key = '$scope\u0000${_dateKey(date)}';
    final barriers = <Future<void>>[
      _scopeTails[scope] ?? Future<void>.value(),
      _dateTails[key] ?? Future<void>.value(),
    ];
    final operation = Future.wait(barriers).then((_) => action());
    final tail = operation.then<void>((_) {}, onError: (_, _) {});
    _dateTails[key] = tail;
    unawaited(
      tail.whenComplete(() {
        if (identical(_dateTails[key], tail)) _dateTails.remove(key);
      }),
    );
    return operation;
  }

  static Future<T> runScope<T>(String scope, Future<T> Function() action) {
    final datePrefix = '$scope\u0000';
    final barriers = <Future<void>>[
      _scopeTails[scope] ?? Future<void>.value(),
      ..._dateTails.entries
          .where((entry) => entry.key.startsWith(datePrefix))
          .map((entry) => entry.value),
    ];
    final operation = Future.wait(barriers).then((_) => action());
    final tail = operation.then<void>((_) {}, onError: (_, _) {});
    _scopeTails[scope] = tail;
    unawaited(
      tail.whenComplete(() {
        if (identical(_scopeTails[scope], tail)) _scopeTails.remove(scope);
      }),
    );
    return operation;
  }
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

String _dateKey(DateTime date) {
  final day = _dateOnly(date);
  return '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
}

DateTime _parseDateKey(String key) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(key);
  if (match == null) throw FormatException('Invalid study date: $key');
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final value = DateTime(year, month, day);
  if (value.year != year || value.month != month || value.day != day) {
    throw FormatException('Invalid study date: $key');
  }
  return value;
}
