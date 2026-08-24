import 'dart:async';

import 'errors.dart';

/// Built-in timer duration presets.
enum PomodoroPreset { twentyFiveFive, fiftyTen, custom }

/// Current timer lifecycle state.
enum PomodoroStatus { idle, focusing, paused, breaking, finished }

/// Validated focus/break durations and their selected preset.
class PomodoroConfig {
  factory PomodoroConfig({
    Duration focusDuration = const Duration(minutes: 25),
    Duration breakDuration = const Duration(minutes: 5),
    PomodoroPreset preset = PomodoroPreset.twentyFiveFive,
  }) {
    _validateDurations(focusDuration, breakDuration);
    return PomodoroConfig._(
      focusDuration: focusDuration,
      breakDuration: breakDuration,
      preset: preset,
    );
  }

  factory PomodoroConfig.fiftyTen() => PomodoroConfig(
    focusDuration: const Duration(minutes: 50),
    breakDuration: const Duration(minutes: 10),
    preset: PomodoroPreset.fiftyTen,
  );

  factory PomodoroConfig.custom({
    required Duration focusDuration,
    required Duration breakDuration,
  }) => PomodoroConfig(
    focusDuration: focusDuration,
    breakDuration: breakDuration,
    preset: PomodoroPreset.custom,
  );

  const PomodoroConfig._({
    required this.focusDuration,
    required this.breakDuration,
    required this.preset,
  });

  final Duration focusDuration;
  final Duration breakDuration;
  final PomodoroPreset preset;

  static void _validateDurations(Duration focus, Duration rest) {
    if (focus <= Duration.zero) {
      throw const StudyRoomError(
        'Focus duration must be greater than zero',
        code: 'invalid_pomodoro_config',
      );
    }
    if (rest < Duration.zero) {
      throw const StudyRoomError(
        'Break duration cannot be negative',
        code: 'invalid_pomodoro_config',
      );
    }
  }
}

/// Immutable snapshot emitted by [PomodoroController].
class PomodoroState {
  const PomodoroState({
    required this.status,
    required this.remaining,
    this.previousStatus,
  });

  PomodoroState.initial(PomodoroConfig config)
    : this(status: PomodoroStatus.idle, remaining: config.focusDuration);

  final PomodoroStatus status;
  final Duration remaining;
  final PomodoroStatus? previousStatus;

  PomodoroState copyWith({
    PomodoroStatus? status,
    Duration? remaining,
    PomodoroStatus? previousStatus,
    bool clearPreviousStatus = false,
  }) {
    return PomodoroState(
      status: status ?? this.status,
      remaining: remaining ?? this.remaining,
      previousStatus: clearPreviousStatus
          ? null
          : previousStatus ?? this.previousStatus,
    );
  }
}

/// Local Pomodoro timer that records completed focus stages in a [StudyStore].
class PomodoroController {
  PomodoroController({
    required StudyStore store,
    PomodoroConfig? config,
    DateTime Function()? now,
  }) : _store = store,
       _config = config ?? PomodoroConfig(),
       _now = now ?? DateTime.now {
    state = PomodoroState.initial(_config);
  }

  final StudyStore _store;
  PomodoroConfig _config;
  final DateTime Function() _now;
  final _states = StreamController<PomodoroState>.broadcast();
  Timer? _ticker;
  Timer? _completionTimer;
  DateTime? _stageEndsAt;
  var _stageGeneration = 0;
  var _completing = false;
  var _disposed = false;

  late PomodoroState state;

  PomodoroConfig get config => _config;

  Stream<PomodoroState> get states async* {
    yield state;
    yield* _states.stream;
  }

  void start() {
    if (state.status != PomodoroStatus.idle &&
        state.status != PomodoroStatus.finished) {
      return;
    }
    _beginStage(PomodoroStatus.focusing, config.focusDuration);
  }

