import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:study_room_sdk/study_room_sdk.dart';

import 'analytics.dart';
import 'audio.dart';
import 'focus_api.dart';
import 'focus_clock.dart';
import 'focus_contracts.dart';
import 'focus_formatters.dart';
import 'focus_primitives.dart';
import 'focus_store_builder.dart';
import 'focus_timer_components.dart';
import 'localizations.dart';
import 'rooms.dart';

/// Package-internal desktop shell for the focus experience.
class StudyFocusDesktopShell extends StatelessWidget {
  const StudyFocusDesktopShell({
    required this.model,
    required this.actions,
    required this.sizing,
    super.key,
  });

  final StudyFocusLayoutModel model;
  final StudyFocusActions actions;
  final StudyFocusSizing sizing;

  @override
  Widget build(BuildContext context) {
    final section = model.shell.desktopSection;
    final defaultPage = switch (section) {
      StudyFocusDesktopSection.focus => _focusPage(),
      StudyFocusDesktopSection.analytics => _DesktopAnalyticsPage(
        key: ValueKey('desktop-analytics-${model.data.dataRevision}'),
        store: model.data.store,
        date: model.data.date,
      ),
      StudyFocusDesktopSection.history => _DesktopHistoryPage(
        model: model,
        actions: actions,
      ),
      StudyFocusDesktopSection.settings => _DesktopSettingsPage(
        model: model,
        actions: actions,
      ),
    };
    final page =
        actions.desktopPageBuilder?.call(context, section, defaultPage) ??
        defaultPage;
    return Column(
      key: const Key('study_focus_desktop_shell'),
      children: [
        _DesktopTopNav(
          section: section,
          onSectionChanged: actions.selectDesktopSection,
          onNewTask: () => _editStudyTask(
            context,
            date: model.data.date,
            onSave: actions.saveTask,
            editor: actions.taskEditor,
          ),
        ),
        Expanded(child: page),
      ],
    );
  }

  Widget _focusPage() {
    final visibleMembers = model.data.members.where(
      (member) =>
          member.id != model.data.currentUserId &&
          member.status != PresenceStatus.offline,
    );
    final members = model.data.showCompanions
        ? SilentCompanionList(
            currentUserId: model.data.currentUserId,
            members: model.data.members,
            theme: SilentCompanionTheme(
              avatarSize: 32,
              focusingColor: studyFocusAccent,
              onlineColor: studyFocusAccent,
              idleColor: Colors.white.withValues(alpha: 0.42),
              awayColor: studyFocusRest,
            ),
          )
        : const SizedBox.shrink();
    return Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(56, 30, 56, 34),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: StudyFocusCoreCluster(
                      model: model,
                      actions: actions,
                      sizing: sizing,
                      desktop: true,
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: StudyFocusGoalCard(
                    model: model,
                    actions: actions,
                    desktop: true,
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          key: const Key('study_focus_desktop_sidebar'),
          width: 380,
          child: _DesktopSidePanel(
            members: members,
            onlineCount: visibleMembers.length,
            stats: _PrototypeStatsOverview(
              store: model.data.store,
              date: model.data.date,
            ),
            model: model,
            actions: actions,
          ),
        ),
      ],
    );
  }
}

class _DesktopTopNav extends StatefulWidget {
  const _DesktopTopNav({
    required this.section,
    required this.onSectionChanged,
    required this.onNewTask,
  });

  final StudyFocusDesktopSection section;
  final ValueChanged<StudyFocusDesktopSection> onSectionChanged;
  final VoidCallback onNewTask;

  @override
  State<_DesktopTopNav> createState() => _DesktopTopNavState();
}

