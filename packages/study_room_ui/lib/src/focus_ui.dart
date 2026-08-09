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

enum StudyFocusDesktopSection { focus, analytics, history, settings }

typedef StudyFocusDesktopPageBuilder =
    Widget Function(
      BuildContext context,
      StudyFocusDesktopSection section,
      Widget defaultPage,
    );

typedef StudyTaskEditor =
    Future<StudyTaskRecord?> Function(
      BuildContext context,
      DateTime date,
      StudyTaskRecord? existing,
    );

class StudyBackgroundOption {
  const StudyBackgroundOption({
    required this.id,
    required this.label,
    required this.background,
  });

  final String id;
  final String label;
  final StudyBackground background;

  static const builtIns = <StudyBackgroundOption>[
    StudyBackgroundOption(
      id: 'midnight',
      label: '深夜',
      background: StudyBackground.color(Color(0xFF16231E), maskOpacity: 0.3),
    ),
    StudyBackgroundOption(
      id: 'forest',
      label: '森林',
      background: StudyBackground.gradient(
        colors: [Color(0xFF18392B), Color(0xFF101A2A)],
        maskOpacity: 0.28,
      ),
    ),
  ];
}

const studyFocusDefaultBackground = StudyBackground.gradient(
  colors: [Color(0xFF10241D), Color(0xFF17263A), Color(0xFF241B35)],
  maskOpacity: 0.2,
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
    this.localStorageNamespace = 'default',
    this.desktopSection,
    this.initialDesktopSection = StudyFocusDesktopSection.focus,
    this.onDesktopSectionChanged,
    this.desktopPageBuilder,
    this.taskEditor,
    this.backgroundOptions = StudyBackgroundOption.builtIns,
    this.onPresenceChanged,
    this.onPresenceError,
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
  final String localStorageNamespace;
  final StudyFocusDesktopSection? desktopSection;
  final StudyFocusDesktopSection initialDesktopSection;
  final ValueChanged<StudyFocusDesktopSection>? onDesktopSectionChanged;
  final StudyFocusDesktopPageBuilder? desktopPageBuilder;
  final StudyTaskEditor? taskEditor;
  final List<StudyBackgroundOption> backgroundOptions;
  final FutureOr<void> Function(PresenceStatus status)? onPresenceChanged;
  final void Function(Object error, StackTrace stackTrace)? onPresenceError;

  @override
  State<StudyFocusKitView> createState() => _StudyFocusKitViewState();
}

enum _FocusDockPanel { stats, sound, members }

