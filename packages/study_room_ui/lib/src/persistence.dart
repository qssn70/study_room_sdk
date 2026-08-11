import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_room_sdk/study_room_sdk.dart';

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

class SharedPreferencesStudyStore implements StudyStore {
  SharedPreferencesStudyStore(this.preferences, {required this.scope});

  static Future<void>? _activeMigration;
  static final _taskMutations = <String, Future<void>>{};

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
  Future<void> saveTodayGoal(DateTime date, TodayGoal goal) async {
    await _writeString(_goalKey(date), jsonEncode(goal.toJson()));
    _changes.add(StudyStoreChange(StudyStoreChangeKind.goal, date: date));
  }

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
  Future<void> saveDayRecord(StudyDayRecord record) async {
    await _writeString(_recordKey(record.date), jsonEncode(record.toJson()));
    _changes.add(
      StudyStoreChange(StudyStoreChangeKind.dayRecord, date: record.date),
    );
  }

  @override
  Future<void> addFocusSession(
    DateTime date,
    Duration duration, {
    int pomodoros = 1,
  }) async {
    final current = await loadDayRecord(date);
    await saveDayRecord(
      current.copyWith(
        focusDuration: current.focusDuration + duration,
        pomodoroCount: current.pomodoroCount + pomodoros,
      ),
    );
  }

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
    return _serializeTaskMutation(() async {
      final tasks = List<StudyTaskRecord>.of(await loadTaskRecords(date));
      final index = tasks.indexWhere((existing) => existing.id == task.id);
      if (index == -1) {
        tasks.add(task);
      } else {
        tasks[index] = task;
      }
      await _saveTasks(date, tasks);
      _changes.add(StudyStoreChange(StudyStoreChangeKind.tasks, date: date));
    });
  }

  @override
  Future<void> deleteTaskRecord(DateTime date, String taskId) {
    return _serializeTaskMutation(() async {
      final tasks = List<StudyTaskRecord>.of(await loadTaskRecords(date))
        ..removeWhere((task) => task.id == taskId);
      await _saveTasks(date, tasks);
      _changes.add(StudyStoreChange(StudyStoreChangeKind.tasks, date: date));
    });
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
  Future<void> saveSettings(StudyFocusSettings settings) async {
    await _writeString(_settingsKey, jsonEncode(settings.toJson()));
    _changes.add(StudyStoreChange(StudyStoreChangeKind.settings));
  }

  Future<void> _saveTasks(DateTime date, List<StudyTaskRecord> tasks) {
    return _writeString(
      _taskKey(date),
      jsonEncode(tasks.map((task) => task.toJson()).toList(growable: false)),
    );
  }

  Future<void> _serializeTaskMutation(Future<void> Function() action) {
    final mutationKey = scope.storagePrefix;
    final previous = _taskMutations[mutationKey] ?? Future<void>.value();
    final operation = previous.then((_) => action());
    _taskMutations[mutationKey] = operation.then<void>(
      (_) {},
      onError: (_, __) {},
    );
    return operation;
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
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

String _dateKey(DateTime date) {
  final day = _dateOnly(date);
  return '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
}
