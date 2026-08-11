library study_room_ui;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_room_sdk/study_room_sdk.dart';

import 'audio.dart';
import 'backgrounds.dart';
import 'focus_api.dart';
import 'focus_contracts.dart';
import 'focus_primitives.dart';
import 'focus_responsive_layout.dart';
import 'focus_sound_coordinator.dart';
import 'localizations.dart';
import 'persistence.dart';

export 'focus_api.dart'
    show
        StudyFocusDesktopPageBuilder,
        StudyFocusDesktopSection,
        StudyFocusVisualStyle,
        StudyTaskEditor;
export 'standalone_focus_views.dart' show PomodoroTimerView, TodayGoalView;

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

class _StudyFocusKitViewState extends State<StudyFocusKitView>
    with WidgetsBindingObserver {
  StudyStore? _store;
  PomodoroController? _controller;
  Stream<PomodoroState>? _timerStates;
  StreamSubscription<StudyStoreChange>? _storeSubscription;
  StreamSubscription<PomodoroState>? _presenceSubscription;
  StudySoundCoordinator? _sound;
  var _storeLoadGeneration = 0;
  var _dataRevision = 0;
  var _settingsWrites = 0;
  Object? _storeLoadError;
  StudyFocusDockPanel? _activeDockPanel;
  var _internalDesktopSection = StudyFocusDesktopSection.focus;
  var _settings = StudyFocusSettings();
  var _activeBackground = studyFocusDefaultBackground;
  String _activeBackgroundId = 'default';
  PresenceStatus? _lastPresence;
  var _lifecycleAway = false;
  late DateTime _automaticDate;

  DateTime get _date {
    final explicit = widget.date;
    if (explicit != null) return explicit;
    final now = DateTime.now();
    if (now.year != _automaticDate.year ||
        now.month != _automaticDate.month ||
        now.day != _automaticDate.day) {
      _automaticDate = now;
    }
    return _automaticDate;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _automaticDate = DateTime.now();
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
      if (!mounted || generation != _storeLoadGeneration) return;
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
      _timerStates = null;
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
    final nextSound = StudySoundCoordinator(
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
      _timerStates = nextController.states;
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
      onError: _reportPresenceError,
    );
    _publishPresenceForController();
  }

  void _handleStoreChange(StudyStoreChange change) {
    if (!mounted) return;
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
    if (store == null) return;
    final settings = await store.loadSettings();
    if (!mounted || store != _store) return;
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
      label: 'default',
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
    if (widget.desktopSection != null) return;
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
    if (store == null) return;
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

  void _toggleDockPanel(StudyFocusDockPanel panel) {
    setState(() {
      _activeDockPanel = _activeDockPanel == panel ? null : panel;
    });
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
    if (callback == null || _lastPresence == status) return;
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
    final localizations = studyRoomLocalizationsOf(context);
    final store = _store;
    final controller = _controller;
    final timerStates = _timerStates;
    final sound = _sound;
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
                        Text(localizations.localDataLoadFailed),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _loadStore,
                          icon: const Icon(Icons.refresh),
                          label: Text(localizations.retry),
                        ),
                      ],
                    ),
                  )
                : store == null ||
                      controller == null ||
                      timerStates == null ||
                      sound == null
                ? const Center(child: CircularProgressIndicator())
                : StreamBuilder<PomodoroState>(
                    stream: timerStates,
                    initialData: controller.state,
                    builder: (context, timerSnapshot) {
                      return ListenableBuilder(
                        listenable: sound,
                        builder: (context, _) {
                          final model = _layoutModel(
                            store: store,
                            controller: controller,
                            sound: sound,
                            timerState: timerSnapshot.data ?? controller.state,
                            timerError: timerSnapshot.error,
                          );
                          return StudyFocusResponsiveLayout(
                            model: model,
                            actions: _layoutActions(
                              store: store,
                              controller: controller,
                              sound: sound,
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }

  StudyFocusLayoutModel _layoutModel({
    required StudyStore store,
    required PomodoroController controller,
    required StudySoundCoordinator sound,
    required PomodoroState timerState,
    required Object? timerError,
  }) {
    return StudyFocusLayoutModel(
      shell: StudyFocusShellModel(
        loadPhase: StudyFocusLoadPhase.ready,
        visualStyle: widget.visualStyle,
        desktopSection: _desktopSection,
        activeDockPanel: _activeDockPanel,
        background: _activeBackground,
        backgrounds: _availableBackgrounds,
        activeBackgroundId: _activeBackgroundId,
        activeBackgroundMaskOpacity: _activeBackground.maskOpacity,
      ),
      data: StudyFocusDataModel(
        store: store,
        date: _date,
        timerState: timerState,
        timerConfig: controller.config,
        timerError: timerError,
        members: widget.room?.members ?? const <StudyMember>[],
        currentUserId: widget.currentUserId,
        showCompanions: widget.showCompanions,
        dataRevision: _dataRevision,
      ),
      sound: StudyFocusSoundModel(
        tracks: sound.tracks,
        selectedTrackId: sound.selected?.id,
        playing: sound.playing,
        volume: sound.volume,
      ),
    );
  }

  StudyFocusActions _layoutActions({
    required StudyStore store,
    required PomodoroController controller,
    required StudySoundCoordinator sound,
  }) {
    return StudyFocusActions(
      retryLoad: _loadStore,
      selectDesktopSection: _selectDesktopSection,
      toggleDockPanel: _toggleDockPanel,
      selectBackground: _selectBackground,
      startTimer: controller.start,
      pauseTimer: controller.pause,
      resumeTimer: controller.resume,
      skipTimer: controller.skip,
      endTimer: controller.end,
      setTimerConfig: controller.setConfig,
      toggleSound: sound.toggle,
      pauseSound: sound.pause,
      setSoundVolume: sound.setVolume,
      saveTodayGoal: store.saveTodayGoal,
      saveTask: store.saveTaskRecord,
      deleteTask: store.deleteTaskRecord,
      desktopPageBuilder: widget.desktopPageBuilder,
      taskEditor: widget.taskEditor,
    );
  }

  ThemeData _visualTheme(BuildContext context) {
    final base = Theme.of(context);
    final scheme = ColorScheme.fromSeed(
      seedColor: studyFocusAccent,
      brightness: Brightness.dark,
      primary: studyFocusAccent,
      secondary: studyFocusRest,
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