class _StudyFocusKitViewState extends State<StudyFocusKitView>
    with WidgetsBindingObserver {
  StudyStore? _store;
  PomodoroController? _controller;
  StreamSubscription<StudyStoreChange>? _storeSubscription;
  StreamSubscription<PomodoroState>? _presenceSubscription;
  _StudySoundCoordinator? _sound;
  var _storeLoadGeneration = 0;
  var _dataRevision = 0;
  var _settingsWrites = 0;
  Object? _storeLoadError;
  _FocusDockPanel? _activeDockPanel;
  var _internalDesktopSection = StudyFocusDesktopSection.focus;
  var _settings = StudyFocusSettings();
  var _activeBackground = studyFocusDefaultBackground;
  String _activeBackgroundId = 'default';
  PresenceStatus? _lastPresence;
  var _lifecycleAway = false;

  DateTime get _date => widget.date ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _internalDesktopSection = widget.initialDesktopSection;
    _activeBackground = widget.background;
    _loadStore();
  }

  @override
  void didUpdateWidget(covariant StudyFocusKitView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final automaticScopeChanged =
        widget.store == null &&
        (oldWidget.currentUserId != widget.currentUserId ||
            oldWidget.localStorageNamespace != widget.localStorageNamespace);
    if (oldWidget.store != widget.store || automaticScopeChanged) {
      _loadStore();
    }
    if (oldWidget.soundPlayer != widget.soundPlayer ||
        oldWidget.soundTracks != widget.soundTracks ||
        oldWidget.background != widget.background ||
        oldWidget.backgroundOptions != widget.backgroundOptions) {
      _loadStore();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _storeSubscription?.cancel();
    _presenceSubscription?.cancel();
    _sound?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _lifecycleAway = false;
        _publishPresenceForController();
      case AppLifecycleState.inactive ||
          AppLifecycleState.hidden ||
          AppLifecycleState.paused ||
          AppLifecycleState.detached:
        _lifecycleAway = true;
        _publishPresence(PresenceStatus.away);
    }
  }

  Future<void> _loadStore() async {
    final generation = ++_storeLoadGeneration;
    _clearStoreForLoad();
    final providedStore = widget.store;
    try {
      StudyStore nextStore;
      if (providedStore != null) {
        nextStore = providedStore;
      } else {
        final preferences = await SharedPreferences.getInstance();
        final userId = widget.currentUserId.trim();
        final scope = userId.isEmpty
            ? StudyStorageScope.guest(namespace: widget.localStorageNamespace)
            : StudyStorageScope.user(
                userId: userId,
                namespace: widget.localStorageNamespace,
              );
        if (!scope.isGuest) {
          await SharedPreferencesStudyStore.migrateLegacyData(
            preferences,
            scope: scope,
          );
        }
        nextStore = SharedPreferencesStudyStore(preferences, scope: scope);
      }
      final settings = await nextStore.loadSettings();
      if (!mounted || generation != _storeLoadGeneration) {
        return;
      }
      _setStore(nextStore, settings);
    } catch (error) {
      if (mounted && generation == _storeLoadGeneration) {
        setState(() => _storeLoadError = error);
      }
    }
  }

  void _clearStoreForLoad() {
    final previousController = _controller;
    final previousSound = _sound;
    unawaited(_storeSubscription?.cancel());
    unawaited(_presenceSubscription?.cancel());
    _storeSubscription = null;
    _presenceSubscription = null;
    void clear() {
      _store = null;
      _controller = null;
      _sound = null;
      _storeLoadError = null;
    }

    if (mounted && (_store != null || _storeLoadError != null)) {
      setState(clear);
    } else {
      clear();
    }
    previousController?.dispose();
    previousSound?.dispose();
  }

  void _setStore(StudyStore store, StudyFocusSettings settings) {
    final nextController = PomodoroController(store: store);
    final nextSound = _StudySoundCoordinator(
      tracks: widget.soundTracks,
      player: widget.soundPlayer,
      settings: settings,
      onChanged: _saveSoundSettings,
      onError: _reportPresenceError,
    );
    _settings = settings;
    _internalDesktopSection = _sectionFromName(settings.desktopSection);
    _activeBackgroundId = _resolveBackgroundId(settings.backgroundId);
    _activeBackground = _backgroundForId(
      _activeBackgroundId,
    ).withMaskOpacity(settings.backgroundMaskOpacity);

    void assign() {
      _store = store;
      _controller = nextController;
      _sound = nextSound;
      _storeLoadError = null;
    }

    if (mounted) {
      setState(assign);
    } else {
      assign();
    }
    _storeSubscription = store.changes.listen(_handleStoreChange);
    _presenceSubscription = nextController.states.listen(
      (_) => _publishPresenceForController(),
      onError: (Object error, StackTrace stackTrace) {
        _reportPresenceError(error, stackTrace);
      },
    );
    _publishPresenceForController();
  }

  void _handleStoreChange(StudyStoreChange change) {
    if (!mounted) {
      return;
    }
    if (change.kind == StudyStoreChangeKind.settings) {
      if (_settingsWrites > 0) {
        setState(() => _dataRevision += 1);
        return;
      }
      unawaited(_reloadSettings());
      return;
    }
    setState(() => _dataRevision += 1);
  }

  Future<void> _reloadSettings() async {
    final store = _store;
    if (store == null) {
      return;
    }
    final settings = await store.loadSettings();
    if (!mounted || store != _store) {
      return;
    }
    setState(() {
      _settings = settings;
      if (widget.desktopSection == null) {
        _internalDesktopSection = _sectionFromName(settings.desktopSection);
      }
      _activeBackgroundId = _resolveBackgroundId(settings.backgroundId);
      _activeBackground = _backgroundForId(
        _activeBackgroundId,
      ).withMaskOpacity(settings.backgroundMaskOpacity);
      _dataRevision += 1;
    });
    _sound?.applySettings(settings);
  }

  StudyFocusDesktopSection _sectionFromName(String? name) {
    return StudyFocusDesktopSection.values.firstWhere(
      (section) => section.name == name,
      orElse: () => widget.initialDesktopSection,
    );
  }

  List<StudyBackgroundOption> get _availableBackgrounds => [
    StudyBackgroundOption(
      id: 'default',
      label: '默认',
      background: widget.background,
    ),
    ...widget.backgroundOptions.where((option) => option.id != 'default'),
  ];

  String _resolveBackgroundId(String? id) {
    return _availableBackgrounds.any((option) => option.id == id)
        ? id!
        : 'default';
  }

  StudyBackground _backgroundForId(String id) {
    return _availableBackgrounds
        .firstWhere((option) => option.id == id)
        .background;
  }

  StudyFocusDesktopSection get _desktopSection =>
      widget.desktopSection ?? _internalDesktopSection;

  void _selectDesktopSection(StudyFocusDesktopSection section) {
    widget.onDesktopSectionChanged?.call(section);
    if (widget.desktopSection != null) {
      return;
    }
    setState(() => _internalDesktopSection = section);
    unawaited(_saveSettings(_settings.copyWith(desktopSection: section.name)));
  }

  Future<void> _saveSoundSettings(String? trackId, double volume) {
    return _saveSettings(
      _settings.copyWith(soundTrackId: trackId, soundVolume: volume),
    );
  }

  Future<void> _selectBackground(String id, double maskOpacity) async {
    final resolved = _resolveBackgroundId(id);
    setState(() {
      _activeBackgroundId = resolved;
      _activeBackground = _backgroundForId(
        resolved,
      ).withMaskOpacity(maskOpacity);
    });
    await _saveSettings(
      _settings.copyWith(
        backgroundId: resolved,
        backgroundMaskOpacity: maskOpacity,
      ),
    );
  }

  Future<void> _saveSettings(StudyFocusSettings settings) async {
    final store = _store;
    if (store == null) {
      return;
    }
    _settings = settings;
    _settingsWrites += 1;
    try {
      await store.saveSettings(settings);
    } catch (error, stackTrace) {
      _reportPresenceError(error, stackTrace);
    } finally {
      _settingsWrites -= 1;
    }
  }

  void _publishPresenceForController() {
    final status = _lifecycleAway
        ? PresenceStatus.away
        : _controller?.state.status == PomodoroStatus.focusing
        ? PresenceStatus.focusing
        : PresenceStatus.idle;
    _publishPresence(status);
  }

  void _publishPresence(PresenceStatus status) {
    final callback = widget.onPresenceChanged;
    if (callback == null || _lastPresence == status) {
      return;
    }
    _lastPresence = status;
    Future<void>.sync(() => callback(status)).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      _reportPresenceError(error, stackTrace);
    });
  }

  void _reportPresenceError(Object error, StackTrace stackTrace) {
    widget.onPresenceError?.call(error, stackTrace);
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    final controller = _controller;
    final members = widget.room?.members ?? const <StudyMember>[];
    return StudyBackgroundLayer(
      background: _activeBackground,
      child: Theme(
        data: _visualTheme(context),
        child: Material(
          type: MaterialType.transparency,
          child: SafeArea(
            bottom: widget.visualStyle != StudyFocusVisualStyle.immersiveDock,
            child: _storeLoadError != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('无法加载本地学习数据'),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _loadStore,
                          icon: const Icon(Icons.refresh),
                          label: const Text('重试'),
                        ),
                      ],
                    ),
                  )
                : store == null || controller == null
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
                      final sound = _StudySoundControls(coordinator: _sound!);
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
                          section: _desktopSection,
                          onSectionChanged: _selectDesktopSection,
                          pageBuilder: widget.desktopPageBuilder,
                          taskEditor: widget.taskEditor,
                          sound: _sound!,
                          backgrounds: _availableBackgrounds,
                          activeBackgroundId: _activeBackgroundId,
                          maskOpacity: _activeBackground.maskOpacity,
                          onBackgroundChanged: _selectBackground,
                          dataRevision: _dataRevision,
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
                          sound: sound,
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
                        background: _activeBackground,
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
    required this.sound,
    super.key,
  });

  final PomodoroController controller;
  final StudyStore store;
  final DateTime date;
  final _StudyFocusSizing sizing;
  final Widget members;
  final Widget sound;

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
            sound: sound,
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
    required this.section,
    required this.onSectionChanged,
    required this.pageBuilder,
    required this.taskEditor,
    required this.sound,
    required this.backgrounds,
    required this.activeBackgroundId,
    required this.maskOpacity,
    required this.onBackgroundChanged,
    required this.dataRevision,
    super.key,
  });

  final PomodoroController controller;
  final StudyStore store;
  final DateTime date;
  final _StudyFocusSizing sizing;
  final Widget members;
  final int onlineCount;
  final StudyFocusDesktopSection section;
  final ValueChanged<StudyFocusDesktopSection> onSectionChanged;
  final StudyFocusDesktopPageBuilder? pageBuilder;
  final StudyTaskEditor? taskEditor;
  final _StudySoundCoordinator sound;
  final List<StudyBackgroundOption> backgrounds;
  final String activeBackgroundId;
  final double maskOpacity;
  final Future<void> Function(String id, double maskOpacity)
  onBackgroundChanged;
  final int dataRevision;

  @override
  Widget build(BuildContext context) {
    final defaultPage = switch (section) {
      StudyFocusDesktopSection.focus => _focusPage(),
      StudyFocusDesktopSection.analytics => _DesktopAnalyticsPage(
        key: ValueKey('desktop-analytics-$dataRevision'),
        store: store,
        date: date,
      ),
      StudyFocusDesktopSection.history => _DesktopHistoryPage(
        store: store,
        date: date,
        taskEditor: taskEditor,
      ),
      StudyFocusDesktopSection.settings => _DesktopSettingsPage(
        sound: sound,
        backgrounds: backgrounds,
        activeBackgroundId: activeBackgroundId,
        maskOpacity: maskOpacity,
        onBackgroundChanged: onBackgroundChanged,
      ),
    };
    final page =
        pageBuilder?.call(context, section, defaultPage) ?? defaultPage;
    return Column(
      key: const Key('study_focus_desktop_shell'),
      children: [
        _DesktopTopNav(
          section: section,
          onSectionChanged: onSectionChanged,
          onNewTask: () => _editStudyTask(
            context,
            store: store,
            date: date,
            editor: taskEditor,
          ),
        ),
        Expanded(child: page),
      ],
    );
  }

  Widget _focusPage() {
    return Row(
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
                    controller: controller,
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
            sound: sound,
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
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

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
              _DesktopNavItem(
                '专注',
                selected: widget.section == StudyFocusDesktopSection.focus,
                onPressed: () =>
                    widget.onSectionChanged(StudyFocusDesktopSection.focus),
              ),
              _DesktopNavItem(
                '数据统计',
                selected: widget.section == StudyFocusDesktopSection.analytics,
                onPressed: () =>
                    widget.onSectionChanged(StudyFocusDesktopSection.analytics),
              ),
              _DesktopNavItem(
                '历史记录',
                selected: widget.section == StudyFocusDesktopSection.history,
                onPressed: () =>
                    widget.onSectionChanged(StudyFocusDesktopSection.history),
              ),
              _DesktopNavItem(
                '设置',
                selected: widget.section == StudyFocusDesktopSection.settings,
                onPressed: () =>
                    widget.onSectionChanged(StudyFocusDesktopSection.settings),
              ),
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
                onPressed: widget.onNewTask,
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
          Center(child: _DesktopPresetBar(controller: controller)),
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
  const _DesktopPresetBar({required this.controller});

  final PomodoroController controller;

  @override
  Widget build(BuildContext context) {
    return _PresetBar(controller: controller, verbose: true);
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
        final paused = status == PomodoroStatus.paused;
        final active = running || paused;
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
                  tooltip: running
                      ? '暂停'
                      : paused
                      ? '继续'
                      : '开始',
                  icon: Icon(
                    running ? Icons.pause : Icons.play_arrow,
                    size: 30,
                  ),
                  onPressed: running
                      ? controller.pause
                      : paused
                      ? controller.resume
                      : controller.start,
                ),
              ),
            ),
            const SizedBox(width: 28),
            _ControlTextButton(
              label: '跳至休息',
              onPressed: active ? controller.skip : null,
            ),
          ],
        );
      },
    );
  }
}

