library study_room_ui;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

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

enum StudyFocusVisualStyle { split, centered, immersiveDock }

const studyFocusDefaultBackgroundImageUrl =
    'https://images.unsplash.com/photo-1419242902214-272b3f66ee7a?q=80&w=2000&auto=format&fit=crop';

const studyFocusDefaultBackground = StudyBackground.image(
  image: NetworkImage(studyFocusDefaultBackgroundImageUrl),
  maskOpacity: 0.25,
);

const _studyFocusAccent = Color(0xFF81C784);
const _studyFocusRest = Color(0xFFFFB74D);

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
    this.background = studyFocusDefaultBackground,
    this.visualStyle = StudyFocusVisualStyle.immersiveDock,
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
  final StudyFocusVisualStyle visualStyle;
  final List<StudySoundTrack> soundTracks;
  final StudySoundPlayer? soundPlayer;
  final DateTime? date;

  @override
  State<StudyFocusKitView> createState() => _StudyFocusKitViewState();
}

enum _FocusDockPanel { stats, sound, members }

class _StudyFocusKitViewState extends State<StudyFocusKitView> {
  StudyStore? _store;
  PomodoroController? _controller;
  var _storeLoadGeneration = 0;
  _FocusDockPanel? _activeDockPanel;

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
      child: Theme(
        data: _visualTheme(context),
        child: Material(
          type: MaterialType.transparency,
          child: SafeArea(
            bottom: widget.visualStyle != StudyFocusVisualStyle.immersiveDock,
            child: store == null || controller == null
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final landscape =
                          constraints.maxWidth > constraints.maxHeight;
                      final sidePanelLayout =
                          constraints.maxWidth >= 760 || landscape;
                      final keySuffix = sidePanelLayout
                          ? 'landscape'
                          : 'portrait';
                      final styleKey = Key(
                        'study_focus_style_${widget.visualStyle.name}_$keySuffix',
                      );
                      final sound = BackgroundSoundView(
                        tracks: widget.soundTracks,
                        soundPlayer: widget.soundPlayer,
                      );
                      final companionTheme = SilentCompanionTheme(
                        avatarSize: sidePanelLayout ? 32 : 40,
                        focusingColor: _studyFocusAccent,
                        onlineColor: _studyFocusAccent,
                        idleColor: Colors.white.withValues(alpha: 0.42),
                        awayColor: _studyFocusRest,
                      );
                      final companions = SilentCompanionList(
                        currentUserId: widget.currentUserId,
                        members: members,
                        theme: companionTheme,
                      );
                      final desktopLandscape =
                          landscape && constraints.maxWidth >= 1100;
                      if (desktopLandscape) {
                        return _StudyFocusDesktopShell(
                          key: styleKey,
                          controller: controller,
                          store: store,
                          date: _date,
                          sizing: _StudyFocusSizing.fromConstraints(
                            constraints,
                            landscape: true,
                          ),
                          members: widget.showCompanions
                              ? companions
                              : const SizedBox.shrink(),
                          onlineCount: members
                              .where(
                                (member) =>
                                    member.id != widget.currentUserId &&
                                    member.status != PresenceStatus.offline,
                              )
                              .length,
                        );
                      }
                      if (sidePanelLayout) {
                        return _StudyFocusLandscapeShell(
                          key: styleKey,
                          controller: controller,
                          store: store,
                          date: _date,
                          sizing: _StudyFocusSizing.fromConstraints(
                            constraints,
                            landscape: true,
                          ),
                          members: widget.showCompanions
                              ? companions
                              : const SizedBox.shrink(),
                        );
                      }
                      return _StudyFocusPortraitShell(
                        key: styleKey,
                        controller: controller,
                        store: store,
                        date: _date,
                        sizing: _StudyFocusSizing.fromConstraints(
                          constraints,
                          landscape: false,
                        ),
                        members: widget.showCompanions
                            ? companions
                            : const SizedBox.shrink(),
                        sound: sound,
                        background: widget.background,
                        visualStyle: widget.visualStyle,
                        activePanel: _activeDockPanel,
                        onDockPanelChanged: (panel) {
                          setState(() {
                            _activeDockPanel = _activeDockPanel == panel
                                ? null
                                : panel;
                          });
                        },
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }

  ThemeData _visualTheme(BuildContext context) {
    final base = Theme.of(context);
    final scheme = ColorScheme.fromSeed(
      seedColor: _studyFocusAccent,
      brightness: Brightness.dark,
      primary: _studyFocusAccent,
      secondary: _studyFocusRest,
      surface: Colors.white.withValues(alpha: 0.10),
    );
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      iconTheme: const IconThemeData(color: Colors.white),
      textTheme: base.textTheme.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.08),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
        ),
      ),
    );
  }
}

