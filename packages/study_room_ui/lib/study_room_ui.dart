library study_room_ui;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_room_sdk/study_room_sdk.dart';

class StudyRoomTheme {
  const StudyRoomTheme({
    this.activeColor = const Color(0xFF2563EB),
    this.surfaceColor = const Color(0xFFF8FAFC),
    this.borderColor = const Color(0xFFE2E8F0),
  });

  final Color activeColor;
  final Color surfaceColor;
  final Color borderColor;
}

class StudyRoomCopy {
  const StudyRoomCopy({
    this.emptyMembers = 'No members yet',
    this.emptyMessages = 'No messages yet',
    this.reconnecting = 'Reconnecting',
    this.connected = 'Connected',
  });

  final String emptyMembers;
  final String emptyMessages;
  final String reconnecting;
  final String connected;
}

class StudyRoomView extends StatelessWidget {
  const StudyRoomView({
    required this.room,
    required this.elapsed,
    required this.sessionStatus,
    required this.messages,
    required this.onStart,
    required this.onPause,
    required this.onSendMessage,
    this.connected = true,
    this.theme = const StudyRoomTheme(),
    this.copy = const StudyRoomCopy(),
    super.key,
  });

  final StudyRoom room;
  final Duration elapsed;
  final StudySessionStatus sessionStatus;
  final List<ChatMessage> messages;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final Future<void> Function(String text) onSendMessage;
  final bool connected;
  final StudyRoomTheme theme;
  final StudyRoomCopy copy;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: theme.surfaceColor,
      child: SafeArea(
        child: Column(
          children: [
            RoomHeader(
              title: room.title,
              memberCount: room.members.length,
              connected: connected,
              copy: copy,
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 720;
                  final members = MemberGrid(
                    members: room.members,
                    copy: copy,
                    theme: theme,
                  );
                  final activity = Column(
                    children: [
                      FocusTimer(
                        elapsed: elapsed,
                        status: sessionStatus,
                        onStart: onStart,
                        onPause: onPause,
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ChatPanel(
                          messages: messages,
                          onSend: onSendMessage,
                          copy: copy,
                        ),
                      ),
                    ],
                  );
                  if (wide) {
                    return Row(
                      children: [
                        Expanded(child: members),
                        const VerticalDivider(width: 1),
                        Expanded(child: activity),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      Expanded(child: members),
                      const Divider(height: 1),
                      Expanded(child: activity),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RoomHeader extends StatelessWidget {
  const RoomHeader({
    required this.title,
    required this.memberCount,
    required this.connected,
    this.copy = const StudyRoomCopy(),
    super.key,
  });

  final String title;
  final int memberCount;
  final bool connected;
  final StudyRoomCopy copy;

  @override
  Widget build(BuildContext context) {
    final color = connected ? Colors.green.shade700 : Colors.orange.shade800;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Text('$memberCount online'),
          const SizedBox(width: 12),
          Icon(Icons.circle, color: color, size: 10),
          const SizedBox(width: 6),
          Text(connected ? copy.connected : copy.reconnecting),
        ],
      ),
    );
  }
}

class MemberGrid extends StatelessWidget {
  const MemberGrid({
    required this.members,
    this.copy = const StudyRoomCopy(),
    this.theme = const StudyRoomTheme(),
    super.key,
  });

  final List<StudyMember> members;
  final StudyRoomCopy copy;
  final StudyRoomTheme theme;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) {
      return Center(child: Text(copy.emptyMembers));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisExtent: 136,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: members.length,
      itemBuilder: (context, index) {
        final member = members[index];
        return DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: theme.borderColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.activeColor.withValues(alpha: 0.12),
                        image: member.avatarUrl.isEmpty
                            ? null
                            : DecorationImage(
                                image: NetworkImage(member.avatarUrl),
                                fit: BoxFit.cover,
                              ),
                      ),
                      child: member.avatarUrl.isEmpty
                          ? Text(_initial(member.displayName))
                          : null,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: 120,
                      child: Text(
                        member.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(_presenceLabel(member.status)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _presenceLabel(PresenceStatus status) {
    switch (status) {
      case PresenceStatus.focusing:
        return 'Focusing';
      case PresenceStatus.online:
        return 'Online';
      case PresenceStatus.idle:
        return 'Idle';
      case PresenceStatus.away:
        return 'Away';
      case PresenceStatus.offline:
        return 'Offline';
    }
  }

  String _initial(String name) {
    if (name.trim().isEmpty) {
      return '?';
    }
    return name.characters.first.toUpperCase();
  }
}

class FocusTimer extends StatelessWidget {
  const FocusTimer({
    required this.elapsed,
    required this.status,
    required this.onStart,
    required this.onPause,
    this.onResume,
    this.onFinish,
    super.key,
  });

  final Duration elapsed;
  final StudySessionStatus status;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback? onResume;
  final VoidCallback? onFinish;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _format(elapsed),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          if (status == StudySessionStatus.running)
            IconButton(
              tooltip: 'Pause',
              icon: const Icon(Icons.pause),
              onPressed: onPause,
            )
          else
            IconButton(
              tooltip: status == StudySessionStatus.paused ? 'Resume' : 'Start',
              icon: const Icon(Icons.play_arrow),
              onPressed: status == StudySessionStatus.paused
                  ? (onResume ?? onStart)
                  : onStart,
            ),
          IconButton(
            tooltip: 'Finish',
            icon: const Icon(Icons.stop),
            onPressed: onFinish,
          ),
        ],
      ),
    );
  }

  String _format(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class ChatPanel extends StatefulWidget {
  const ChatPanel({
    required this.messages,
    required this.onSend,
    this.copy = const StudyRoomCopy(),
    super.key,
  });

  final List<ChatMessage> messages;
  final Future<void> Function(String text) onSend;
  final StudyRoomCopy copy;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _controller = TextEditingController();
  var _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Column(
        children: [
          Expanded(
            child: widget.messages.isEmpty
                ? Center(child: Text(widget.copy.emptyMessages))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: widget.messages.length,
                    itemBuilder: (context, index) {
                      final message = widget.messages[index];
                      return ListTile(
                        dense: true,
                        title: Text(message.senderName),
                        subtitle: Text(message.text),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Message',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Send',
                  icon: _sending
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  onPressed: _sending ? null : _send,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }
    setState(() => _sending = true);
    try {
      await widget.onSend(text);
      _controller.clear();
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }
}

class StudyFocusKitView extends StatefulWidget {
  const StudyFocusKitView({
    this.store,
    this.currentUserId = '',
    this.room,
    this.showCompanions = true,
    this.background = const StudyBackground.color(Color(0xFFF6F7F9)),
    this.soundTracks = StudySoundTrack.builtIns,
    this.soundPlayer,
    this.date,
    super.key,
  });

  final StudyStore? store;
  final String currentUserId;
  final StudyRoom? room;
  final bool showCompanions;
  final StudyBackground background;
  final List<StudySoundTrack> soundTracks;
  final StudySoundPlayer? soundPlayer;
  final DateTime? date;

  @override
  State<StudyFocusKitView> createState() => _StudyFocusKitViewState();
}

class _StudyFocusKitViewState extends State<StudyFocusKitView> {
  StudyStore? _store;
  PomodoroController? _controller;
  var _storeLoadGeneration = 0;

  DateTime get _date => widget.date ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadStore();
  }

  @override
  void didUpdateWidget(covariant StudyFocusKitView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      _loadStore();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    widget.soundPlayer?.dispose();
    super.dispose();
  }

  Future<void> _loadStore() async {
    final generation = ++_storeLoadGeneration;
    final providedStore = widget.store;
    if (providedStore != null) {
      _setStore(providedStore, notify: _store != null);
      return;
    }

    final preferences = await SharedPreferences.getInstance();
    if (!mounted || generation != _storeLoadGeneration) {
      return;
    }
    _setStore(SharedPreferencesStudyStore(preferences));
  }

  void _setStore(StudyStore store, {bool notify = true}) {
    final previousController = _controller;
    final nextController = PomodoroController(store: store);

    void assign() {
      _store = store;
      _controller = nextController;
    }

    if (notify && mounted) {
      setState(assign);
    } else {
      assign();
    }
    previousController?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    final controller = _controller;
    final members = widget.room?.members ?? const <StudyMember>[];
    return StudyBackgroundLayer(
      background: widget.background,
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: store == null || controller == null
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 760;
                      final panels = [
                        _StudyPanel(
                          title: 'Pomodoro',
                          child: PomodoroTimerView(controller: controller),
                        ),
                        _StudyPanel(
                          title: 'Today goal',
                          child: TodayGoalView(store: store, date: _date),
                        ),
                        _StudyPanel(
                          title: 'Study records',
                          child: StudyStatsView(store: store, date: _date),
                        ),
                        _StudyPanel(
                          title: 'Personal analytics',
                          child: StudyAnalyticsView(store: store, date: _date),
                        ),
                        _StudyPanel(
                          title: 'Background sound',
                          child: BackgroundSoundView(
                            tracks: widget.soundTracks,
                            soundPlayer: widget.soundPlayer,
                          ),
                        ),
                        _StudyPanel(
                          title: 'Background',
                          child: BackgroundSettingsView(
                            background: widget.background,
                          ),
                        ),
                        if (widget.showCompanions)
                          _StudyPanel(
                            title: 'Companions',
                            child: SilentCompanionList(
                              currentUserId: widget.currentUserId,
                              members: members,
                            ),
                          ),
                      ];
                      if (!wide) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: panels
                              .map(
                                (panel) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: panel,
                                ),
                              )
                              .toList(growable: false),
                        );
                      }
                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: panels
                            .map(
                              (panel) => SizedBox(
                                width: (constraints.maxWidth - 12) / 2,
                                child: panel,
                              ),
                            )
                            .toList(growable: false),
                      );
                    },
                  ),
                ),
        ),
      ),
    );
  }
}