class _StudyFocusDesktopGoalCard extends StatefulWidget {
  const _StudyFocusDesktopGoalCard({
    required this.store,
    required this.date,
    required this.controller,
  });

  final StudyStore store;
  final DateTime date;
  final PomodoroController controller;

  @override
  State<_StudyFocusDesktopGoalCard> createState() =>
      _StudyFocusDesktopGoalCardState();
}

class _StudyFocusDesktopGoalCardState
    extends State<_StudyFocusDesktopGoalCard> {
  late Future<(TodayGoal, StudyDayRecord)> _future;
  StreamSubscription<StudyStoreChange>? _subscription;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant _StudyFocusDesktopGoalCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store || oldWidget.date != widget.date) {
      unawaited(_subscription?.cancel());
      _future = _load();
      _subscribe();
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _subscribe() {
    _subscription = widget.store.changes.listen((change) {
      if (!mounted ||
          (change.kind != StudyStoreChangeKind.goal &&
              change.kind != StudyStoreChangeKind.dayRecord) ||
          (change.date != null &&
              _dateKey(change.date!) != _dateKey(widget.date))) {
        return;
      }
      setState(() {
        _future = _load();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PomodoroState>(
      stream: widget.controller.states,
      initialData: widget.controller.state,
      builder: (context, _) => FutureBuilder<(TodayGoal, StudyDayRecord)>(
        future: _future,
        builder: (context, snapshot) {
          final goal = snapshot.data?.$1 ?? const TodayGoal();
          final record = snapshot.data?.$2 ?? StudyDayRecord(date: widget.date);
          final target = goal.targetPomodoros ?? 4;
          final done = record.pomodoroCount.clamp(0, target);
          final focusMinutes = math.max(
            1,
            widget.controller.config.focusDuration.inMinutes,
          );
          final remaining = math.max(0, target - done) * focusMinutes;
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
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.56),
                    ),
                    activeColor: _studyFocusAccent,
                    onChanged: (value) =>
                        _toggleCompleted(goal, record, value ?? false),
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
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '番茄进度: $done/$target | 预计还需 $remaining 分钟',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
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
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
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
      ),
    );
  }

  Future<(TodayGoal, StudyDayRecord)> _load() async {
    final goal = await widget.store.loadTodayGoal(widget.date);
    final record = await widget.store.loadDayRecord(widget.date);
    return (goal, record);
  }

  Future<void> _toggleCompleted(
    TodayGoal goal,
    StudyDayRecord record,
    bool completed,
  ) async {
    final next = goal.copyWith(completed: completed);
    setState(() => _future = Future.value((next, record)));
    try {
      await widget.store.saveTodayGoal(widget.date, next);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _future = Future.value((goal, record)));
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('目标保存失败')));
    }
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('数据统计', style: Theme.of(context).textTheme.headlineSmall),
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
  const _DesktopHistoryPage({
    required this.store,
    required this.date,
    required this.taskEditor,
  });

  final StudyStore store;
  final DateTime date;
  final StudyTaskEditor? taskEditor;

  @override
  State<_DesktopHistoryPage> createState() => _DesktopHistoryPageState();
}

class _DesktopHistoryPageState extends State<_DesktopHistoryPage> {
  late DateTime _selectedDate = _dateOnly(widget.date);
  late Future<(List<StudyDayRecord>, List<StudyTaskRecord>)> _future = _load();
  StreamSubscription<StudyStoreChange>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.store.changes.listen((change) {
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

  @override
  void didUpdateWidget(covariant _DesktopHistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      unawaited(_subscription?.cancel());
      _subscription = widget.store.changes.listen((_) {
        if (mounted) {
          setState(() {
            _future = _load();
          });
        }
      });
    }
    if (oldWidget.date != widget.date) {
      _selectedDate = _dateOnly(widget.date);
    }
    if (oldWidget.store != widget.store || oldWidget.date != widget.date) {
      _future = _load();
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  Future<(List<StudyDayRecord>, List<StudyTaskRecord>)> _load() async {
    final end = _dateOnly(widget.date);
    final records = await widget.store.loadDayRecords(
      start: end.subtract(const Duration(days: 29)),
      end: end,
    );
    final tasks = await widget.store.loadTaskRecords(_selectedDate);
    return (records.reversed.toList(growable: false), tasks);
  }

  @override
  Widget build(BuildContext context) {
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
                          _dateKey(record.date) == _dateKey(_selectedDate);
                      return ListTile(
                        selected: selected,
                        title: Text(_dateKey(record.date)),
                        subtitle: Text(
                          '${record.focusDuration.inMinutes} 分钟 · ${record.pomodoroCount} 个番茄',
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
                              '${_dateKey(_selectedDate)} 的任务',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: () => _editStudyTask(
                              context,
                              store: widget.store,
                              date: _selectedDate,
                              editor: widget.taskEditor,
                            ),
                            icon: const Icon(Icons.add),
                            label: const Text('新建任务'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: tasks.isEmpty
                            ? const Center(child: Text('暂无任务'))
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
                                              tooltip: '编辑',
                                              onPressed: () => _editStudyTask(
                                                context,
                                                store: widget.store,
                                                date: _selectedDate,
                                                existing: task,
                                                editor: widget.taskEditor,
                                              ),
                                              icon: const Icon(Icons.edit),
                                            ),
                                            IconButton(
                                              tooltip: '删除',
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除任务'),
        content: Text('确定删除“${task.title}”吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await widget.store.deleteTaskRecord(_selectedDate, task.id);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.maybeOf(
            context,
          )?.showSnackBar(const SnackBar(content: Text('任务删除失败')));
        }
      }
    }
  }

  Future<void> _saveTask(StudyTaskRecord task) async {
    try {
      await widget.store.saveTaskRecord(_selectedDate, task);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(const SnackBar(content: Text('任务保存失败')));
      }
    }
  }
}

class _DesktopSettingsPage extends StatefulWidget {
  const _DesktopSettingsPage({
    required this.sound,
    required this.backgrounds,
    required this.activeBackgroundId,
    required this.maskOpacity,
    required this.onBackgroundChanged,
  });

  final _StudySoundCoordinator sound;
  final List<StudyBackgroundOption> backgrounds;
  final String activeBackgroundId;
  final double maskOpacity;
  final Future<void> Function(String id, double maskOpacity)
  onBackgroundChanged;

  @override
  State<_DesktopSettingsPage> createState() => _DesktopSettingsPageState();
}

class _DesktopSettingsPageState extends State<_DesktopSettingsPage> {
  late double _maskOpacity = widget.maskOpacity;

  @override
  void didUpdateWidget(covariant _DesktopSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.maskOpacity != widget.maskOpacity) {
      _maskOpacity = widget.maskOpacity;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('设置', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 20),
          _DesktopPanelCard(
            child: _StudySoundControls(coordinator: widget.sound),
          ),
          const SizedBox(height: 20),
          _DesktopPanelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('背景', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: widget.backgrounds
                      .map(
                        (option) => ChoiceChip(
                          label: Text(option.label),
                          selected: option.id == widget.activeBackgroundId,
                          onSelected: (_) => widget.onBackgroundChanged(
                            option.id,
                            _maskOpacity,
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
                const SizedBox(height: 18),
                Text('遮罩 ${(100 * _maskOpacity).round()}%'),
                Slider(
                  key: const Key('desktop_background_mask'),
                  value: _maskOpacity,
                  max: 0.85,
                  onChanged: (value) => setState(() => _maskOpacity = value),
                  onChangeEnd: (value) => widget.onBackgroundChanged(
                    widget.activeBackgroundId,
                    value,
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

var _taskSequence = 0;

Future<void> _editStudyTask(
  BuildContext context, {
  required StudyStore store,
  required DateTime date,
  StudyTaskRecord? existing,
  StudyTaskEditor? editor,
}) async {
  final task = editor == null
      ? await showDialog<StudyTaskRecord>(
          context: context,
          builder: (context) => _StudyTaskDialog(existing: existing),
        )
      : await editor(context, date, existing);
  if (task != null) {
    try {
      await store.saveTaskRecord(date, task);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(const SnackBar(content: Text('任务保存失败')));
      }
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
    return AlertDialog(
      title: Text(widget.existing == null ? '新建任务' : '编辑任务'),
      content: TextField(
        key: const Key('study_task_title'),
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: '任务名称', errorText: _error),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }

  void _save() {
    final title = _controller.text.trim();
    if (title.isEmpty) {
      setState(() => _error = '任务名称不能为空');
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
    required this.sound,
  });

  final Widget members;
  final int onlineCount;
  final Widget stats;
  final _StudySoundCoordinator sound;

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
            _DesktopSoundGrid(coordinator: sound),
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
  const _DesktopSoundGrid({required this.coordinator});

  final _StudySoundCoordinator coordinator;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: coordinator,
      builder: (context, _) => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: coordinator.tracks
            .map(
              (track) => SizedBox(
                width: 96,
                child: _DesktopSoundTile(
                  icon: _soundIcon(track.id),
                  label: track.label,
                  selected: coordinator.selected?.id == track.id,
                  playing:
                      coordinator.playing &&
                      coordinator.selected?.id == track.id,
                  onPressed: () => coordinator.toggle(track),
                ),
              ),
            )
            .toList(growable: false),
      ),
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
    required this.selected,
    required this.playing,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool playing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('desktop_sound_$label'),
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: selected ? 0.16 : 0.06),
          border: Border.all(
            color: selected
                ? _studyFocusAccent
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
                color: _studyFocusAccent,
              ),
              const SizedBox(height: 8),
              Text(
                label,
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
          Center(child: _PresetBar(controller: controller)),
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
  const _PresetBar({required this.controller, this.verbose = false});

  final PomodoroController controller;
  final bool verbose;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PomodoroState>(
      stream: controller.states,
      initialData: controller.state,
      builder: (context, snapshot) {
        final status = snapshot.data?.status ?? controller.state.status;
        final enabled =
            status == PomodoroStatus.idle || status == PomodoroStatus.finished;
        final preset = controller.config.preset;
        return _GlassPanel(
          borderRadius: BorderRadius.circular(999),
          padding: const EdgeInsets.all(4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PresetChip(
                label: verbose ? '25 / 5 分钟' : '25/5',
                selected: preset == PomodoroPreset.twentyFiveFive,
                onPressed: enabled
                    ? () => controller.setConfig(PomodoroConfig())
                    : null,
              ),
              _PresetChip(
                label: verbose ? '50 / 10 分钟' : '50/10',
                selected: preset == PomodoroPreset.fiftyTen,
                onPressed: enabled
                    ? () => controller.setConfig(PomodoroConfig.fiftyTen())
                    : null,
              ),
              _PresetChip(
                label: verbose ? '自定义时长' : '自定义',
                selected: preset == PomodoroPreset.custom,
                onPressed: enabled
                    ? () => _showCustomPomodoroDialog(context, controller)
                    : null,
              ),
            ],
          ),
        );
      },
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
  BuildContext context,
  PomodoroController controller,
) async {
  final config = await showDialog<PomodoroConfig>(
    context: context,
    builder: (context) =>
        _CustomPomodoroDialog(initialConfig: controller.config),
  );
  if (config != null) {
    controller.setConfig(config);
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
    return AlertDialog(
      title: const Text('自定义时长'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('pomodoro_custom_focus'),
            controller: _focusController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '专注分钟'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('pomodoro_custom_break'),
            controller: _breakController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '休息分钟'),
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
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _apply, child: const Text('应用')),
      ],
    );
  }

  void _apply() {
    final focus = int.tryParse(_focusController.text.trim());
    final rest = int.tryParse(_breakController.text.trim());
    if (focus == null || focus <= 0 || rest == null || rest < 0) {
      setState(() {
        _validationError = '专注时长须大于 0，休息时长不能为负数';
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
  Object? _error;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(covariant _VisualPomodoroTimer oldWidget) {
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
                    _error == null ? _statusLabel(_state.status) : '保存失败',
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
        final paused = status == PomodoroStatus.paused;
        final active = running || paused;
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
                  tooltip: running
                      ? '暂停'
                      : paused
                      ? '继续'
                      : '开始',
                  icon: Icon(running ? Icons.pause : Icons.play_arrow),
                  onPressed: running
                      ? controller.pause
                      : paused
                      ? controller.resume
                      : controller.start,
                ),
              ),
            ),
            SizedBox(width: gap),
            _ControlTextButton(
              label: '跳过',
              onPressed: active ? controller.skip : null,
            ),
          ],
        );
      },
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
  void didUpdateWidget(covariant _StudyFocusGoalCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store || oldWidget.date != widget.date) {
      unawaited(_subscription?.cancel());
      _subscribe();
      _load();
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _textController.dispose();
    super.dispose();
  }

  void _subscribe() {
    _subscription = widget.store.changes.listen((change) {
      if (!mounted ||
          (change.kind != StudyStoreChangeKind.goal &&
              change.kind != StudyStoreChangeKind.dayRecord) ||
          (change.date != null &&
              _dateKey(change.date!) != _dateKey(widget.date))) {
        return;
      }
      unawaited(_load());
    });
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final goal = await widget.store.loadTodayGoal(widget.date);
    final record = await widget.store.loadDayRecord(widget.date);
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
    final previous = _goal;
    final generation = ++_saveGeneration;
    setState(() => _goal = goal);
    try {
      await widget.store.saveTodayGoal(widget.date, goal);
    } catch (_) {
      if (!mounted || generation != _saveGeneration) {
        return;
      }
      setState(() => _goal = previous);
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('目标保存失败')));
    }
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

class _PrototypeStatsOverview extends StatelessWidget {
  const _PrototypeStatsOverview({required this.store, required this.date});

  final StudyStore store;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return _ReactiveStudyStoreBuilder<StudyStats>(
      store: store,
      dependency: _dateKey(date),
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
          if (_error != null) const Text('Unable to save focus session'),
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
              _dateKey(change.date!) != _dateKey(widget.date))) {
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
            onChanged: (_) => unawaited(_save()),
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
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(const SnackBar(content: Text('目标保存失败')));
      }
    }
  }
}

class StudyStatsView extends StatelessWidget {
  const StudyStatsView({required this.store, required this.date, super.key});

  final StudyStore store;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return _ReactiveStudyStoreBuilder<StudyStats>(
      store: store,
      dependency: _dateKey(date),
      changeKinds: const {StudyStoreChangeKind.dayRecord},
      load: () => StudyAnalytics(store).statsFor(date),
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
    return _ReactiveStudyStoreBuilder<StudyStats>(
      store: store,
      dependency: _dateKey(date),
      changeKinds: const {StudyStoreChangeKind.dayRecord},
      load: () => StudyAnalytics(store).statsFor(date),
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
    return _ReactiveStudyStoreBuilder<StudyReport>(
      store: store,
      dependency: '${range.name}:${_dateKey(date)}',
      changeKinds: const {
        StudyStoreChangeKind.dayRecord,
        StudyStoreChangeKind.tasks,
      },
      load: () => StudyAnalytics(store).report(range, date),
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

class _ReactiveStudyStoreBuilder<T> extends StatefulWidget {
  const _ReactiveStudyStoreBuilder({
    required this.store,
    required this.dependency,
    required this.changeKinds,
    required this.load,
    required this.builder,
  });

  final StudyStore store;
  final Object dependency;
  final Set<StudyStoreChangeKind> changeKinds;
  final Future<T> Function() load;
  final AsyncWidgetBuilder<T> builder;

  @override
  State<_ReactiveStudyStoreBuilder<T>> createState() =>
      _ReactiveStudyStoreBuilderState<T>();
}

class _ReactiveStudyStoreBuilderState<T>
    extends State<_ReactiveStudyStoreBuilder<T>> {
  StreamSubscription<StudyStoreChange>? _subscription;
  AsyncSnapshot<T> _snapshot = const AsyncSnapshot.waiting();
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    _subscribe();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant _ReactiveStudyStoreBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      unawaited(_subscription?.cancel());
      _subscribe();
    }
    if (oldWidget.store != widget.store ||
        oldWidget.dependency != widget.dependency) {
      unawaited(_load(clear: true));
    }
  }

  @override
  void dispose() {
    ++_generation;
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _subscribe() {
    _subscription = widget.store.changes.listen((change) {
      if (mounted && widget.changeKinds.contains(change.kind)) {
        unawaited(_load());
      }
    });
  }

  Future<void> _load({bool clear = false}) async {
    final generation = ++_generation;
    if (clear && mounted) {
      setState(() => _snapshot = const AsyncSnapshot.waiting());
    }
    try {
      final value = await widget.load();
      if (!mounted || generation != _generation) {
        return;
      }
      setState(
        () => _snapshot = AsyncSnapshot.withData(ConnectionState.done, value),
      );
    } catch (error, stackTrace) {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(
        () => _snapshot = AsyncSnapshot.withError(
          ConnectionState.done,
          error,
          stackTrace,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _snapshot);
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
    unawaited(_player.play());
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> setVolume(double volume) =>
      _player.setVolume(volume.clamp(0.0, 1.0));

  @override
  Future<void> dispose() => _player.dispose();
}

class _StudySoundCoordinator extends ChangeNotifier {
  _StudySoundCoordinator({
    required this.tracks,
    required StudySoundPlayer? player,
    required StudyFocusSettings settings,
    required this.onChanged,
    required this.onError,
  }) : _ownsPlayer = player == null,
       _player = player ?? JustAudioStudySoundPlayer(),
       _volume = settings.soundVolume {
    _selected = _trackForId(settings.soundTrackId);
  }

  final List<StudySoundTrack> tracks;
  final StudySoundPlayer _player;
  final bool _ownsPlayer;
  final Future<void> Function(String? trackId, double volume) onChanged;
  final void Function(Object error, StackTrace stackTrace) onError;

  StudySoundTrack? _selected;
  bool _playing = false;
  double _volume;

  StudySoundTrack? get selected => _selected;
  bool get playing => _playing;
  double get volume => _volume;

  Future<void> toggle(StudySoundTrack track) async {
    try {
      if (_playing && _selected?.id == track.id) {
        await _player.pause();
        _playing = false;
      } else {
        await _player.play(track, volume: _volume);
        _selected = track;
        _playing = true;
        await onChanged(_selected?.id, _volume);
      }
      notifyListeners();
    } catch (error, stackTrace) {
      onError(error, stackTrace);
    }
  }

  Future<void> pause() async {
    if (!_playing) {
      return;
    }
    try {
      await _player.pause();
      _playing = false;
      notifyListeners();
    } catch (error, stackTrace) {
      onError(error, stackTrace);
    }
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0).toDouble();
    notifyListeners();
    try {
      await _player.setVolume(_volume);
      await onChanged(_selected?.id, _volume);
    } catch (error, stackTrace) {
      onError(error, stackTrace);
    }
  }

  void applySettings(StudyFocusSettings settings) {
    _selected = _trackForId(settings.soundTrackId);
    _volume = settings.soundVolume;
    _playing = false;
    notifyListeners();
  }

  StudySoundTrack? _trackForId(String? id) {
    if (tracks.isEmpty) {
      return null;
    }
    return tracks.firstWhere(
      (track) => track.id == id,
      orElse: () => tracks.first,
    );
  }

  @override
  void dispose() {
    if (_ownsPlayer) {
      unawaited(_player.dispose());
    }
    super.dispose();
  }
}

class _StudySoundControls extends StatelessWidget {
  const _StudySoundControls({required this.coordinator});

  final _StudySoundCoordinator coordinator;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: coordinator,
      builder: (context, _) {
        return Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: coordinator.tracks
                    .map(
                      (track) => ChoiceChip(
                        label: Text(track.label),
                        selected: coordinator.selected?.id == track.id,
                        onSelected: (_) => coordinator.toggle(track),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton.filled(
                    tooltip: coordinator.playing ? 'Pause' : 'Play',
                    icon: Icon(
                      coordinator.playing ? Icons.pause : Icons.play_arrow,
                    ),
                    onPressed: coordinator.selected == null
                        ? null
                        : () => coordinator.toggle(coordinator.selected!),
                  ),
                  Expanded(
                    child: Slider(
                      value: coordinator.volume,
                      onChanged: coordinator.setVolume,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
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

  StudyBackground withMaskOpacity(double maskOpacity) {
    return StudyBackground._(
      type: type,
      color: color,
      image: image,
      gradientColors: gradientColors,
      maskOpacity: maskOpacity,
    );
  }
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