class _StudyFocusPortraitShell extends StatelessWidget {
  const _StudyFocusPortraitShell({
    required this.controller,
    required this.store,
    required this.date,
    required this.sizing,
    required this.members,
    required this.sound,
    required this.background,
    required this.visualStyle,
    required this.activePanel,
    required this.onDockPanelChanged,
    super.key,
  });

  final PomodoroController controller;
  final StudyStore store;
  final DateTime date;
  final _StudyFocusSizing sizing;
  final Widget members;
  final Widget sound;
  final StudyBackground background;
  final StudyFocusVisualStyle visualStyle;
  final _FocusDockPanel? activePanel;
  final ValueChanged<_FocusDockPanel> onDockPanelChanged;

  @override
  Widget build(BuildContext context) {
    final immersive = visualStyle == StudyFocusVisualStyle.immersiveDock;
    final split = visualStyle == StudyFocusVisualStyle.split;
    final goal = _StudyFocusGoalCard(store: store, date: date);
    final core = _StudyFocusCoreCluster(
      controller: controller,
      sizing: sizing,
      goal: split ? null : goal,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        Align(
          alignment: split ? const Alignment(0, -0.42) : Alignment.center,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: core,
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              immersive ? 0 : 24,
              0,
              immersive ? 0 : 24,
              immersive ? 0 : 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PortraitDockDrawer(
                  activePanel: activePanel,
                  members: members,
                  sound: sound,
                  stats: StudyAnalyticsView(store: store, date: date),
                ),
                if (split) ...[const SizedBox(height: 16), goal],
                const SizedBox(height: 16),
                _FocusDock(
                  immersive: immersive,
                  activePanel: activePanel,
                  onChanged: onDockPanelChanged,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StudyFocusLandscapeShell extends StatelessWidget {
  const _StudyFocusLandscapeShell({
    required this.controller,
    required this.store,
    required this.date,
    required this.sizing,
    required this.members,
    super.key,
  });

  final PomodoroController controller;
  final StudyStore store;
  final DateTime date;
  final _StudyFocusSizing sizing;
  final Widget members;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 14,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Center(
              child: _StudyFocusCoreCluster(
                controller: controller,
                sizing: sizing,
              ),
            ),
          ),
        ),
        Expanded(
          flex: 10,
          child: _LandscapeInfoPanel(
            members: members,
            goal: _StudyFocusGoalCard(store: store, date: date, compact: true),
            sound: const _PrototypeSoundBar(),
            stats: _PrototypeStatsOverview(store: store, date: date),
          ),
        ),
      ],
    );
  }
}

class _StudyFocusDesktopShell extends StatelessWidget {
  const _StudyFocusDesktopShell({
    required this.controller,
    required this.store,
    required this.date,
    required this.sizing,
    required this.members,
    required this.onlineCount,
    super.key,
  });