class _StudyPanel extends StatelessWidget {
  const _StudyPanel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class PomodoroTimerView extends StatefulWidget {
  const PomodoroTimerView({required this.controller, super.key});

  final PomodoroController controller;

  @override
  State<PomodoroTimerView> createState() => _PomodoroTimerViewState();
}

class _PomodoroTimerViewState extends State<PomodoroTimerView> {
  late PomodoroState _state = widget.controller.state;

  @override
  void initState() {
    super.initState();
    widget.controller.states.listen((state) {
      if (mounted) {
        setState(() => _state = state);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
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
                tooltip: 'Start',
                icon: const Icon(Icons.play_arrow),
                onPressed: widget.controller.start,
              ),
              IconButton(
                tooltip: 'Pause',
                icon: const Icon(Icons.pause),
                onPressed: widget.controller.pause,
              ),
              IconButton(
                tooltip: 'Resume',
                icon: const Icon(Icons.replay),
                onPressed: widget.controller.resume,
              ),
              IconButton(
                tooltip: 'End',
                icon: const Icon(Icons.stop),
                onPressed: widget.controller.end,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(_statusLabel(_state.status)),
        ],
      ),
    );
  }

  String _format(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _statusLabel(PomodoroStatus status) {
    return switch (status) {
      PomodoroStatus.idle => 'Idle',
      PomodoroStatus.focusing => 'Focusing',
      PomodoroStatus.paused => 'Paused',
      PomodoroStatus.breaking => 'Break',
      PomodoroStatus.finished => 'Finished',
    };
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _textController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final goal = await widget.store.loadTodayGoal(widget.date);
    if (!mounted) {
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
            decoration: const InputDecoration(
              labelText: 'Today goal',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _save(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _targetController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Target pomodoros',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => _save(),
                ),
              ),
              const SizedBox(width: 8),
              Checkbox(
                value: _completed,
                onChanged: (value) {
                  setState(() => _completed = value ?? false);
                  _save();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save() {
    final target = int.tryParse(_targetController.text.trim());
    return widget.store.saveTodayGoal(
      widget.date,
      TodayGoal(
        text: _textController.text.trim(),
        targetPomodoros: target,
        completed: _completed,
      ),
    );
  }
}

class StudyStatsView extends StatelessWidget {
  const StudyStatsView({required this.store, required this.date, super.key});

  final StudyStore store;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StudyStats>(
      future: StudyAnalytics(store).statsFor(date),
      builder: (context, snapshot) {
        final stats = snapshot.data;
        if (stats == null) {
          return const LinearProgressIndicator();
        }
        return Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            _Metric(
              label: 'Focus',
              value: '${stats.todayFocusDuration.inMinutes} min',
            ),
            _Metric(label: 'Pomodoros', value: '${stats.todayPomodoroCount}'),
            _Metric(label: 'Streak', value: '${stats.streakDays} days'),
          ],
        );
      },
    );
  }
}

class StudyAnalyticsView extends StatelessWidget {
  const StudyAnalyticsView({
    required this.store,
    required this.date,
    super.key,
  });

  final StudyStore store;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StudyStats>(
      future: StudyAnalytics(store).statsFor(date),
      builder: (context, snapshot) {
        final stats = snapshot.data;
        if (stats == null) {
          return const LinearProgressIndicator();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _Metric(
                  label: 'Today',
                  value: '${stats.todayFocusDuration.inMinutes} min',
                ),
                _Metric(
                  label: 'Count',
                  value: '${stats.todayPomodoroCount} pomodoros',
                ),
                _Metric(label: 'Run', value: '${stats.streakDays} days'),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 42,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: stats.lastSevenDays
                    .map((day) {
                      final height = (day.focusDuration.inMinutes / 120).clamp(
                        0.04,
                        1.0,
                      );
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: FractionallySizedBox(
                            heightFactor: height,
                            alignment: Alignment.bottomCenter,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
            ),
          ],
        );
      },
    );
  }
}

class StudyReportView extends StatelessWidget {
  const StudyReportView({
    required this.store,
    required this.range,
    required this.date,
    super.key,
  });

  final StudyStore store;
  final StudyReportRange range;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StudyReport>(
      future: StudyAnalytics(store).report(range, date),
      builder: (context, snapshot) {
        final report = snapshot.data;
        if (report == null) {
          return const LinearProgressIndicator();
        }
        final rate = report.taskCompletionRate == null
            ? 'No tasks'
            : '${(report.taskCompletionRate! * 100).round()}% complete';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _Metric(
                  label: 'Total',
                  value: '${report.totalFocusDuration.inMinutes} min',
                ),
                _Metric(
                  label: 'Sessions',
                  value: '${report.totalPomodoroCount} pomodoros',
                ),
                _Metric(label: 'Tasks', value: rate),
              ],
            ),
            const SizedBox(height: 8),
            Text(report.summary),
          ],
        );
      },
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 84),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}

