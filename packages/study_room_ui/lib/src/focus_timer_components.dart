import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:study_room_sdk/study_room_sdk.dart';

import 'focus_contracts.dart';
import 'focus_formatters.dart';
import 'focus_primitives.dart';
import 'localizations.dart';

/// Package-internal focus timer cluster shared by responsive shell libraries.
class StudyFocusCoreCluster extends StatelessWidget {
  const StudyFocusCoreCluster({
    required this.model,
    required this.actions,
    required this.sizing,
    this.goal,
    this.desktop = false,
    super.key,
  });

  final StudyFocusLayoutModel model;
  final StudyFocusActions actions;
  final StudyFocusSizing sizing;
  final Widget? goal;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final gap = desktop ? 34.0 : sizing.clusterGap;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: desktop ? 620 : sizing.coreMaxWidth,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: _PresetBar(model: model, actions: actions, verbose: desktop),
          ),
          SizedBox(height: gap),
          Center(
            child: _VisualPomodoroTimer(
              key: const Key('study_focus_timer'),
              model: model,
              size: sizing.timerSize,
            ),
          ),
          SizedBox(height: gap),
          if (desktop)
            _DesktopTimerControls(model: model, actions: actions)
          else
            _VisualTimerControls(
              model: model,
              actions: actions,
              buttonSize: sizing.controlButtonSize,
              gap: sizing.controlGap,
            ),
          if (goal != null) ...[SizedBox(height: sizing.goalGap), goal!],
        ],
      ),
    );
  }
}

class _PresetBar extends StatelessWidget {
  const _PresetBar({
    required this.model,
    required this.actions,
    this.verbose = false,
  });

  final StudyFocusLayoutModel model;
  final StudyFocusActions actions;
  final bool verbose;