  final PomodoroController controller;
  final StudyStore store;
  final DateTime date;
  final _StudyFocusSizing sizing;
  final Widget members;
  final int onlineCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('study_focus_desktop_shell'),
      children: [
        const _DesktopTopNav(),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(56, 30, 56, 34),
                  child: Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: _StudyFocusDesktopCore(
                            controller: controller,
                            sizing: sizing,
                          ),
                        ),
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: _StudyFocusDesktopGoalCard(
                          store: store,
                          date: date,
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
                  onlineCount: onlineCount,
                  stats: _PrototypeStatsOverview(store: store, date: date),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DesktopTopNav extends StatelessWidget {
  const _DesktopTopNav();

  @override
  Widget build(BuildContext context) {
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
                  color: _studyFocusAccent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '极简自习室',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 36),
              const _DesktopNavItem('专注', selected: true),
              const _DesktopNavItem('数据统计'),
              const _DesktopNavItem('历史记录'),
              const _DesktopNavItem('设置'),
              const Spacer(),
              Text(
                _formatClock(TimeOfDay.now()),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.66),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 18),
              FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建任务'),
                style: FilledButton.styleFrom(
                  backgroundColor: _studyFocusAccent,
                  foregroundColor: const Color(0xFF10251A),
                  minimumSize: const Size(112, 38),
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

  static String _formatClock(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _DesktopNavItem extends StatelessWidget {
  const _DesktopNavItem(this.label, {this.selected = false});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 26),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Colors.white.withValues(alpha: selected ? 0.96 : 0.58),
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
    );
  }
}

class _StudyFocusDesktopCore extends StatelessWidget {
  const _StudyFocusDesktopCore({
    required this.controller,
    required this.sizing,
  });

  final PomodoroController controller;
  final _StudyFocusSizing sizing;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: _DesktopPresetBar()),
          const SizedBox(height: 34),
          Center(
            child: _VisualPomodoroTimer(
              key: const Key('study_focus_timer'),
              controller: controller,
              size: sizing.timerSize,
            ),
          ),
          const SizedBox(height: 34),
          _DesktopTimerControls(controller: controller),
        ],
      ),
    );
  }
}

class _DesktopPresetBar extends StatelessWidget {
  const _DesktopPresetBar();

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      borderRadius: BorderRadius.circular(999),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          _PresetChip(label: '25 / 5 分钟', selected: true),
          _PresetChip(label: '50 / 10 分钟'),
          _PresetChip(label: '自定义时长'),
        ],
      ),
    );
  }
}

class _DesktopTimerControls extends StatelessWidget {
  const _DesktopTimerControls({required this.controller});

  final PomodoroController controller;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PomodoroState>(
      stream: controller.states,
      initialData: controller.state,
      builder: (context, snapshot) {
        final status = snapshot.data?.status ?? PomodoroStatus.idle;
        final running =
            status == PomodoroStatus.focusing ||
            status == PomodoroStatus.breaking;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ControlTextButton(label: '结束当前轮次', onPressed: controller.end),
            const SizedBox(width: 28),
            _GlassPanel(
              borderRadius: BorderRadius.circular(999),
              padding: EdgeInsets.zero,
              child: SizedBox.square(
                dimension: 68,
                child: IconButton(
                  tooltip: running ? '暂停' : '开始',
                  icon: Icon(
                    running ? Icons.pause : Icons.play_arrow,
                    size: 30,
                  ),
                  onPressed: running ? controller.pause : controller.start,
                ),
              ),
            ),
            const SizedBox(width: 28),
            _ControlTextButton(label: '跳至休息', onPressed: controller.resume),
          ],
        );
      },
    );
  }
}

class _StudyFocusDesktopGoalCard extends StatelessWidget {
  const _StudyFocusDesktopGoalCard({required this.store, required this.date});