class _DesktopTopNavState extends State<_DesktopTopNav> {
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = studyRoomLocalizationsOf(context);
    return SizedBox(
      height: 60,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.18),
          border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: studyFocusAccent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                localizations.focusAppTitle,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 36),
              _DesktopNavItem(
                localizations.focusSection,
                selected: widget.section == StudyFocusDesktopSection.focus,
                onPressed: () =>
                    widget.onSectionChanged(StudyFocusDesktopSection.focus),
              ),
              _DesktopNavItem(
                localizations.analyticsSection,
                selected: widget.section == StudyFocusDesktopSection.analytics,
                onPressed: () =>
                    widget.onSectionChanged(StudyFocusDesktopSection.analytics),
              ),
              _DesktopNavItem(
                localizations.historySection,
                selected: widget.section == StudyFocusDesktopSection.history,
                onPressed: () =>
                    widget.onSectionChanged(StudyFocusDesktopSection.history),
              ),
              _DesktopNavItem(
                localizations.settingsSection,
                selected: widget.section == StudyFocusDesktopSection.settings,
                onPressed: () =>
                    widget.onSectionChanged(StudyFocusDesktopSection.settings),
              ),
              const Spacer(),
              Text(
                TimeOfDay.fromDateTime(
                  StudyFocusClockScope.nowOf(context),
                ).format(context),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.66),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 18),
              FilledButton.icon(
                onPressed: widget.onNewTask,
                icon: const Icon(Icons.add, size: 18),
                label: Text(localizations.newTask),
                style: FilledButton.styleFrom(
                  backgroundColor: studyFocusAccent,
                  foregroundColor: const Color(0xFF10251A),
                  minimumSize: const Size(112, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopNavItem extends StatelessWidget {
  const _DesktopNavItem(
    this.label, {
    required this.onPressed,
    this.selected = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: TextButton(
        onPressed: onPressed,
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Colors.white.withValues(alpha: selected ? 0.96 : 0.58),
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

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

class _DesktopSidePanel extends StatelessWidget {
  const _DesktopSidePanel({
    required this.members,
    required this.onlineCount,
    required this.stats,
    required this.model,
    required this.actions,
  });

  final Widget members;
  final int onlineCount;
  final Widget stats;
  final StudyFocusLayoutModel model;
  final StudyFocusActions actions;

  @override
  Widget build(BuildContext context) {
    final localizations = studyRoomLocalizationsOf(context);
    return StudyFocusGlassPanel(
      borderRadius: BorderRadius.zero,
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DesktopSectionHeader(
              title: localizations.silentCompanions,
              trailing: localizations.onlineMemberCount(onlineCount),
            ),
            const SizedBox(height: 14),
            _DesktopPanelCard(child: members),
            const SizedBox(height: 24),
            _DesktopSectionHeader(title: localizations.whiteNoise),
            const SizedBox(height: 12),
            _DesktopSoundGrid(model: model, actions: actions),
            const SizedBox(height: 24),
            _DesktopSectionHeader(title: localizations.todayPrivateData),
            const SizedBox(height: 12),
            _DesktopPanelCard(child: stats),
          ],
        ),
      ),
    );
  }
}

class _DesktopSectionHeader extends StatelessWidget {
  const _DesktopSectionHeader({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.52),
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}

class _DesktopPanelCard extends StatelessWidget {
  const _DesktopPanelCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(padding: const EdgeInsets.all(12), child: child),
    );
  }
}

class _DesktopSoundGrid extends StatelessWidget {
  const _DesktopSoundGrid({required this.model, required this.actions});

  final StudyFocusLayoutModel model;
  final StudyFocusActions actions;

  @override
  Widget build(BuildContext context) {
    final localizations = studyRoomLocalizationsOf(context);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: model.sound.tracks
          .map(
            (track) => SizedBox(
              width: 96,
              child: _DesktopSoundTile(
                icon: _soundIcon(track.id),
                label: track.label,
                displayLabel: localizedSoundTrackLabel(track, localizations),
                selected: model.sound.selectedTrackId == track.id,
                playing:
                    model.sound.playing &&
                    model.sound.selectedTrackId == track.id,
                onPressed: () => unawaited(actions.toggleSound(track)),
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  IconData _soundIcon(String id) => switch (id) {
    'rain' => Icons.water_drop,
    'cafe' => Icons.local_cafe,
    'library' => Icons.local_library,
    'keyboard' => Icons.keyboard,
    _ => Icons.graphic_eq,
  };
}

class _DesktopSoundTile extends StatelessWidget {
  const _DesktopSoundTile({
    required this.icon,
    required this.label,
    required this.displayLabel,
    required this.selected,
    required this.playing,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String displayLabel;
  final bool selected;
  final bool playing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        key: Key('desktop_sound_$label'),
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: selected ? 0.16 : 0.06),
            border: Border.all(
              color: selected
                  ? studyFocusAccent
                  : Colors.white.withValues(alpha: 0.10),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              children: [
                Icon(
                  playing ? Icons.pause : icon,
                  size: 22,
                  color: studyFocusAccent,
                ),
                const SizedBox(height: 8),
                Text(
                  displayLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrototypeStatsOverview extends StatelessWidget {
  const _PrototypeStatsOverview({required this.store, required this.date});

  final StudyStore store;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final localizations = studyRoomLocalizationsOf(context);
    return StudyStoreListenableBuilder<StudyStats>(
      store: store,
      dependency: studyDateKey(date),
      changeKinds: const {StudyStoreChangeKind.dayRecord},
      load: () => StudyAnalytics(store).statsFor(date),
      builder: (context, snapshot) {
        final stats = snapshot.data;
        if (stats == null) {
          return const LinearProgressIndicator();
        }
        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: _PrototypeMetric(
                    value: _formatHours(
                      stats.todayFocusDuration,
                      localizations,
                    ),
                    label: localizations.todayFocus,
                  ),
                ),
                Expanded(
                  child: _PrototypeMetric(
                    value: localizations.pomodoroCountValue(
                      stats.todayPomodoroCount,
                    ),
                    label: localizations.todayPomodoros,
                  ),
                ),
                Expanded(
                  child: _PrototypeMetric(
                    value: localizations.dayCountValue(stats.streakDays),
                    label: localizations.streak,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _PrototypeBars(days: stats.lastSevenDays),
          ],
        );
      },
    );
  }

  String _formatHours(Duration duration, StudyRoomLocalizations localizations) {
    final hours = duration.inMinutes / 60;
    final value = NumberFormat.decimalPattern(
      localizations.localeName,
    ).format(hours);
    return localizations.hoursValue(value);
  }
}

class _PrototypeMetric extends StatelessWidget {
  const _PrototypeMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.54),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _PrototypeBars extends StatelessWidget {
  const _PrototypeBars({required this.days});

  final List<StudyDayRecord> days;

  @override
  Widget build(BuildContext context) {
    final visibleDays = days.isEmpty
        ? List<StudyDayRecord>.generate(
            7,
            (index) => StudyDayRecord(date: DateTime(1970, 1, index + 1)),
          )
        : days;
    return SizedBox(
      height: 42,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var index = 0; index < visibleDays.length; index++) ...[
            Expanded(
              child: FractionallySizedBox(
                heightFactor: (visibleDays[index].focusDuration.inMinutes / 120)
                    .clamp(0.16, 1.0),
                alignment: Alignment.bottomCenter,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: index == visibleDays.length - 1
                        ? studyFocusAccent
                        : const Color(0xFF546E7A).withValues(alpha: 0.62),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
            if (index != visibleDays.length - 1) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}