  @override
  Widget build(BuildContext context) {
    final localizations = studyRoomLocalizationsOf(context);
    final status = model.data.timerState.status;
    final enabled =
        status == PomodoroStatus.idle || status == PomodoroStatus.finished;
    final preset = model.data.timerConfig.preset;
    return StudyFocusGlassPanel(
      borderRadius: BorderRadius.circular(999),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _PresetChip(
            label: verbose
                ? localizations.pomodoroPresetMinutes(25, 5)
                : '25/5',
            selected: preset == PomodoroPreset.twentyFiveFive,
            onPressed: enabled
                ? () => actions.setTimerConfig(PomodoroConfig())
                : null,
          ),
          _PresetChip(
            label: verbose
                ? localizations.pomodoroPresetMinutes(50, 10)
                : '50/10',
            selected: preset == PomodoroPreset.fiftyTen,
            onPressed: enabled
                ? () => actions.setTimerConfig(PomodoroConfig.fiftyTen())
                : null,
          ),
          _PresetChip(
            label: verbose
                ? localizations.customDuration
                : localizations.custom,
            selected: preset == PomodoroPreset.custom,
            onPressed: enabled
                ? () => _showCustomPomodoroDialog(
                    context,
                    initialConfig: model.data.timerConfig,
                    onApply: actions.setTimerConfig,
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Opacity(
        opacity: onPressed == null ? 0.5 : 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onPressed,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selected
                  ? Colors.white.withValues(alpha: 0.20)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Colors.white.withValues(alpha: selected ? 1 : 0.64),
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _showCustomPomodoroDialog(
  BuildContext context, {
  required PomodoroConfig initialConfig,
  required ValueChanged<PomodoroConfig> onApply,
}) async {
  final config = await showDialog<PomodoroConfig>(
    context: context,
    builder: (context) => _CustomPomodoroDialog(initialConfig: initialConfig),
  );
  if (config != null) {
    onApply(config);
  }
}

class _CustomPomodoroDialog extends StatefulWidget {
  const _CustomPomodoroDialog({required this.initialConfig});

  final PomodoroConfig initialConfig;

  @override
  State<_CustomPomodoroDialog> createState() => _CustomPomodoroDialogState();
}

class _CustomPomodoroDialogState extends State<_CustomPomodoroDialog> {
  late final _focusController = TextEditingController(
    text: widget.initialConfig.focusDuration.inMinutes.toString(),
  );
  late final _breakController = TextEditingController(
    text: widget.initialConfig.breakDuration.inMinutes.toString(),
  );
  String? _validationError;

  @override
  void dispose() {
    _focusController.dispose();
    _breakController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = studyRoomLocalizationsOf(context);
    return AlertDialog(
      title: Text(localizations.customDuration),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('pomodoro_custom_focus'),
            controller: _focusController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: localizations.focusMinutes),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('pomodoro_custom_break'),
            controller: _breakController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: localizations.breakMinutes),
          ),
          if (_validationError != null) ...[
            const SizedBox(height: 10),
            Text(
              _validationError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localizations.cancel),
        ),
        FilledButton(onPressed: _apply, child: Text(localizations.apply)),
      ],
    );
  }

  void _apply() {
    final focus = int.tryParse(_focusController.text.trim());
    final rest = int.tryParse(_breakController.text.trim());
    if (focus == null || focus <= 0 || rest == null || rest < 0) {
      setState(() {
        _validationError = studyRoomLocalizationsOf(
          context,
        ).pomodoroDurationInvalid;
      });
      return;
    }
    Navigator.of(context).pop(
      PomodoroConfig.custom(
        focusDuration: Duration(minutes: focus),
        breakDuration: Duration(minutes: rest),
      ),
    );
  }
}

class _VisualPomodoroTimer extends StatelessWidget {
  const _VisualPomodoroTimer({
    required this.model,
    required this.size,
    super.key,
  });

  final StudyFocusLayoutModel model;
  final double size;

  @override
  Widget build(BuildContext context) {
    final localizations = studyRoomLocalizationsOf(context);
    final state = model.data.timerState;
    final total = state.status == PomodoroStatus.breaking
        ? model.data.timerConfig.breakDuration
        : model.data.timerConfig.focusDuration;
    final progress = total == Duration.zero
        ? 0.0
        : 1 - (state.remaining.inMilliseconds / total.inMilliseconds);
    final color = state.status == PomodoroStatus.breaking
        ? studyFocusRest
        : studyFocusAccent;
    final innerSize = size >= 200 ? size - 24 : size - 20;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.square(
            dimension: size,
            child: CircularProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              strokeWidth: size >= 200 ? 12 : 10,
              backgroundColor: Colors.white.withValues(alpha: 0.16),
              color: color,
              strokeCap: StrokeCap.round,
            ),
          ),
          StudyFocusGlassPanel(
            borderRadius: BorderRadius.circular(size / 2),
            padding: EdgeInsets.zero,
            child: SizedBox.square(
              dimension: innerSize,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _formatDuration(state.remaining),
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontSize: size >= 200 ? 48 : 36,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                      shadows: const [
                        Shadow(
                          color: Color(0x66000000),
                          offset: Offset(0, 2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    model.data.timerError == null
                        ? pomodoroStatusLabel(state.status, localizations)
                        : localizations.saveFailed,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white.withValues(alpha: 0.74),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VisualTimerControls extends StatelessWidget {
  const _VisualTimerControls({
    required this.model,
    required this.actions,
    required this.buttonSize,
    required this.gap,
  });

  final StudyFocusLayoutModel model;
  final StudyFocusActions actions;
  final double buttonSize;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final localizations = studyRoomLocalizationsOf(context);
    final status = model.data.timerState.status;
    final running =
        status == PomodoroStatus.focusing || status == PomodoroStatus.breaking;
    final paused = status == PomodoroStatus.paused;
    final active = running || paused;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ControlTextButton(
          label: localizations.finish,
          onPressed: actions.endTimer,
        ),
        SizedBox(width: gap),
        StudyFocusGlassPanel(
          borderRadius: BorderRadius.circular(999),
          padding: EdgeInsets.zero,
          child: SizedBox.square(
            dimension: buttonSize,
            child: IconButton(
              tooltip: running
                  ? localizations.pause
                  : paused
                  ? localizations.resume
                  : localizations.start,
              icon: Icon(running ? Icons.pause : Icons.play_arrow),
              onPressed: running
                  ? actions.pauseTimer
                  : paused
                  ? actions.resumeTimer
                  : actions.startTimer,
            ),
          ),
        ),
        SizedBox(width: gap),
        _ControlTextButton(
          label: localizations.skip,
          onPressed: active ? actions.skipTimer : null,
        ),
      ],
    );
  }
}

class _DesktopTimerControls extends StatelessWidget {
  const _DesktopTimerControls({required this.model, required this.actions});

  final StudyFocusLayoutModel model;
  final StudyFocusActions actions;

  @override
  Widget build(BuildContext context) {
    final localizations = studyRoomLocalizationsOf(context);
    final status = model.data.timerState.status;
    final running =
        status == PomodoroStatus.focusing || status == PomodoroStatus.breaking;
    final paused = status == PomodoroStatus.paused;
    final active = running || paused;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ControlTextButton(
          label: localizations.endCurrentRound,
          onPressed: actions.endTimer,
        ),
        const SizedBox(width: 28),
        StudyFocusGlassPanel(
          borderRadius: BorderRadius.circular(999),
          padding: EdgeInsets.zero,
          child: SizedBox.square(
            dimension: 68,
            child: IconButton(
              tooltip: running
                  ? localizations.pause
                  : paused
                  ? localizations.resume
                  : localizations.start,
              icon: Icon(running ? Icons.pause : Icons.play_arrow, size: 30),
              onPressed: running
                  ? actions.pauseTimer
                  : paused
                  ? actions.resumeTimer
                  : actions.startTimer,
            ),
          ),
        ),
        const SizedBox(width: 28),
        _ControlTextButton(
          label: localizations.skipToBreak,
          onPressed: active ? actions.skipTimer : null,
        ),
      ],
    );
  }
}

class _ControlTextButton extends StatelessWidget {
  const _ControlTextButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white.withValues(alpha: 0.72),
        textStyle: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}

/// Package-internal goal card shared by portrait, landscape, and desktop shells.
class StudyFocusGoalCard extends StatefulWidget {
  const StudyFocusGoalCard({
    required this.model,
    required this.actions,
    this.compact = false,
    this.desktop = false,
    super.key,
  });

  final StudyFocusLayoutModel model;
  final StudyFocusActions actions;
  final bool compact;
  final bool desktop;

  @override
  State<StudyFocusGoalCard> createState() => _StudyFocusGoalCardState();
}

class _StudyFocusGoalCardState extends State<StudyFocusGoalCard> {
  final _textController = TextEditingController();
  var _goal = const TodayGoal();
  var _record = StudyDayRecord(date: DateTime(1970));
  var _loaded = false;
  var _loadGeneration = 0;
  var _saveGeneration = 0;
  StreamSubscription<StudyStoreChange>? _subscription;

  StudyStore get _store => widget.model.data.store;
  DateTime get _date => widget.model.data.date;

  @override
  void initState() {
    super.initState();
    _subscribe();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant StudyFocusGoalCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model.data.store != _store ||
        oldWidget.model.data.date != _date) {
      unawaited(_subscription?.cancel());
      _subscribe();
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _textController.dispose();
    super.dispose();
  }

  void _subscribe() {
    _subscription = _store.changes.listen((change) {
      if (!mounted ||
          (change.kind != StudyStoreChangeKind.goal &&
              change.kind != StudyStoreChangeKind.dayRecord) ||
          (change.date != null &&
              studyDateKey(change.date!) != studyDateKey(_date))) {
        return;
      }
      unawaited(_load());
    });
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final goal = await _store.loadTodayGoal(_date);
    final record = await _store.loadDayRecord(_date);
    if (!mounted || generation != _loadGeneration) {
      return;
    }
    setState(() {
      _goal = goal;
      _record = record;
      _textController.text = goal.text;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const SizedBox(
        height: 72,
        child: Center(
          child: SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return widget.desktop ? _buildDesktop(context) : _buildResponsive(context);
  }

  Widget _buildResponsive(BuildContext context) {
    final localizations = studyRoomLocalizationsOf(context);
    final target = _goal.targetPomodoros ?? 4;
    final done = _record.pomodoroCount.clamp(0, target);
    return StudyFocusGlassPanel(
      key: const Key('study_focus_goal_card'),
      borderRadius: BorderRadius.circular(16),
      padding: EdgeInsets.symmetric(
        horizontal: widget.compact ? 10 : 16,
        vertical: widget.compact ? 10 : 16,
      ),
      child: Row(
        children: [
          SizedBox.square(
            dimension: widget.compact ? 28 : 34,
            child: Checkbox(
              value: _goal.completed,
              shape: const CircleBorder(),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.56)),
              activeColor: studyFocusAccent,
              onChanged: (value) =>
                  _save(_goal.copyWith(completed: value ?? false)),
            ),
          ),
          SizedBox(width: widget.compact ? 8 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const Key('study_focus_goal_text_field'),
                  controller: _textController,
                  minLines: 1,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    isCollapsed: true,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                    hintText: localizations.defaultGoal,
                    hintStyle: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontWeight: FontWeight.w700,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                  onChanged: (value) =>
                      _save(_goal.copyWith(text: value.trim())),
                ),
                const SizedBox(height: 4),
                Text(
                  localizations.pomodoroProgress(done, target),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    final localizations = studyRoomLocalizationsOf(context);
    final target = _goal.targetPomodoros ?? 4;
    final done = _record.pomodoroCount.clamp(0, target);
    final focusMinutes = math.max(
      1,
      widget.model.data.timerConfig.focusDuration.inMinutes,
    );
    final remaining = math.max(0, target - done) * focusMinutes;
    final progress = target == 0 ? 0.0 : done / target;
    return StudyFocusGlassPanel(
      key: const Key('study_focus_goal_card'),
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 36,
            child: Checkbox(
              value: _goal.completed,
              shape: const CircleBorder(),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.56)),
              activeColor: studyFocusAccent,
              onChanged: (value) =>
                  _save(_goal.copyWith(completed: value ?? false)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _goal.text.isEmpty ? localizations.defaultGoal : _goal.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  localizations.pomodoroProgressRemaining(
                    done,
                    target,
                    remaining,
                  ),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.64),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          SizedBox(
            width: 118,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  localizations.completionPercent((progress * 100).round()),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: studyFocusAccent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    value: progress.clamp(0.0, 1.0),
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                    color: studyFocusAccent,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save(TodayGoal goal) async {
    final previous = _goal;
    final generation = ++_saveGeneration;
    setState(() => _goal = goal);
    try {
      await widget.actions.saveTodayGoal(_date, goal);
    } catch (_) {
      if (!mounted || generation != _saveGeneration) {
        return;
      }
      setState(() => _goal = previous);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(studyRoomLocalizationsOf(context).goalSaveFailed),
        ),
      );
    }
  }
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