  void pause() {
    if (state.status != PomodoroStatus.focusing &&
        state.status != PomodoroStatus.breaking) {
      return;
    }
    final previousStatus = state.status;
    final remaining = _remainingNow();
    _cancelStage();
    _emit(
      state.copyWith(
        status: PomodoroStatus.paused,
        remaining: remaining > Duration.zero ? remaining : Duration.zero,
        previousStatus: previousStatus,
      ),
    );
  }

  void resume() {
    if (state.status != PomodoroStatus.paused) {
      return;
    }
    final stage = state.previousStatus ?? PomodoroStatus.focusing;
    if (state.remaining <= Duration.zero) {
      _skipStage(stage);
      return;
    }
    _beginStage(stage, state.remaining);
  }

  void skip() {
    final stage = switch (state.status) {
      PomodoroStatus.focusing || PomodoroStatus.breaking => state.status,
      PomodoroStatus.paused => state.previousStatus,
      _ => null,
    };
    if (stage != null) {
      _skipStage(stage);
    }
  }

  void end() {
    if (state.status == PomodoroStatus.idle ||
        state.status == PomodoroStatus.finished) {
      return;
    }
    _cancelStage();
    _emit(
      state.copyWith(
        status: PomodoroStatus.finished,
        remaining: Duration.zero,
        clearPreviousStatus: true,
      ),
    );
  }

  void setConfig(PomodoroConfig config) {
    if (state.status == PomodoroStatus.focusing ||
        state.status == PomodoroStatus.breaking ||
        state.status == PomodoroStatus.paused) {
      throw const StudyRoomError(
        'Cannot change pomodoro config during an active stage',
        code: 'pomodoro_active',
      );
    }
    _cancelStage();
    _config = config;
    _emit(PomodoroState.initial(config));
  }

  void _beginStage(PomodoroStatus status, Duration duration) {
    _cancelStage();
    final generation = _stageGeneration;
    _completing = false;
    _stageEndsAt = _now().add(duration);
    _emit(PomodoroState(status: status, remaining: duration));
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (generation != _stageGeneration || _disposed) {
        return;
      }
      final remaining = _remainingNow();
      _emit(state.copyWith(remaining: remaining));
      if (remaining <= Duration.zero) {
        unawaited(_completeStage(generation, status));
      }
    });
    _completionTimer = Timer(
      duration,
      () => unawaited(_completeStage(generation, status)),
    );
  }

  Future<void> _completeStage(int generation, PomodoroStatus stage) async {
    if (_disposed || generation != _stageGeneration || _completing) {
      return;
    }
    _completing = true;
    _ticker?.cancel();
    _completionTimer?.cancel();
    _stageEndsAt = null;
    _emit(state.copyWith(remaining: Duration.zero));

    if (stage == PomodoroStatus.focusing) {
      try {
        await _store.addFocusSession(_now(), config.focusDuration);
      } catch (error, stackTrace) {
        if (!_disposed && generation == _stageGeneration) {
          _emit(
            state.copyWith(
              status: PomodoroStatus.finished,
              remaining: Duration.zero,
              clearPreviousStatus: true,
            ),
          );
          if (!_states.isClosed) {
            _states.addError(error, stackTrace);
          }
        }
        return;
      }
      if (_disposed || generation != _stageGeneration) {
        return;
      }
      if (config.breakDuration > Duration.zero) {
        _beginStage(PomodoroStatus.breaking, config.breakDuration);
      } else {
        _resetToIdle();
      }
      return;
    }
    _resetToIdle();
  }

  void _skipStage(PomodoroStatus stage) {
    _cancelStage();
    if (stage == PomodoroStatus.focusing &&
        config.breakDuration > Duration.zero) {
      _beginStage(PomodoroStatus.breaking, config.breakDuration);
    } else {
      _resetToIdle();
    }
  }

  void _resetToIdle() {
    _cancelStage();
    _emit(PomodoroState.initial(config));
  }

  Duration _remainingNow() {
    final endsAt = _stageEndsAt;
    if (endsAt == null) {
      return state.remaining;
    }
    final remaining = endsAt.difference(_now());
    return remaining > Duration.zero ? remaining : Duration.zero;
  }

  void _cancelStage() {
    _stageGeneration += 1;
    _ticker?.cancel();
    _completionTimer?.cancel();
    _ticker = null;
    _completionTimer = null;
    _stageEndsAt = null;
    _completing = false;
  }

  void _emit(PomodoroState next) {
    if (_disposed) {
      return;
    }
    state = next;
    if (!_states.isClosed) {
      _states.add(next);
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _cancelStage();
    _disposed = true;
    _states.close();
  }
}

