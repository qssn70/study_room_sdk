import 'dart:async';

import 'package:flutter/material.dart';
import 'package:study_room_sdk/study_room_sdk.dart';

import 'focus_formatters.dart';
import 'localizations.dart';

class PomodoroTimerView extends StatefulWidget {
  const PomodoroTimerView({required this.controller, super.key});

  final PomodoroController controller;

  @override
  State<PomodoroTimerView> createState() => _PomodoroTimerViewState();
}

class _PomodoroTimerViewState extends State<PomodoroTimerView> {
  late PomodoroState _state = widget.controller.state;
  StreamSubscription<PomodoroState>? _subscription;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(covariant PomodoroTimerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _subscription?.cancel();
      _state = widget.controller.state;
      _error = null;
      _listen();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _listen() {
    _subscription = widget.controller.states.listen(
      (state) {
        if (mounted) {
          setState(() {
            _state = state;
            _error = null;
          });
        }
      },
      onError: (Object error) {
        if (mounted) {
          setState(() => _error = error);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = studyRoomLocalizationsOf(context);
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _format(_state.remaining),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              IconButton.filled(
                tooltip: localizations.start,
                icon: const Icon(Icons.play_arrow),
                onPressed: widget.controller.start,
              ),
              IconButton(
                tooltip: localizations.pause,
                icon: const Icon(Icons.pause),
                onPressed: widget.controller.pause,
              ),
              IconButton(
                tooltip: localizations.resume,
                icon: const Icon(Icons.replay),
                onPressed: widget.controller.resume,
              ),
              IconButton(
                tooltip: localizations.finish,
                icon: const Icon(Icons.stop),
                onPressed: widget.controller.end,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(pomodoroStatusLabel(_state.status, localizations)),
          if (_error != null) Text(localizations.unableToSaveFocusSession),
        ],
      ),
    );
  }

  String _format(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class TodayGoalView extends StatefulWidget {
  const TodayGoalView({required this.store, required this.date, super.key});

  final StudyStore store;
  final DateTime date;

  @override
  State<TodayGoalView> createState() => _TodayGoalViewState();
}

class _TodayGoalViewState extends State<TodayGoalView> {
  final _textController = TextEditingController();
  final _targetController = TextEditingController();
  var _completed = false;
  var _loaded = false;
  var _loadGeneration = 0;
  var _saveGeneration = 0;
  StreamSubscription<StudyStoreChange>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscribe();
    _load();
  }

  @override
  void didUpdateWidget(covariant TodayGoalView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store || oldWidget.date != widget.date) {
      unawaited(_subscription?.cancel());
      _subscribe();
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _textController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  void _subscribe() {
    _subscription = widget.store.changes.listen((change) {
      if (!mounted ||
          change.kind != StudyStoreChangeKind.goal ||
          (change.date != null &&
              studyDateKey(change.date!) != studyDateKey(widget.date))) {
        return;
      }
      unawaited(_load());
    });
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final goal = await widget.store.loadTodayGoal(widget.date);
    if (!mounted || generation != _loadGeneration) {
      return;
    }
    setState(() {
      _textController.text = goal.text;
      _targetController.text = goal.targetPomodoros?.toString() ?? '';
      _completed = goal.completed;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final localizations = studyRoomLocalizationsOf(context);
    if (!_loaded) {
      return const SizedBox.square(
        dimension: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Material(
      type: MaterialType.transparency,
      child: Column(
        children: [
          TextField(
            controller: _textController,
            decoration: InputDecoration(
              labelText: localizations.todayGoalLabel,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => unawaited(_save()),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _targetController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: localizations.targetPomodoros,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => unawaited(_save()),
                ),
              ),
              const SizedBox(width: 8),
              Checkbox(
                value: _completed,
                onChanged: (value) {
                  setState(() => _completed = value ?? false);
                  unawaited(_save());
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final target = int.tryParse(_targetController.text.trim());
    final generation = ++_saveGeneration;
    try {
      await widget.store.saveTodayGoal(
        widget.date,
        TodayGoal(
          text: _textController.text.trim(),
          targetPomodoros: target,
          completed: _completed,
        ),
      );
    } catch (_) {
      if (!mounted || generation != _saveGeneration) {
        return;
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(studyRoomLocalizationsOf(context).goalSaveFailed),
          ),
        );
      }
    }
  }
}
