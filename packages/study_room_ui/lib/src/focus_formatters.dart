import 'package:study_room_sdk/study_room_sdk.dart';

import 'audio.dart';
import 'backgrounds.dart';
import 'localizations.dart';

String localizedSoundTrackLabel(
  StudySoundTrack track,
  StudyRoomLocalizations localizations,
) {
  final builtIn = StudySoundTrack.builtIns.any(
    (candidate) => identical(candidate, track),
  );
  if (!builtIn) return track.label;
  return switch (track.id) {
    'rain' => localizations.soundRain,
    'white_noise' => localizations.soundWhiteNoise,
    'cafe' => localizations.soundCafe,
    'library' => localizations.soundLibrary,
    'keyboard' => localizations.soundKeyboard,
    _ => track.label,
  };
}

String localizedBackgroundOptionLabel(
  StudyBackgroundOption option,
  StudyRoomLocalizations localizations,
) {
  if (option.id == 'default') return localizations.defaultBackground;
  final builtIn = StudyBackgroundOption.builtIns.any(
    (candidate) => identical(candidate, option),
  );
  if (!builtIn) return option.label;
  return switch (option.id) {
    'midnight' => localizations.backgroundMidnight,
    'forest' => localizations.backgroundForest,
    _ => option.label,
  };
}

String pomodoroStatusLabel(
  PomodoroStatus status,
  StudyRoomLocalizations localizations,
) => switch (status) {
  PomodoroStatus.idle => localizations.pomodoroReady,
  PomodoroStatus.focusing => localizations.pomodoroFocusing,
  PomodoroStatus.paused => localizations.pomodoroPaused,
  PomodoroStatus.breaking => localizations.pomodoroBreaking,
  PomodoroStatus.finished => localizations.pomodoroFinished,
};

DateTime studyDateOnly(DateTime date) =>
    DateTime(date.year, date.month, date.day);

String studyDateKey(DateTime date) {
  final day = studyDateOnly(date);
  return '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
}