/// Goal text, optional Pomodoro target, and completion state for one day.
class TodayGoal {
  const TodayGoal({
    this.text = '',
    this.targetPomodoros,
    this.completed = false,
  });

  final String text;
  final int? targetPomodoros;
  final bool completed;

  TodayGoal copyWith({
    String? text,
    int? targetPomodoros,
    bool? completed,
    bool clearTargetPomodoros = false,
  }) {
    return TodayGoal(
      text: text ?? this.text,
      targetPomodoros: clearTargetPomodoros
          ? null
          : targetPomodoros ?? this.targetPomodoros,
      completed: completed ?? this.completed,
    );
  }

  Map<String, dynamic> toJson() => {
    'text': text,
    'targetPomodoros': targetPomodoros,
    'completed': completed,
  };

  factory TodayGoal.fromJson(Map<String, dynamic> json) {
    return TodayGoal(
      text: json['text'] as String? ?? '',
      targetPomodoros: json['targetPomodoros'] as int?,
      completed: json['completed'] as bool? ?? false,
    );
  }
}

/// Locally persisted task record scoped to one study date.
class StudyTaskRecord {
  const StudyTaskRecord({
    required this.id,
    required this.title,
    required this.completed,
  });

  final String id;
  final String title;
  final bool completed;

  StudyTaskRecord copyWith({String? id, String? title, bool? completed}) {
    return StudyTaskRecord(
      id: id ?? this.id,
      title: title ?? this.title,
      completed: completed ?? this.completed,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'completed': completed,
  };

  factory StudyTaskRecord.fromJson(Map<String, dynamic> json) {
    return StudyTaskRecord(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      completed: json['completed'] as bool? ?? false,
    );
  }
}

/// Persisted focus UI preferences owned by the host's [StudyStore].
class StudyFocusSettings {
  factory StudyFocusSettings({
    String? soundTrackId,
    double soundVolume = 0.5,
    String? backgroundId,
    double backgroundMaskOpacity = 0.25,
    String? desktopSection,
  }) {
    return StudyFocusSettings._(
      soundTrackId: soundTrackId,
      soundVolume: soundVolume.clamp(0.0, 1.0).toDouble(),
      backgroundId: backgroundId,
      backgroundMaskOpacity: backgroundMaskOpacity.clamp(0.0, 0.85).toDouble(),
      desktopSection: desktopSection,
    );
  }

  const StudyFocusSettings._({
    required this.soundTrackId,
    required this.soundVolume,
    required this.backgroundId,
    required this.backgroundMaskOpacity,
    required this.desktopSection,
  });

  final String? soundTrackId;
  final double soundVolume;
  final String? backgroundId;
  final double backgroundMaskOpacity;
  final String? desktopSection;

  StudyFocusSettings copyWith({
    String? soundTrackId,
    double? soundVolume,
    String? backgroundId,
    double? backgroundMaskOpacity,
    String? desktopSection,
    bool clearSoundTrackId = false,
    bool clearBackgroundId = false,
    bool clearDesktopSection = false,
  }) {
    return StudyFocusSettings(
      soundTrackId: clearSoundTrackId
          ? null
          : soundTrackId ?? this.soundTrackId,
      soundVolume: soundVolume ?? this.soundVolume,
      backgroundId: clearBackgroundId
          ? null
          : backgroundId ?? this.backgroundId,
      backgroundMaskOpacity:
          backgroundMaskOpacity ?? this.backgroundMaskOpacity,
      desktopSection: clearDesktopSection
          ? null
          : desktopSection ?? this.desktopSection,
    );
  }