  final StudyStore store;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(TodayGoal, StudyDayRecord)>(
      future: _load(),
      builder: (context, snapshot) {
        final goal = snapshot.data?.$1 ?? const TodayGoal();
        final record = snapshot.data?.$2 ?? StudyDayRecord(date: date);
        final target = goal.targetPomodoros ?? 4;
        final done = record.pomodoroCount.clamp(0, target);
        final remaining = math.max(0, target - done) * 25;
        final progress = target == 0 ? 0.0 : done / target;
        return _GlassPanel(
          key: const Key('study_focus_goal_card'),
          borderRadius: BorderRadius.circular(16),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 36,
                child: Checkbox(
                  value: goal.completed,
                  shape: const CircleBorder(),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.56)),
                  activeColor: _studyFocusAccent,
                  onChanged: (value) {
                    store.saveTodayGoal(date, goal.copyWith(completed: value));
                  },
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      goal.text.isEmpty ? '完成 SDK 文档编写' : goal.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '番茄进度: $done/$target | 预计还需 $remaining 分钟',
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
                      '${(progress * 100).round()}% 完成度',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: _studyFocusAccent,
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
                        color: _studyFocusAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<(TodayGoal, StudyDayRecord)> _load() async {
    final goal = await store.loadTodayGoal(date);
    final record = await store.loadDayRecord(date);
    return (goal, record);
  }
}

class _DesktopSidePanel extends StatelessWidget {
  const _DesktopSidePanel({
    required this.members,
    required this.onlineCount,
    required this.stats,
  });

  final Widget members;
  final int onlineCount;
  final Widget stats;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      borderRadius: BorderRadius.zero,
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DesktopSectionHeader(title: '静默陪伴', trailing: '在线 $onlineCount 人'),
            const SizedBox(height: 14),
            _DesktopPanelCard(child: members),
            const SizedBox(height: 24),
            const _DesktopSectionHeader(title: '白噪音'),
            const SizedBox(height: 12),
            const _DesktopSoundGrid(),
            const SizedBox(height: 24),
            const _DesktopSectionHeader(title: '今日数据 (私密)'),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(padding: const EdgeInsets.all(12), child: child),
    );
  }
}

class _DesktopSoundGrid extends StatelessWidget {
  const _DesktopSoundGrid();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(
          child: _DesktopSoundTile(icon: Icons.water_drop, label: '雨声'),
        ),
        SizedBox(width: 10),
        Expanded(
          child: _DesktopSoundTile(icon: Icons.fireplace, label: '壁炉'),
        ),
        SizedBox(width: 10),
        Expanded(
          child: _DesktopSoundTile(icon: Icons.local_cafe, label: '咖啡'),
        ),
      ],
    );
  }
}

class _DesktopSoundTile extends StatelessWidget {
  const _DesktopSoundTile({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: [
            Icon(icon, size: 22, color: _studyFocusAccent),
            const SizedBox(height: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.78),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StudyFocusCoreCluster extends StatelessWidget {
  const _StudyFocusCoreCluster({
    required this.controller,
    required this.sizing,
    this.goal,
  });

  final PomodoroController controller;
  final _StudyFocusSizing sizing;
  final Widget? goal;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: sizing.coreMaxWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: _PresetBar()),
          SizedBox(height: sizing.clusterGap),
          Center(
            child: _VisualPomodoroTimer(
              key: const Key('study_focus_timer'),
              controller: controller,
              size: sizing.timerSize,
            ),
          ),
          SizedBox(height: sizing.clusterGap),
          _VisualTimerControls(
            controller: controller,
            buttonSize: sizing.controlButtonSize,
            gap: sizing.controlGap,
          ),
          if (goal != null) ...[SizedBox(height: sizing.goalGap), goal!],
        ],
      ),
    );
  }
}

class _StudyFocusSizing {
  const _StudyFocusSizing({
    required this.timerSize,
    required this.coreMaxWidth,
    required this.clusterGap,
    required this.goalGap,
    required this.controlButtonSize,
    required this.controlGap,
  });

  final double timerSize;
  final double coreMaxWidth;
  final double clusterGap;
  final double goalGap;
  final double controlButtonSize;
  final double controlGap;

  factory _StudyFocusSizing.fromConstraints(
    BoxConstraints constraints, {
    required bool landscape,
  }) {
    final width = _finiteDimension(constraints.maxWidth, fallback: 390);
    final height = _finiteDimension(constraints.maxHeight, fallback: 844);
    final timerSize = landscape
        ? math.min(width * 0.25, height * 0.48).clamp(176.0, 380.0).toDouble()
        : math.min(width * 0.58, height * 0.32).clamp(220.0, 340.0).toDouble();
    final scale = (timerSize / 220).clamp(0.85, 1.25).toDouble();

    return _StudyFocusSizing(
      timerSize: timerSize,
      coreMaxWidth: math
          .max(342.0, timerSize + 96)
          .clamp(342.0, 520.0)
          .toDouble(),
      clusterGap: 24 * scale,
      goalGap: 32 * scale,
      controlButtonSize: 56 * scale,
      controlGap: 24 * scale,
    );
  }

