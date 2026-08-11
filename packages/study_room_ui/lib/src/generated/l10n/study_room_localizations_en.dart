// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'study_room_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class GeneratedStudyRoomLocalizationsEn
    extends GeneratedStudyRoomLocalizations {
  GeneratedStudyRoomLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get rooms => 'Study rooms';

  @override
  String get createRoom => 'Create room';

  @override
  String get roomTitle => 'Room title';

  @override
  String get joinRoom => 'Request access';

  @override
  String get roomId => 'Room ID';

  @override
  String get pendingRequests => 'Pending requests';

  @override
  String get myRequests => 'My requests';

  @override
  String get approve => 'Approve';

  @override
  String get reject => 'Reject';

  @override
  String get cancel => 'Cancel';

  @override
  String get members => 'Members';

  @override
  String get transferOwnership => 'Transfer ownership';

  @override
  String get remove => 'Remove';

  @override
  String get retry => 'Retry';

  @override
  String get refresh => 'Refresh';

  @override
  String get noRooms => 'You have not joined a room yet';

  @override
  String get noRequests => 'No requests';

  @override
  String get open => 'Open';

  @override
  String get owner => 'Owner';

  @override
  String get member => 'Member';

  @override
  String get pending => 'Pending';

  @override
  String get approved => 'Approved';

  @override
  String get rejected => 'Rejected';

  @override
  String get cancelled => 'Cancelled';

  @override
  String get requestSubmitted => 'Join request submitted';

  @override
  String get operationFailed => 'Operation failed. Please retry.';

  @override
  String get emptyMembers => 'No members yet';

  @override
  String get emptyMessages => 'No messages yet';

  @override
  String get reconnecting => 'Reconnecting';

  @override
  String get connected => 'Connected';

  @override
  String onlineMemberCount(int count) {
    return '$count online';
  }

  @override
  String get presenceFocusing => 'Focusing';

  @override
  String get presenceOnline => 'Online';

  @override
  String get presenceIdle => 'Idle';

  @override
  String get presenceAway => 'Away';

  @override
  String get presenceOffline => 'Offline';

  @override
  String get noCompanions => 'No companions yet';

  @override
  String get start => 'Start';

  @override
  String get play => 'Play';

  @override
  String get pause => 'Pause';

  @override
  String get resume => 'Resume';

  @override
  String get finish => 'Finish';

  @override
  String get messageHint => 'Message';

  @override
  String get send => 'Send';

  @override
  String memberCount(int count) {
    return '$count members';
  }

  @override
  String get localDataLoadFailed => 'Unable to load local study data';

  @override
  String get focusAppTitle => 'Minimal study room';

  @override
  String get focusSection => 'Focus';

  @override
  String get analyticsSection => 'Analytics';

  @override
  String get historySection => 'History';

  @override
  String get settingsSection => 'Settings';

  @override
  String get newTask => 'New task';

  @override
  String get editTask => 'Edit task';

  @override
  String get endCurrentRound => 'End current round';

  @override
  String get skipToBreak => 'Skip to break';

  @override
  String get defaultGoal => 'Complete SDK documentation';

  @override
  String pomodoroProgressRemaining(int done, int target, int minutes) {
    return 'Pomodoro progress: $done/$target | About $minutes min remaining';
  }

  @override
  String pomodoroProgress(int done, int target) {
    return 'Pomodoro progress: $done/$target';
  }

  @override
  String completionPercent(int percent) {
    return '$percent% complete';
  }

  @override
  String get goalSaveFailed => 'Unable to save goal';

  @override
  String focusHistorySummary(int minutes, int count) {
    return '$minutes min · $count pomodoros';
  }

  @override
  String tasksForDate(String date) {
    return 'Tasks for $date';
  }

  @override
  String get noTasks => 'No tasks';

  @override
  String get edit => 'Edit';

  @override
  String get delete => 'Delete';

  @override
  String get deleteTaskTitle => 'Delete task';

  @override
  String deleteTaskConfirmation(String title) {
    return 'Delete “$title”?';
  }

  @override
  String get taskDeleteFailed => 'Unable to delete task';

  @override
  String get taskSaveFailed => 'Unable to save task';

  @override
  String get save => 'Save';

  @override
  String get taskName => 'Task name';

  @override
  String get taskNameRequired => 'Task name cannot be empty';

  @override
  String get background => 'Background';

  @override
  String backgroundMask(int percent) {
    return 'Overlay $percent%';
  }

  @override
  String get defaultBackground => 'Default';

  @override
  String get silentCompanions => 'Silent companions';

  @override
  String get whiteNoise => 'White noise';

  @override
  String get todayPrivateData => 'Today\'s data (private)';

  @override
  String pomodoroPresetMinutes(int focus, int rest) {
    return '$focus / $rest min';
  }

  @override
  String get customDuration => 'Custom duration';

  @override
  String get custom => 'Custom';

  @override
  String get focusMinutes => 'Focus minutes';

  @override
  String get breakMinutes => 'Break minutes';

  @override
  String get apply => 'Apply';

  @override
  String get pomodoroDurationInvalid =>
      'Focus duration must be greater than 0 and break duration cannot be negative';

  @override
  String get saveFailed => 'Save failed';

  @override
  String get pomodoroReady => 'Ready to focus';

  @override
  String get pomodoroFocusing => 'Focusing';

  @override
  String get pomodoroPaused => 'Paused';

  @override
  String get pomodoroBreaking => 'On a break';

  @override
  String get pomodoroFinished => 'Finished';

  @override
  String get skip => 'Skip';

  @override
  String get todayGoal => 'Today\'s goal';

  @override
  String get backgroundSound => 'Background sound';

  @override
  String get privateStats => 'Personal statistics (private)';

  @override
  String get companions => 'Studying together';

  @override
  String get todayFocus => 'Focus today';

  @override
  String get todayPomodoros => 'Pomodoros today';

  @override
  String get streak => 'Streak';

  @override
  String pomodoroCountValue(int count) {
    return '$count';
  }

  @override
  String dayCountValue(int count) {
    return '$count days';
  }

  @override
  String hoursValue(String value) {
    return '${value}h';
  }

  @override
  String get stats => 'Stats';

  @override
  String get soundRain => 'Rain';

  @override
  String get soundWhiteNoise => 'White noise';

  @override
  String get soundCafe => 'Cafe';

  @override
  String get soundLibrary => 'Library';

  @override
  String get soundKeyboard => 'Keyboard';

  @override
  String get backgroundMidnight => 'Midnight';

  @override
  String get backgroundForest => 'Forest';

  @override
  String get unableToSaveFocusSession => 'Unable to save focus session';

  @override
  String get todayGoalLabel => 'Today goal';

  @override
  String get targetPomodoros => 'Target pomodoros';

  @override
  String get analyticsFocus => 'Focus';

  @override
  String get analyticsPomodoros => 'Pomodoros';

  @override
  String get analyticsStreak => 'Streak';

  @override
  String get analyticsToday => 'Today';

  @override
  String get analyticsCount => 'Count';

  @override
  String get analyticsRun => 'Run';

  @override
  String get analyticsTotal => 'Total';

  @override
  String get analyticsSessions => 'Sessions';

  @override
  String get analyticsTasks => 'Tasks';

  @override
  String minutesValue(int count) {
    return '$count min';
  }

  @override
  String daysValue(int count) {
    return '$count days';
  }

  @override
  String pomodorosValue(int count) {
    return '$count pomodoros';
  }

  @override
  String get noTasksReport => 'No tasks';

  @override
  String completionValue(int percent) {
    return '$percent% complete';
  }

  @override
  String get reportNoFocusSessions => 'No focus sessions yet.';

  @override
  String reportSummary(int minutes, int pomodoros, int streak) {
    return '$minutes focused minutes, $pomodoros pomodoros, $streak day streak.';
  }
}