  Map<String, dynamic> toJson() => {
    'soundTrackId': soundTrackId,
    'soundVolume': soundVolume,
    'backgroundId': backgroundId,
    'backgroundMaskOpacity': backgroundMaskOpacity,
    'desktopSection': desktopSection,
  };

  factory StudyFocusSettings.fromJson(Map<String, dynamic> json) {
    return StudyFocusSettings(
      soundTrackId: json['soundTrackId'] as String?,
      soundVolume: (json['soundVolume'] as num?)?.toDouble() ?? 0.5,
      backgroundId: json['backgroundId'] as String?,
      backgroundMaskOpacity:
          (json['backgroundMaskOpacity'] as num?)?.toDouble() ?? 0.25,
      desktopSection: json['desktopSection'] as String?,
    );
  }
}

/// Kind of local Store value changed by a [StudyStoreChange].
enum StudyStoreChangeKind { goal, dayRecord, tasks, settings }

/// Notification emitted after a successful Store mutation.
class StudyStoreChange {
  StudyStoreChange(this.kind, {DateTime? date})
    : date = date == null ? null : _dateOnly(date);

  final StudyStoreChangeKind kind;
  final DateTime? date;
}

/// Aggregated focus duration and Pomodoro count for one local date.
class StudyDayRecord {
  const StudyDayRecord({
    required this.date,
    this.focusDuration = Duration.zero,
    this.pomodoroCount = 0,
  });

  final DateTime date;
  final Duration focusDuration;
  final int pomodoroCount;

  bool get hasStudied => pomodoroCount > 0 || focusDuration > Duration.zero;

  StudyDayRecord copyWith({
    DateTime? date,
    Duration? focusDuration,
    int? pomodoroCount,
  }) {
    return StudyDayRecord(
      date: date ?? this.date,
      focusDuration: focusDuration ?? this.focusDuration,
      pomodoroCount: pomodoroCount ?? this.pomodoroCount,
    );
  }

  Map<String, dynamic> toJson() => {
    'date': _dateKey(date),
    'focusSeconds': focusDuration.inSeconds,
    'pomodoroCount': pomodoroCount,
  };

  factory StudyDayRecord.fromJson(Map<String, dynamic> json) {
    return StudyDayRecord(
      date: _parseDateKey(json['date'] as String),
      focusDuration: Duration(seconds: json['focusSeconds'] as int? ?? 0),
      pomodoroCount: json['pomodoroCount'] as int? ?? 0,
    );
  }
}

/// Today and seven-day statistics computed from a [StudyStore].
class StudyStats {
  const StudyStats({
    required this.todayFocusDuration,
    required this.todayPomodoroCount,
    required this.streakDays,
    required this.lastSevenDays,
  });

  final Duration todayFocusDuration;
  final int todayPomodoroCount;
  final int streakDays;
  final List<StudyDayRecord> lastSevenDays;
}

/// Calendar range used when generating a [StudyReport].
enum StudyReportRange { day, week, month }

/// Aggregated local study report over a day, week, or month.
class StudyReport {
  const StudyReport({
    required this.range,
    required this.startDate,
    required this.endDate,
    required this.days,
    required this.totalFocusDuration,
    required this.totalPomodoroCount,
    required this.streakDays,
    required this.taskCompletionRate,
    required this.summary,
  });

  final StudyReportRange range;
  final DateTime startDate;
  final DateTime endDate;
  final List<StudyDayRecord> days;
  final Duration totalFocusDuration;
  final int totalPomodoroCount;
  final int streakDays;
  final double? taskCompletionRate;
  final String summary;
}

/// Controls how a [StudyDataBackup] is applied to a backup-capable store.
enum StudyBackupImportMode {
  /// Replaces values present in the backup while preserving unrelated dates.
  merge,