enum StudySoundSourceType { asset, network, file, uri }

class StudySoundTrack {
  const StudySoundTrack.asset({
    required this.id,
    required this.label,
    required String path,
  }) : sourceType = StudySoundSourceType.asset,
       source = path;

  const StudySoundTrack.network({
    required this.id,
    required this.label,
    required String url,
  }) : sourceType = StudySoundSourceType.network,
       source = url;

  const StudySoundTrack.file({
    required this.id,
    required this.label,
    required String path,
  }) : sourceType = StudySoundSourceType.file,
       source = path;

  const StudySoundTrack.uri({
    required this.id,
    required this.label,
    required String uri,
  }) : sourceType = StudySoundSourceType.uri,
       source = uri;

  final String id;
  final String label;
  final StudySoundSourceType sourceType;
  final String source;

  static const builtIns = [
    StudySoundTrack.asset(
      id: 'rain',
      label: 'Rain',
      path: 'assets/audio/rain.wav',
    ),
    StudySoundTrack.asset(
      id: 'white_noise',
      label: 'White noise',
      path: 'assets/audio/white_noise.wav',
    ),
    StudySoundTrack.asset(
      id: 'cafe',
      label: 'Cafe',
      path: 'assets/audio/cafe.wav',
    ),
    StudySoundTrack.asset(
      id: 'library',
      label: 'Library',
      path: 'assets/audio/library.wav',
    ),
    StudySoundTrack.asset(
      id: 'keyboard',
      label: 'Keyboard',
      path: 'assets/audio/keyboard.wav',
    ),
  ];
}