  static double _finiteDimension(double value, {required double fallback}) {
    if (!value.isFinite || value <= 0) {
      return fallback;
    }
    return value;
  }
}

class _PresetBar extends StatelessWidget {
  const _PresetBar();

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      borderRadius: BorderRadius.circular(999),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          _PresetChip(label: '25/5', selected: true),
          _PresetChip(label: '50/10'),
          _PresetChip(label: '自定义'),
        ],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.label, this.selected = false});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
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
    );
  }
}

class _VisualPomodoroTimer extends StatefulWidget {
  const _VisualPomodoroTimer({
    required this.controller,
    required this.size,
    super.key,
  });

  final PomodoroController controller;
  final double size;

  @override
  State<_VisualPomodoroTimer> createState() => _VisualPomodoroTimerState();
}

class _VisualPomodoroTimerState extends State<_VisualPomodoroTimer> {
  late PomodoroState _state = widget.controller.state;
  StreamSubscription<PomodoroState>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.controller.states.listen((state) {
      if (mounted) {
        setState(() => _state = state);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _VisualPomodoroTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _subscription?.cancel();
      _state = widget.controller.state;
      _subscription = widget.controller.states.listen((state) {
        if (mounted) {
          setState(() => _state = state);
        }
      });
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = _state.status == PomodoroStatus.breaking
        ? widget.controller.config.breakDuration
        : widget.controller.config.focusDuration;
    final progress = total == Duration.zero
        ? 0.0
        : 1 - (_state.remaining.inMilliseconds / total.inMilliseconds);
    final color = _state.status == PomodoroStatus.breaking
        ? _studyFocusRest
        : _studyFocusAccent;
    final innerSize = widget.size >= 200 ? widget.size - 24 : widget.size - 20;
    return SizedBox.square(
      dimension: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.square(
            dimension: widget.size,
            child: CircularProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              strokeWidth: widget.size >= 200 ? 12 : 10,
              backgroundColor: Colors.white.withValues(alpha: 0.16),
              color: color,
              strokeCap: StrokeCap.round,
            ),
          ),
          _GlassPanel(
            borderRadius: BorderRadius.circular(widget.size / 2),
            padding: EdgeInsets.zero,
            child: SizedBox.square(
              dimension: innerSize,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _format(_state.remaining),
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontSize: widget.size >= 200 ? 48 : 36,
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
                    _statusLabel(_state.status),
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

  String _format(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _statusLabel(PomodoroStatus status) {
    return switch (status) {
      PomodoroStatus.idle => '准备专注',
      PomodoroStatus.focusing => '专注中',
      PomodoroStatus.paused => '已暂停',
      PomodoroStatus.breaking => '休息中',
      PomodoroStatus.finished => '已完成',
    };
  }
}

class _VisualTimerControls extends StatelessWidget {
  const _VisualTimerControls({
    required this.controller,
    required this.buttonSize,
    required this.gap,
  });

  final PomodoroController controller;
  final double buttonSize;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PomodoroState>(
      stream: controller.states,
      initialData: controller.state,
      builder: (context, snapshot) {
        final status = snapshot.data?.status ?? PomodoroStatus.idle;
        final running =
            status == PomodoroStatus.focusing ||
            status == PomodoroStatus.breaking;
        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ControlTextButton(label: '结束', onPressed: controller.end),
            SizedBox(width: gap),
            _GlassPanel(
              borderRadius: BorderRadius.circular(999),
              padding: EdgeInsets.zero,
              child: SizedBox.square(
                dimension: buttonSize,
                child: IconButton(
                  tooltip: running ? '暂停' : '开始',
                  icon: Icon(running ? Icons.pause : Icons.play_arrow),
                  onPressed: running ? controller.pause : controller.start,
                ),
              ),
            ),
            SizedBox(width: gap),
            _ControlTextButton(label: '跳过', onPressed: controller.resume),
          ],
        );
      },
    );
  }
}

class _ControlTextButton extends StatelessWidget {
  const _ControlTextButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

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

class _StudyFocusGoalCard extends StatefulWidget {
  const _StudyFocusGoalCard({
    required this.store,
    required this.date,
    this.compact = false,
  });

  final StudyStore store;
  final DateTime date;
  final bool compact;

  @override
  State<_StudyFocusGoalCard> createState() => _StudyFocusGoalCardState();
}

class _StudyFocusGoalCardState extends State<_StudyFocusGoalCard> {
  final _textController = TextEditingController();
  var _goal = const TodayGoal();
  var _record = StudyDayRecord(date: DateTime(1970));
  var _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _StudyFocusGoalCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store || oldWidget.date != widget.date) {
      _load();
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final goal = await widget.store.loadTodayGoal(widget.date);
    final record = await widget.store.loadDayRecord(widget.date);
    if (!mounted) {
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
    final target = _goal.targetPomodoros ?? 4;
    final done = _record.pomodoroCount.clamp(0, target);
    return _GlassPanel(
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
              activeColor: _studyFocusAccent,
              onChanged: (value) => _save(_goal.copyWith(completed: value)),
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
                    hintText: '完成 SDK 文档编写',
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
                  '番茄进度: $done/$target',
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

  Future<void> _save(TodayGoal goal) async {
    setState(() => _goal = goal.copyWith(completed: goal.completed));
    await widget.store.saveTodayGoal(widget.date, goal);
  }
}

class _LandscapeInfoPanel extends StatelessWidget {
  const _LandscapeInfoPanel({
    required this.members,
    required this.goal,
    required this.sound,
    required this.stats,
  });

  final Widget members;
  final Widget goal;
  final Widget sound;
  final Widget stats;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      key: const Key('study_focus_landscape_side_panel'),
      borderRadius: const BorderRadius.horizontal(left: Radius.circular(24)),
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LandscapeCompanionBar(members: members),
            const SizedBox(height: 14),
            const _SectionHeading('今日目标'),
            const SizedBox(height: 6),
            goal,
            const SizedBox(height: 14),
            const _SectionHeading('背景音'),
            const SizedBox(height: 6),
            sound,
            const SizedBox(height: 14),
            const _SectionHeading('个人统计（私密）'),
            const SizedBox(height: 6),
            stats,
          ],
        ),
      ),
    );
  }
}

class _LandscapeCompanionBar extends StatelessWidget {
  const _LandscapeCompanionBar({required this.members});