  /// Removes all study data in the target store before applying the backup.
  replace,
}

/// A portable, versioned snapshot of one local study-data scope.
///
/// The backup deliberately excludes user and namespace identifiers. The host
/// chooses the destination identity by selecting the [StudyBackupStore] that
/// receives the import. The JSON representation is not encrypted; hosts are
/// responsible for protecting it at rest and in transit.
class StudyDataBackup {
  factory StudyDataBackup({
    int schemaVersion = currentSchemaVersion,
    required DateTime exportedAt,
    Map<String, TodayGoal> goalsByDate = const {},
    List<StudyDayRecord> dayRecords = const [],
    Map<String, List<StudyTaskRecord>> tasksByDate = const {},
    StudyFocusSettings? settings,
  }) {
    if (schemaVersion != currentSchemaVersion) {
      throw FormatException('Unsupported study backup schema: $schemaVersion');
    }
    final normalizedGoals = <String, TodayGoal>{};
    for (final entry in goalsByDate.entries) {
      _parseDateKey(entry.key);
      normalizedGoals[entry.key] = entry.value;
    }
    final normalizedRecords = <StudyDayRecord>[];
    final recordDates = <String>{};
    for (final record in dayRecords) {
      final normalized = record.copyWith(date: _dateOnly(record.date));
      final key = _dateKey(normalized.date);
      if (!recordDates.add(key)) {
        throw FormatException('Duplicate day record in backup: $key');
      }
      normalizedRecords.add(normalized);
    }
    final normalizedTasks = <String, List<StudyTaskRecord>>{};
    for (final entry in tasksByDate.entries) {
      _parseDateKey(entry.key);
      final ids = <String>{};
      for (final task in entry.value) {
        if (task.id.trim().isEmpty || !ids.add(task.id)) {
          throw FormatException(
            'Invalid or duplicate task id for ${entry.key}: ${task.id}',
          );
        }
      }
      normalizedTasks[entry.key] = List.unmodifiable(entry.value);
    }
    return StudyDataBackup._(
      schemaVersion: schemaVersion,
      exportedAt: exportedAt.toUtc(),
      goalsByDate: Map.unmodifiable(normalizedGoals),
      dayRecords: List.unmodifiable(normalizedRecords),
      tasksByDate: Map.unmodifiable(normalizedTasks),
      settings: settings ?? StudyFocusSettings(),
    );
  }

  const StudyDataBackup._({
    required this.schemaVersion,
    required this.exportedAt,
    required this.goalsByDate,
    required this.dayRecords,
    required this.tasksByDate,
    required this.settings,
  });

  /// The only backup schema understood by this release.
  static const currentSchemaVersion = 1;

  final int schemaVersion;
  final DateTime exportedAt;
  final Map<String, TodayGoal> goalsByDate;
  final List<StudyDayRecord> dayRecords;
  final Map<String, List<StudyTaskRecord>> tasksByDate;
  final StudyFocusSettings settings;

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'exportedAt': exportedAt.toUtc().toIso8601String(),
    'goalsByDate': {
      for (final entry in goalsByDate.entries) entry.key: entry.value.toJson(),
    },
    'dayRecords': dayRecords
        .map((record) => record.toJson())
        .toList(growable: false),
    'tasksByDate': {
      for (final entry in tasksByDate.entries)
        entry.key: entry.value
            .map((task) => task.toJson())
            .toList(growable: false),
    },
    'settings': settings.toJson(),
  };