abstract class StudySoundPlayer {
  Future<void> play(StudySoundTrack track, {double volume = 0.5});

  Future<void> pause();

  Future<void> setVolume(double volume);

  Future<void> dispose();
}

class JustAudioStudySoundPlayer implements StudySoundPlayer {
  JustAudioStudySoundPlayer({AudioPlayer? player})
    : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Future<void> play(StudySoundTrack track, {double volume = 0.5}) async {
    await _player.setLoopMode(LoopMode.one);
    await _player.setVolume(volume.clamp(0.0, 1.0));
    switch (track.sourceType) {
      case StudySoundSourceType.asset:
        await _player.setAsset(track.source, package: 'study_room_ui');
      case StudySoundSourceType.network:
        await _player.setUrl(track.source);
      case StudySoundSourceType.file:
        await _player.setFilePath(track.source);
      case StudySoundSourceType.uri:
        await _player.setAudioSource(AudioSource.uri(Uri.parse(track.source)));
    }
    await _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> setVolume(double volume) =>
      _player.setVolume(volume.clamp(0.0, 1.0));

  @override
  Future<void> dispose() => _player.dispose();
}

class BackgroundSoundView extends StatefulWidget {
  const BackgroundSoundView({
    this.tracks = StudySoundTrack.builtIns,
    this.soundPlayer,
    super.key,
  });

