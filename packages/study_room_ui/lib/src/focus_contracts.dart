import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:study_room_sdk/study_room_sdk.dart';

import 'audio.dart';
import 'backgrounds.dart';
import 'focus_api.dart';

/// Package-internal lifecycle state shared by the focus coordinator and the
/// independent layout libraries. This type is intentionally not exported from
/// `study_room_ui.dart`.
enum StudyFocusLoadPhase { loading, ready, failed }

/// Package-internal dock selection shared across independent layout libraries.
enum StudyFocusDockPanel { stats, sound, members }

@immutable
class StudyFocusShellModel {
  StudyFocusShellModel({
    required this.loadPhase,
    required this.visualStyle,
    required this.desktopSection,
    required this.background,
    required List<StudyBackgroundOption> backgrounds,
    required this.activeBackgroundId,
    required this.activeBackgroundMaskOpacity,
    this.activeDockPanel,
    this.loadError,
  }) : backgrounds = List.unmodifiable(backgrounds);

  final StudyFocusLoadPhase loadPhase;
  final StudyFocusVisualStyle visualStyle;
  final StudyFocusDesktopSection desktopSection;
  final StudyFocusDockPanel? activeDockPanel;
  final StudyBackground background;
  final List<StudyBackgroundOption> backgrounds;
  final String activeBackgroundId;
  final double activeBackgroundMaskOpacity;
  final Object? loadError;
}

@immutable
class StudyFocusDataModel {
  StudyFocusDataModel({
    required this.store,
    required this.date,
    required this.timerState,
    required this.timerConfig,
    required List<StudyMember> members,
    required this.currentUserId,
    required this.showCompanions,
    required this.dataRevision,
    this.timerError,
  }) : members = List.unmodifiable(members);

  final StudyStore store;
  final DateTime date;
  final PomodoroState timerState;
  final PomodoroConfig timerConfig;
  final List<StudyMember> members;
  final String currentUserId;
  final bool showCompanions;
  final int dataRevision;
  final Object? timerError;
}

@immutable
class StudyFocusSoundModel {
  StudyFocusSoundModel({
    required List<StudySoundTrack> tracks,
    required this.selectedTrackId,
    required this.playing,
    required this.volume,
  }) : tracks = List.unmodifiable(tracks);

  final List<StudySoundTrack> tracks;
  final String? selectedTrackId;
  final bool playing;
  final double volume;
}

@immutable
class StudyFocusLayoutModel {
  const StudyFocusLayoutModel({
    required this.shell,
    required this.data,
    required this.sound,
  });

  final StudyFocusShellModel shell;
  final StudyFocusDataModel data;
  final StudyFocusSoundModel sound;
}

/// Mutations exposed by the coordinator to otherwise declarative layouts.
///
/// Keeping this callback surface separate from [StudyFocusLayoutModel] lets
/// layout libraries remain free of store, audio-player, and lifecycle ownership.
@immutable
class StudyFocusActions {
  const StudyFocusActions({
    required this.retryLoad,
    required this.selectDesktopSection,
    required this.toggleDockPanel,
    required this.selectBackground,
    required this.startTimer,
    required this.pauseTimer,
    required this.resumeTimer,
    required this.skipTimer,
    required this.endTimer,
    required this.setTimerConfig,
    required this.toggleSound,
    required this.pauseSound,
    required this.setSoundVolume,
    required this.saveTodayGoal,
    required this.saveTask,
    required this.deleteTask,
    this.desktopPageBuilder,
    this.taskEditor,
  });

  final VoidCallback retryLoad;
  final ValueChanged<StudyFocusDesktopSection> selectDesktopSection;
  final ValueChanged<StudyFocusDockPanel> toggleDockPanel;
  final Future<void> Function(String id, double maskOpacity) selectBackground;
  final VoidCallback startTimer;
  final VoidCallback pauseTimer;
  final VoidCallback resumeTimer;
  final VoidCallback skipTimer;
  final VoidCallback endTimer;
  final ValueChanged<PomodoroConfig> setTimerConfig;
  final Future<void> Function(StudySoundTrack track) toggleSound;
  final Future<void> Function() pauseSound;
  final Future<void> Function(double volume) setSoundVolume;
  final Future<void> Function(DateTime date, TodayGoal goal) saveTodayGoal;
  final Future<void> Function(DateTime date, StudyTaskRecord task) saveTask;
  final Future<void> Function(DateTime date, String taskId) deleteTask;
  final StudyFocusDesktopPageBuilder? desktopPageBuilder;
  final StudyTaskEditor? taskEditor;
}