  factory StudyDataBackup.fromJson(Map<String, dynamic> json) {
    final schemaVersion = json['schemaVersion'];
    final exportedAt = json['exportedAt'];
    final goals = json['goalsByDate'];
    final records = json['dayRecords'];
    final tasks = json['tasksByDate'];
    final settings = json['settings'];
    if (schemaVersion is! int ||
        exportedAt is! String ||
        goals is! Map ||
        records is! List ||
        tasks is! Map ||
        settings is! Map) {
      throw const FormatException('Invalid study backup document');
    }
    final parsedExportedAt = DateTime.tryParse(exportedAt);
    if (parsedExportedAt == null) {
      throw const FormatException('Invalid study backup export timestamp');
    }
    final parsedGoals = <String, TodayGoal>{};
    for (final entry in goals.entries) {
      if (entry.key is! String || entry.value is! Map) {
        throw const FormatException('Invalid study backup goal');
      }
      parsedGoals[entry.key as String] = TodayGoal.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
    }
    final parsedRecords = <StudyDayRecord>[];
    for (final value in records) {
      if (value is! Map) {
        throw const FormatException('Invalid study backup day record');
      }
      parsedRecords.add(
        StudyDayRecord.fromJson(Map<String, dynamic>.from(value)),
      );
    }
    final parsedTasks = <String, List<StudyTaskRecord>>{};
    for (final entry in tasks.entries) {
      if (entry.key is! String || entry.value is! List) {
        throw const FormatException('Invalid study backup task group');
      }
      final values = <StudyTaskRecord>[];
      for (final value in entry.value as List) {
        if (value is! Map) {
          throw const FormatException('Invalid study backup task');
        }
        values.add(StudyTaskRecord.fromJson(Map<String, dynamic>.from(value)));
      }
      parsedTasks[entry.key as String] = values;
    }
    return StudyDataBackup(
      schemaVersion: schemaVersion,
      exportedAt: parsedExportedAt,
      goalsByDate: parsedGoals,
      dayRecords: parsedRecords,
      tasksByDate: parsedTasks,
      settings: StudyFocusSettings.fromJson(
        Map<String, dynamic>.from(settings),
      ),
    );
  }
}

/// Host-owned persistence boundary for personal local study data.
///
/// The SDK never disposes a Store supplied by the host. Implementations should
/// keep [changes] alive for as long as consumers may read or mutate the Store.
abstract class StudyStore {
  Stream<StudyStoreChange> get changes;

  Future<TodayGoal> loadTodayGoal(DateTime date);

  Future<void> saveTodayGoal(DateTime date, TodayGoal goal);

  Future<StudyDayRecord> loadDayRecord(DateTime date);

  Future<List<StudyDayRecord>> loadDayRecords({
    required DateTime start,
    required DateTime end,
  });

  Future<void> saveDayRecord(StudyDayRecord record);

  Future<void> addFocusSession(
    DateTime date,
    Duration duration, {
    int pomodoros = 1,
  });

  Future<List<StudyTaskRecord>> loadTaskRecords(DateTime date);

  Future<void> saveTaskRecord(DateTime date, StudyTaskRecord task);

  Future<void> deleteTaskRecord(DateTime date, String taskId);

  Future<StudyFocusSettings> loadSettings();

  Future<void> saveSettings(StudyFocusSettings settings);
}

/// Optional persistence capability for exporting and restoring local data.
///
/// Existing custom [StudyStore] implementations do not need to implement this
/// interface. Callers should check `store is StudyBackupStore` before offering
/// backup controls.
abstract interface class StudyBackupStore implements StudyStore {
  Future<StudyDataBackup> exportBackup();

  Future<void> importBackup(
    StudyDataBackup backup, {
    StudyBackupImportMode mode = StudyBackupImportMode.merge,
  });
}

/// In-memory [StudyBackupStore] suitable for tests and ephemeral sessions.
class MemoryStudyStore implements StudyBackupStore {
  final _goals = <String, TodayGoal>{};
  final _records = <String, StudyDayRecord>{};
  final _tasks = <String, List<StudyTaskRecord>>{};
  final _changes = StreamController<StudyStoreChange>.broadcast(sync: true);
  Future<void> _mutationTail = Future<void>.value();
  var _settings = StudyFocusSettings();

  @override
  Stream<StudyStoreChange> get changes => _changes.stream;

  @override
  Future<TodayGoal> loadTodayGoal(DateTime date) async {
    return _goals[_dateKey(date)] ?? const TodayGoal();
  }

  @override
  Future<void> saveTodayGoal(DateTime date, TodayGoal goal) async {
    _goals[_dateKey(date)] = goal;
    _changes.add(StudyStoreChange(StudyStoreChangeKind.goal, date: date));
  }