  final List<StudySoundTrack> tracks;
  final StudySoundPlayer? soundPlayer;

  @override
  State<BackgroundSoundView> createState() => _BackgroundSoundViewState();
}

class _BackgroundSoundViewState extends State<BackgroundSoundView> {
  late final StudySoundPlayer _player =
      widget.soundPlayer ?? JustAudioStudySoundPlayer();
  late StudySoundTrack? _selected = widget.tracks.isEmpty
      ? null
      : widget.tracks.first;
  var _playing = false;
  var _volume = 0.5;

  @override
  void dispose() {
    if (widget.soundPlayer == null) {
      _player.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.tracks
                .map((track) {
                  return ChoiceChip(
                    label: Text(track.label),
                    selected: _selected?.id == track.id,
                    onSelected: (_) => setState(() => _selected = track),
                  );
                })
                .toList(growable: false),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton.filled(
                tooltip: 'Play',
                icon: const Icon(Icons.play_arrow),
                onPressed: _selected == null
                    ? null
                    : () async {
                        await _player.play(_selected!, volume: _volume);
                        if (mounted) {
                          setState(() => _playing = true);
                        }
                      },
              ),
              IconButton(
                tooltip: 'Pause',
                icon: const Icon(Icons.pause),
                onPressed: !_playing
                    ? null
                    : () async {
                        await _player.pause();
                        if (mounted) {
                          setState(() => _playing = false);
                        }
                      },
              ),
              Expanded(
                child: Slider(
                  value: _volume,
                  onChanged: (value) {
                    setState(() => _volume = value);
                    _player.setVolume(value);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum StudyBackgroundType { color, image, gradient }

class StudyBackground {
  const StudyBackground.color(Color color, {double maskOpacity = 0.35})
    : this._(
        type: StudyBackgroundType.color,
        color: color,
        maskOpacity: maskOpacity,
      );

  const StudyBackground.image({
    required ImageProvider image,
    double maskOpacity = 0.45,
  }) : this._(
         type: StudyBackgroundType.image,
         image: image,
         maskOpacity: maskOpacity,
       );

  const StudyBackground.gradient({
    required List<Color> colors,
    double maskOpacity = 0.35,
  }) : this._(
         type: StudyBackgroundType.gradient,
         gradientColors: colors,
         maskOpacity: maskOpacity,
       );

  const StudyBackground._({
    required this.type,
    this.color,
    this.image,
    this.gradientColors = const [],
    double maskOpacity = 0.35,
  }) : maskOpacity = maskOpacity < 0
           ? 0
           : maskOpacity > 0.85
           ? 0.85
           : maskOpacity;

  final StudyBackgroundType type;
  final Color? color;
  final ImageProvider? image;
  final List<Color> gradientColors;
  final double maskOpacity;
}

class StudyBackgroundLayer extends StatelessWidget {
  const StudyBackgroundLayer({
    required this.background,
    required this.child,
    super.key,
  });

  final StudyBackground background;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(decoration: _decoration()),
        ColoredBox(
          color: Colors.black.withValues(alpha: background.maskOpacity),
        ),
        child,
      ],
    );
  }

  BoxDecoration _decoration() {
    return switch (background.type) {
      StudyBackgroundType.color => BoxDecoration(
        color: background.color ?? const Color(0xFFF6F7F9),
      ),
      StudyBackgroundType.image => BoxDecoration(
        image: background.image == null
            ? null
            : DecorationImage(image: background.image!, fit: BoxFit.cover),
      ),
      StudyBackgroundType.gradient => BoxDecoration(
        gradient: LinearGradient(
          colors: background.gradientColors.isEmpty
              ? const [Color(0xFFF6F7F9), Colors.white]
              : background.gradientColors,
        ),
      ),
    };
  }
}

class BackgroundSettingsView extends StatelessWidget {
  const BackgroundSettingsView({required this.background, super.key});

  final StudyBackground background;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Row(
        children: [
          _BackgroundSwatch(background: background),
          const SizedBox(width: 12),
          Expanded(
            child: Slider(value: background.maskOpacity, onChanged: null),
          ),
        ],
      ),
    );
  }
}

class _BackgroundSwatch extends StatelessWidget {
  const _BackgroundSwatch({required this.background});