  final Widget members;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '陪伴中',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.68),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: members),
          ],
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: Colors.white.withValues(alpha: 0.42),
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _PrototypeSoundBar extends StatelessWidget {
  const _PrototypeSoundBar();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: _PrototypeSoundPill(label: '雨声', selected: true)),
        SizedBox(width: 8),
        Expanded(child: _PrototypeSoundPill(label: '白噪')),
        SizedBox(width: 8),
        Expanded(child: _PrototypeSoundPill(label: '咖啡')),
      ],
    );
  }
}

class _PrototypeSoundPill extends StatelessWidget {
  const _PrototypeSoundPill({required this.label, this.selected = false});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected
            ? _studyFocusAccent.withValues(alpha: 0.20)
            : Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: selected
                ? _studyFocusAccent
                : Colors.white.withValues(alpha: 0.68),
            fontWeight: FontWeight.w700,
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
    return FutureBuilder<StudyStats>(
      future: StudyAnalytics(store).statsFor(date),
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
                _PrototypeMetric(
                  value: _formatHours(stats.todayFocusDuration),
                  label: '今日专注',
                ),
                _PrototypeMetric(
                  value: '${stats.todayPomodoroCount}个',
                  label: '今日番茄',
                ),
                _PrototypeMetric(value: '${stats.streakDays}天', label: '连续打卡'),
              ],
            ),
            const SizedBox(height: 10),
            _PrototypeBars(days: stats.lastSevenDays),
          ],
        );
      },
    );
  }

  String _formatHours(Duration duration) {
    final hours = duration.inMinutes / 60;
    if (hours == 0) {
      return '0h';
    }
    return '${hours.toStringAsFixed(hours.truncateToDouble() == hours ? 0 : 1)}h';
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
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
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
                        ? _studyFocusAccent
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

class _PortraitDockDrawer extends StatelessWidget {
  const _PortraitDockDrawer({
    required this.activePanel,
    required this.members,
    required this.sound,
    required this.stats,
  });

  final _FocusDockPanel? activePanel;
  final Widget members;
  final Widget sound;
  final Widget stats;

  @override
  Widget build(BuildContext context) {
    if (activePanel == null) {
      return const SizedBox.shrink();
    }
    final (title, child) = switch (activePanel!) {
      _FocusDockPanel.stats => ('个人统计（私密）', stats),
      _FocusDockPanel.sound => ('背景音', sound),
      _FocusDockPanel.members => ('陪伴中', members),
    };
    return SizedBox(
      height: 220,
      child: _GlassPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            Expanded(child: SingleChildScrollView(child: child)),
          ],
        ),
      ),
    );
  }
}