  @override
  Future<StudyDayRecord> loadDayRecord(DateTime date) async {
    final day = _dateOnly(date);
    return _records[_dateKey(day)] ?? StudyDayRecord(date: day);
  }

  @override
  Future<List<StudyDayRecord>> loadDayRecords({
    required DateTime start,
    required DateTime end,
  }) async {
    final days = <StudyDayRecord>[];
    var cursor = _dateOnly(start);
    final last = _dateOnly(end);
    while (!cursor.isAfter(last)) {
      days.add(await loadDayRecord(cursor));
      cursor = cursor.add(const Duration(days: 1));
    }
    return days;
  }

  @override
  Future<void> saveDayRecord(StudyDayRecord record) async {
    final normalized = record.copyWith(date: _dateOnly(record.date));
    _records[_dateKey(normalized.date)] = normalized;
    _changes.add(
      StudyStoreChange(StudyStoreChangeKind.dayRecord, date: normalized.date),
    );
  }

  @override
  Future<void> addFocusSession(
    DateTime date,
    Duration duration, {
    int pomodoros = 1,
  }) => _serializeMutation(() async {
    final day = _dateOnly(date);
    final key = _dateKey(day);
    final current = _records[key] ?? StudyDayRecord(date: day);
    _records[key] = current.copyWith(
      focusDuration: current.focusDuration + duration,
      pomodoroCount: current.pomodoroCount + pomodoros,
    );
    _changes.add(StudyStoreChange(StudyStoreChangeKind.dayRecord, date: day));
  });

  @override
  Future<List<StudyTaskRecord>> loadTaskRecords(DateTime date) async {
    return List.unmodifiable(_tasks[_dateKey(date)] ?? const []);
  }

  @override
  Future<void> saveTaskRecord(DateTime date, StudyTaskRecord task) =>
      _serializeMutation(() async {
        final key = _dateKey(date);
        final tasks = List<StudyTaskRecord>.of(_tasks[key] ?? const []);
        final index = tasks.indexWhere((existing) => existing.id == task.id);
        if (index == -1) {
          tasks.add(task);
        } else {
          tasks[index] = task;
        }
        _tasks[key] = tasks;
        _changes.add(StudyStoreChange(StudyStoreChangeKind.tasks, date: date));
      });

  @override
  Future<void> deleteTaskRecord(DateTime date, String taskId) =>
      _serializeMutation(() async {
        final key = _dateKey(date);
        final tasks = List<StudyTaskRecord>.of(_tasks[key] ?? const []);
        tasks.removeWhere((task) => task.id == taskId);
        _tasks[key] = tasks;
        _changes.add(StudyStoreChange(StudyStoreChangeKind.tasks, date: date));
      });

  @override
  Future<StudyFocusSettings> loadSettings() async => _settings;

  @override
  Future<void> saveSettings(StudyFocusSettings settings) async {
    _settings = settings;
    _changes.add(StudyStoreChange(StudyStoreChangeKind.settings));
  }

  @override
  Future<StudyDataBackup> exportBackup() => _serializeMutation(() async {
    return StudyDataBackup(
      exportedAt: DateTime.now().toUtc(),
      goalsByDate: _goals,
      dayRecords: _records.values.toList(growable: false),
      tasksByDate: _tasks,
      settings: _settings,
    );
  });

  @override
  Future<void> importBackup(
    StudyDataBackup backup, {
    StudyBackupImportMode mode = StudyBackupImportMode.merge,
  }) => _serializeMutation(() async {
    if (mode == StudyBackupImportMode.replace) {
      _goals.clear();
      _records.clear();
      _tasks.clear();
    }
    _goals.addAll(backup.goalsByDate);
    for (final record in backup.dayRecords) {
      _records[_dateKey(record.date)] = record;
    }
    for (final entry in backup.tasksByDate.entries) {
      final tasks = List<StudyTaskRecord>.of(_tasks[entry.key] ?? const []);
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
      _tasks[entry.key] = tasks;
    }
    _settings = backup.settings;
    for (final date in backup.goalsByDate.keys) {
      _changes.add(
        StudyStoreChange(StudyStoreChangeKind.goal, date: _parseDateKey(date)),
      );
    }
    for (final record in backup.dayRecords) {
      _changes.add(
        StudyStoreChange(StudyStoreChangeKind.dayRecord, date: record.date),
      );
    }
    for (final date in backup.tasksByDate.keys) {
      _changes.add(
        StudyStoreChange(StudyStoreChangeKind.tasks, date: _parseDateKey(date)),
      );
    }
    _changes.add(StudyStoreChange(StudyStoreChangeKind.settings));
  });