  final StudyBackground background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
        color: background.color,
        gradient: background.type == StudyBackgroundType.gradient
            ? LinearGradient(colors: background.gradientColors)
            : null,
        image: background.image == null
            ? null
            : DecorationImage(image: background.image!, fit: BoxFit.cover),
      ),
    );
  }
}

class SilentCompanionTheme {
  const SilentCompanionTheme({
    this.avatarSize = 40,
    this.focusingColor = const Color(0xFF16A34A),
    this.onlineColor = const Color(0xFF2563EB),
    this.idleColor = const Color(0xFF64748B),
    this.awayColor = const Color(0xFFF59E0B),
  });

  final double avatarSize;
  final Color focusingColor;
  final Color onlineColor;
  final Color idleColor;
  final Color awayColor;

  Color colorFor(PresenceStatus status) {
    return switch (status) {
      PresenceStatus.focusing => focusingColor,
      PresenceStatus.online => onlineColor,
      PresenceStatus.idle => idleColor,
      PresenceStatus.away => awayColor,
      PresenceStatus.offline => idleColor,
    };
  }

  IconData iconFor(PresenceStatus status) {
    return switch (status) {
      PresenceStatus.focusing => Icons.radio_button_checked,
      PresenceStatus.away => Icons.local_cafe,
      PresenceStatus.online || PresenceStatus.idle => Icons.circle_outlined,
      PresenceStatus.offline => Icons.circle_outlined,
    };
  }
}

class SilentCompanionList extends StatelessWidget {
  const SilentCompanionList({
    required this.currentUserId,
    required this.members,
    this.theme = const SilentCompanionTheme(),
    super.key,
  });

  final String currentUserId;
  final List<StudyMember> members;
  final SilentCompanionTheme theme;

  @override
  Widget build(BuildContext context) {
    final visible = members
        .where(
          (member) =>
              member.id != currentUserId &&
              member.status != PresenceStatus.offline,
        )
        .toList(growable: false);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: visible.isEmpty
          ? const SizedBox(
              height: 48,
              child: Center(child: Text('No companions')),
            )
          : Wrap(
              key: ValueKey(visible.map((member) => member.id).join(',')),
              spacing: 10,
              runSpacing: 10,
              children: visible
                  .map(
                    (member) => _CompanionAvatar(member: member, theme: theme),
                  )
                  .toList(growable: false),
            ),
    );
  }
}

class _CompanionAvatar extends StatelessWidget {
  const _CompanionAvatar({required this.member, required this.theme});

  final StudyMember member;
  final SilentCompanionTheme theme;

  @override
  Widget build(BuildContext context) {
    final size = theme.avatarSize;
    final color = theme.colorFor(member.status);
    return SizedBox(
      width: size + 28,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2),
                  image: member.avatarUrl.isEmpty
                      ? null
                      : DecorationImage(
                          image: NetworkImage(member.avatarUrl),
                          fit: BoxFit.cover,
                        ),
                  color: color.withValues(alpha: 0.10),
                ),
                child: member.avatarUrl.isEmpty
                    ? Text(_initial(member.displayName))
                    : null,
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    theme.iconFor(member.status),
                    size: 16,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            member.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _initial(String name) {
    if (name.trim().isEmpty) {
      return '?';
    }
    return name.characters.first.toUpperCase();
  }
}

class SharedPreferencesStudyStore implements StudyStore {
  SharedPreferencesStudyStore(this.preferences, {this.prefix = 'study_focus'});

  final SharedPreferences preferences;
  final String prefix;

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
    await preferences.setString(_goalKey(date), jsonEncode(goal.toJson()));
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
    await preferences.setString(
      _recordKey(record.date),
      jsonEncode(record.toJson()),
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
    final tasks = List<StudyTaskRecord>.of(await loadTaskRecords(date));
    final index = tasks.indexWhere((existing) => existing.id == task.id);
    if (index == -1) {
      tasks.add(task);
    } else {
      tasks[index] = task;
    }
    await preferences.setString(
      _taskKey(date),
      jsonEncode(tasks.map((task) => task.toJson()).toList(growable: false)),
    );
  }

  String _goalKey(DateTime date) => '$prefix:goal:${_dateKey(date)}';

  String _recordKey(DateTime date) => '$prefix:record:${_dateKey(date)}';

  String _taskKey(DateTime date) => '$prefix:task:${_dateKey(date)}';
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

String _dateKey(DateTime date) {
  final day = _dateOnly(date);
  return '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
}