class _FocusDock extends StatelessWidget {
  const _FocusDock({
    required this.immersive,
    required this.activePanel,
    required this.onChanged,
  });

  final bool immersive;
  final _FocusDockPanel? activePanel;
  final ValueChanged<_FocusDockPanel> onChanged;

  @override
  Widget build(BuildContext context) {
    final dock = _GlassPanel(
      key: const Key('study_focus_dock'),
      borderRadius: immersive
          ? const BorderRadius.vertical(top: Radius.circular(24))
          : BorderRadius.circular(999),
      padding: EdgeInsets.fromLTRB(18, 10, 18, immersive ? 24 : 10),
      child: SizedBox(
        height: 48,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _DockButton(
              icon: Icons.bar_chart,
              label: '统计',
              selected: activePanel == _FocusDockPanel.stats,
              onPressed: () => onChanged(_FocusDockPanel.stats),
            ),
            _DockButton(
              icon: Icons.music_note,
              label: '雨声',
              selected:
                  activePanel == null || activePanel == _FocusDockPanel.sound,
              onPressed: () => onChanged(_FocusDockPanel.sound),
            ),
            _DockButton(
              icon: Icons.group,
              label: '成员',
              selected: activePanel == _FocusDockPanel.members,
              onPressed: () => onChanged(_FocusDockPanel.members),
            ),
          ],
        ),
      ),
    );
    if (immersive) {
      return SizedBox(width: double.infinity, child: dock);
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 342),
      child: SizedBox(width: double.infinity, child: dock),
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: selected
              ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
              : const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: selected
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.transparent,
            border: selected
                ? Border.all(color: Colors.white.withValues(alpha: 0.12))
                : null,
            borderRadius: BorderRadius.circular(999),
          ),
          child: selected
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: _studyFocusAccent),
                    const SizedBox(width: 5),
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.72),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        height: 1,
                        color: Colors.white.withValues(alpha: 0.78),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
    this.padding = const EdgeInsets.all(14),
    super.key,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            borderRadius: borderRadius,
          ),
          child: Padding(padding: padding, child: child),
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
        _background(),
        ColoredBox(
          color: Colors.black.withValues(alpha: background.maskOpacity),
        ),
        child,
      ],
    );
  }

  Widget _background() {
    if (background.type == StudyBackgroundType.image &&
        background.image != null) {
      return Image(
        image: background.image!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return const ColoredBox(color: Color(0xFF16231E));
        },
      );
    }
    return DecoratedBox(decoration: _decoration());
  }

  BoxDecoration _decoration() {
    return switch (background.type) {
      StudyBackgroundType.color => BoxDecoration(
        color: background.color ?? const Color(0xFFF6F7F9),
      ),
      StudyBackgroundType.image => const BoxDecoration(
        color: Color(0xFF16231E),
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
          ? const SizedBox(height: 48, child: Center(child: Text('暂无陪伴')))
          : SingleChildScrollView(
              key: ValueKey(visible.map((member) => member.id).join(',')),
              scrollDirection: Axis.horizontal,
              child: Row(
                children: visible
                    .map(
                      (member) => Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: _CompanionAvatar(member: member, theme: theme),
                      ),
                    )
                    .toList(growable: false),
              ),
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