  Future<T> _serializeMutation<T>(Future<T> Function() action) {
    final operation = _mutationTail.then((_) => action());
    _mutationTail = operation.then<void>((_) {}, onError: (_, _) {});
    return operation;
  }
}

/// Computes statistics and reports from a [StudyStore].
class StudyAnalytics {
  const StudyAnalytics(this.store);

  final StudyStore store;

  Future<StudyStats> statsFor(DateTime today) async {
    final day = _dateOnly(today);
    final todayRecord = await store.loadDayRecord(day);
    final lastSevenDays = await store.loadDayRecords(
      start: day.subtract(const Duration(days: 6)),
      end: day,
    );
    return StudyStats(
      todayFocusDuration: todayRecord.focusDuration,
      todayPomodoroCount: todayRecord.pomodoroCount,
      streakDays: await streakDaysEnding(day),
      lastSevenDays: lastSevenDays,
    );
  }

  Future<int> streakDaysEnding(DateTime day) async {
    var streak = 0;
    var cursor = _dateOnly(day);
    while (true) {
      final record = await store.loadDayRecord(cursor);
      if (!record.hasStudied) {
        return streak;
      }
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }
  }

  double? taskCompletionRate(List<StudyTaskRecord> tasks) {
    if (tasks.isEmpty) {
      return null;
    }
    final completed = tasks.where((task) => task.completed).length;
    return completed / tasks.length;
  }

  Future<StudyReport> report(StudyReportRange range, DateTime anchor) async {
    final anchorDay = _dateOnly(anchor);
    final start = switch (range) {
      StudyReportRange.day => anchorDay,
      StudyReportRange.week => anchorDay.subtract(
        Duration(days: anchorDay.weekday - 1),
      ),
      StudyReportRange.month => DateTime(anchorDay.year, anchorDay.month),
    };
    final end = switch (range) {
      StudyReportRange.day => anchorDay,
      StudyReportRange.week => start.add(const Duration(days: 6)),
      StudyReportRange.month => DateTime(
        anchorDay.year,
        anchorDay.month + 1,
        0,
      ),
    };
    final days = await store.loadDayRecords(start: start, end: end);
    final tasks = <StudyTaskRecord>[];
    var totalFocus = Duration.zero;
    var totalPomodoros = 0;
    for (final day in days) {
      totalFocus += day.focusDuration;
      totalPomodoros += day.pomodoroCount;
      tasks.addAll(await store.loadTaskRecords(day.date));
    }
    final streak = await streakDaysEnding(end);
    return StudyReport(
      range: range,
      startDate: start,
      endDate: end,
      days: days,
      totalFocusDuration: totalFocus,
      totalPomodoroCount: totalPomodoros,
      streakDays: streak,
      taskCompletionRate: taskCompletionRate(tasks),
      summary: _summary(totalFocus, totalPomodoros, streak),
    );
  }

  String _summary(Duration focus, int pomodoros, int streak) {
    if (pomodoros == 0 && focus == Duration.zero) {
      return 'No focus sessions yet.';
    }
    return '${focus.inMinutes} focused minutes, $pomodoros pomodoros, $streak day streak.';
  }
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

String _dateKey(DateTime date) {
  final day = _dateOnly(date);
  final month = day.month.toString().padLeft(2, '0');
  final datePart = day.day.toString().padLeft(2, '0');
  return '${day.year}-$month-$datePart';
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
