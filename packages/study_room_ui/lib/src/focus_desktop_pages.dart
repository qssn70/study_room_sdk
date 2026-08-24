part of 'focus_desktop.dart';

class _DesktopAnalyticsPage extends StatelessWidget {
  const _DesktopAnalyticsPage({
    required this.store,
    required this.date,
    super.key,
  });

  final StudyStore store;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final localizations = studyRoomLocalizationsOf(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            localizations.analyticsSection,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 20),
          _DesktopPanelCard(
            child: StudyAnalyticsView(store: store, date: date),
          ),
          const SizedBox(height: 20),
          for (final range in StudyReportRange.values) ...[
            _DesktopPanelCard(
              child: StudyReportView(store: store, range: range, date: date),
            ),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class _DesktopHistoryPage extends StatefulWidget {
  const _DesktopHistoryPage({required this.model, required this.actions});

  final StudyFocusLayoutModel model;
  final StudyFocusActions actions;

  @override
  State<_DesktopHistoryPage> createState() => _DesktopHistoryPageState();
}

class _DesktopHistoryPageState extends State<_DesktopHistoryPage> {
  late DateTime _selectedDate = studyDateOnly(widget.model.data.date);
  late Future<(List<StudyDayRecord>, List<StudyTaskRecord>)> _future = _load();
  StreamSubscription<StudyStoreChange>? _subscription;

  StudyStore get _store => widget.model.data.store;
  DateTime get _date => widget.model.data.date;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant _DesktopHistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model.data.store != _store) {
      unawaited(_subscription?.cancel());
      _subscribe();
    }
    if (oldWidget.model.data.date != _date) {
      _selectedDate = studyDateOnly(_date);
    }
    if (oldWidget.model.data.store != _store ||
        oldWidget.model.data.date != _date) {
      _future = _load();
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _subscribe() {
    _subscription = _store.changes.listen((change) {
      if (!mounted ||
          (change.kind != StudyStoreChangeKind.dayRecord &&
              change.kind != StudyStoreChangeKind.tasks)) {
        return;
      }
      setState(() {
        _future = _load();
      });
    });
  }

  Future<(List<StudyDayRecord>, List<StudyTaskRecord>)> _load() async {
    final end = studyDateOnly(_date);
    final records = await _store.loadDayRecords(
      start: end.subtract(const Duration(days: 29)),
      end: end,
    );
    final tasks = await _store.loadTaskRecords(_selectedDate);
    return (records.reversed.toList(growable: false), tasks);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = studyRoomLocalizationsOf(context);
    return FutureBuilder<(List<StudyDayRecord>, List<StudyTaskRecord>)>(
      future: _future,
      builder: (context, snapshot) {
        final records = snapshot.data?.$1;
        final tasks = snapshot.data?.$2;
        if (records == null || tasks == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return Padding(
          padding: const EdgeInsets.all(28),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 330,
                child: _DesktopPanelCard(
                  child: ListView.builder(
                    itemCount: records.length,
                    itemBuilder: (context, index) {
                      final record = records[index];
                      final selected =
                          studyDateKey(record.date) ==
                          studyDateKey(_selectedDate);
                      return ListTile(
                        selected: selected,
                        title: Text(
                          MaterialLocalizations.of(
                            context,
                          ).formatMediumDate(record.date),
                        ),
                        subtitle: Text(
                          localizations.focusHistorySummary(
                            record.focusDuration.inMinutes,
                            record.pomodoroCount,
                          ),
                        ),
                        onTap: () {
                          setState(() {
                            _selectedDate = record.date;
                            _future = _load();
                          });
                        },
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: _DesktopPanelCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              localizations.tasksForDate(
                                MaterialLocalizations.of(
                                  context,
                                ).formatMediumDate(_selectedDate),
                              ),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: () => _editStudyTask(
                              context,
                              date: _selectedDate,
                              onSave: widget.actions.saveTask,
                              editor: widget.actions.taskEditor,
                            ),
                            icon: const Icon(Icons.add),
                            label: Text(localizations.newTask),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: tasks.isEmpty
                            ? Center(child: Text(localizations.noTasks))
                            : ListView(
                                children: tasks
                                    .map(
                                      (task) => ListTile(
                                        key: Key('desktop_task_${task.id}'),
                                        leading: Checkbox(
                                          value: task.completed,
                                          onChanged: (value) => _saveTask(
                                            task.copyWith(
                                              completed: value ?? false,
                                            ),
                                          ),
                                        ),
                                        title: Text(
                                          task.title,
                                          style: TextStyle(
                                            decoration: task.completed
                                                ? TextDecoration.lineThrough
                                                : null,
                                          ),
                                        ),
                                        trailing: Wrap(
                                          children: [
                                            IconButton(
                                              tooltip: localizations.edit,
                                              onPressed: () => _editStudyTask(
                                                context,
                                                date: _selectedDate,
                                                onSave: widget.actions.saveTask,
                                                existing: task,
                                                editor:
                                                    widget.actions.taskEditor,
                                              ),
                                              icon: const Icon(Icons.edit),
                                            ),
                                            IconButton(
                                              tooltip: localizations.delete,
                                              onPressed: () =>
                                                  _deleteTask(task),
                                              icon: const Icon(Icons.delete),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                    .toList(growable: false),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteTask(StudyTaskRecord task) async {
    final localizations = studyRoomLocalizationsOf(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localizations.deleteTaskTitle),
        content: Text(localizations.deleteTaskConfirmation(task.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(localizations.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(localizations.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.actions.deleteTask(_selectedDate, task.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(localizations.taskDeleteFailed)),
        );
      }
    }
  }

  Future<void> _saveTask(StudyTaskRecord task) async {
    final localizations = studyRoomLocalizationsOf(context);
    try {
      await widget.actions.saveTask(_selectedDate, task);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text(localizations.taskSaveFailed)));
      }
    }
  }
}

class _DesktopSettingsPage extends StatefulWidget {
  const _DesktopSettingsPage({required this.model, required this.actions});

  final StudyFocusLayoutModel model;
  final StudyFocusActions actions;

  @override
  State<_DesktopSettingsPage> createState() => _DesktopSettingsPageState();
}

class _DesktopSettingsPageState extends State<_DesktopSettingsPage> {
  late double _maskOpacity = widget.model.shell.activeBackgroundMaskOpacity;

  @override
  void didUpdateWidget(covariant _DesktopSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model.shell.activeBackgroundMaskOpacity !=
        widget.model.shell.activeBackgroundMaskOpacity) {
      _maskOpacity = widget.model.shell.activeBackgroundMaskOpacity;
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = studyRoomLocalizationsOf(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            localizations.settingsSection,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 20),
          _DesktopPanelCard(
            child: _DesktopSoundControls(
              model: widget.model,
              actions: widget.actions,
            ),
          ),
          const SizedBox(height: 20),
          _DesktopPanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  localizations.background,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: widget.model.shell.backgrounds
                      .map(
                        (option) => ChoiceChip(
                          label: Text(
                            localizedBackgroundOptionLabel(
                              option,
                              localizations,
                            ),
                          ),
                          selected:
                              option.id ==
                              widget.model.shell.activeBackgroundId,
                          onSelected: (_) => unawaited(
                            widget.actions.selectBackground(
                              option.id,
                              _maskOpacity,
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
                const SizedBox(height: 18),
                Text(
                  localizations.backgroundMask((100 * _maskOpacity).round()),
                ),
                Slider(
                  key: const Key('desktop_background_mask'),
                  value: _maskOpacity,
                  max: 0.85,
                  onChanged: (value) => setState(() => _maskOpacity = value),
                  onChangeEnd: (value) => unawaited(
                    widget.actions.selectBackground(
                      widget.model.shell.activeBackgroundId,
                      value,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopSoundControls extends StatelessWidget {
  const _DesktopSoundControls({required this.model, required this.actions});

  final StudyFocusLayoutModel model;
  final StudyFocusActions actions;

  @override
  Widget build(BuildContext context) {
    final localizations = studyRoomLocalizationsOf(context);
    final selected = _selectedTrack(model.sound);
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: model.sound.tracks
                .map(
                  (track) => ChoiceChip(
                    label: Text(localizedSoundTrackLabel(track, localizations)),
                    selected: model.sound.selectedTrackId == track.id,
                    onSelected: (_) => unawaited(actions.toggleSound(track)),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton.filled(
                tooltip: model.sound.playing
                    ? localizations.pause
                    : localizations.play,
                icon: Icon(
                  model.sound.playing ? Icons.pause : Icons.play_arrow,
                ),
                onPressed: selected == null
                    ? null
                    : () => unawaited(
                        model.sound.playing
                            ? actions.pauseSound()
                            : actions.toggleSound(selected),
                      ),
              ),
              Expanded(
                child: Slider(
                  value: model.sound.volume,
                  onChanged: (value) =>
                      unawaited(actions.setSoundVolume(value)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

StudySoundTrack? _selectedTrack(StudyFocusSoundModel sound) {
  for (final track in sound.tracks) {
    if (track.id == sound.selectedTrackId) return track;
  }
  return null;
}

var _taskSequence = 0;

Future<void> _editStudyTask(
  BuildContext context, {
  required DateTime date,
  required Future<void> Function(DateTime date, StudyTaskRecord task) onSave,
  StudyTaskRecord? existing,
  StudyTaskEditor? editor,
}) async {
  final localizations = studyRoomLocalizationsOf(context);
  final task = editor == null
      ? await showDialog<StudyTaskRecord>(
          context: context,
          builder: (context) => _StudyTaskDialog(existing: existing),
        )
      : await editor(context, date, existing);
  if (task == null) return;
  try {
    await onSave(date, task);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(localizations.taskSaveFailed)));
    }
  }
}

class _StudyTaskDialog extends StatefulWidget {
  const _StudyTaskDialog({this.existing});

  final StudyTaskRecord? existing;

  @override
  State<_StudyTaskDialog> createState() => _StudyTaskDialogState();
}

class _StudyTaskDialogState extends State<_StudyTaskDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.existing?.title ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = studyRoomLocalizationsOf(context);
    return AlertDialog(
      title: Text(
        widget.existing == null
            ? localizations.newTask
            : localizations.editTask,
      ),
      content: TextField(
        key: const Key('study_task_title'),
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: localizations.taskName,
          errorText: _error,
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(localizations.cancel),
        ),
        FilledButton(onPressed: _save, child: Text(localizations.save)),
      ],
    );
  }

  void _save() {
    final title = _controller.text.trim();
    if (title.isEmpty) {
      setState(
        () => _error = studyRoomLocalizationsOf(context).taskNameRequired,
      );
      return;
    }
    Navigator.pop(
      context,
      widget.existing?.copyWith(title: title) ??
          StudyTaskRecord(
            id: 'task_${DateTime.now().toUtc().microsecondsSinceEpoch}_${_taskSequence++}',
            title: title,
            completed: false,
          ),
    );
  }
}
