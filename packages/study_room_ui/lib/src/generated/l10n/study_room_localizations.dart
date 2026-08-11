import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'study_room_localizations_en.dart';
import 'study_room_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of GeneratedStudyRoomLocalizations
/// returned by `GeneratedStudyRoomLocalizations.of(context)`.
///
/// Applications need to include `GeneratedStudyRoomLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/study_room_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: GeneratedStudyRoomLocalizations.localizationsDelegates,
///   supportedLocales: GeneratedStudyRoomLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the GeneratedStudyRoomLocalizations.supportedLocales
/// property.
abstract class GeneratedStudyRoomLocalizations {
  GeneratedStudyRoomLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static GeneratedStudyRoomLocalizations of(BuildContext context) {
    return Localizations.of<GeneratedStudyRoomLocalizations>(
      context,
      GeneratedStudyRoomLocalizations,
    )!;
  }

  static const LocalizationsDelegate<GeneratedStudyRoomLocalizations> delegate =
      _GeneratedStudyRoomLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @rooms.
  ///
  /// In en, this message translates to:
  /// **'Study rooms'**
  String get rooms;

  /// No description provided for @createRoom.
  ///
  /// In en, this message translates to:
  /// **'Create room'**
  String get createRoom;

  /// No description provided for @roomTitle.
  ///
  /// In en, this message translates to:
  /// **'Room title'**
  String get roomTitle;

  /// No description provided for @joinRoom.
  ///
  /// In en, this message translates to:
  /// **'Request access'**
  String get joinRoom;

  /// No description provided for @roomId.
  ///
  /// In en, this message translates to:
  /// **'Room ID'**
  String get roomId;

  /// No description provided for @pendingRequests.
  ///
  /// In en, this message translates to:
  /// **'Pending requests'**
  String get pendingRequests;

  /// No description provided for @myRequests.
  ///
  /// In en, this message translates to:
  /// **'My requests'**
  String get myRequests;

  /// No description provided for @approve.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get approve;

  /// No description provided for @reject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get reject;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @members.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get members;

  /// No description provided for @transferOwnership.
  ///
  /// In en, this message translates to:
  /// **'Transfer ownership'**
  String get transferOwnership;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @noRooms.
  ///
  /// In en, this message translates to:
  /// **'You have not joined a room yet'**
  String get noRooms;

  /// No description provided for @noRequests.
  ///
  /// In en, this message translates to:
  /// **'No requests'**
  String get noRequests;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @owner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get owner;

  /// No description provided for @member.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get member;

  /// No description provided for @pending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pending;

  /// No description provided for @approved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get approved;

  /// No description provided for @rejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get rejected;

  /// No description provided for @cancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get cancelled;

  /// No description provided for @requestSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Join request submitted'**
  String get requestSubmitted;

  /// No description provided for @operationFailed.
  ///
  /// In en, this message translates to:
  /// **'Operation failed. Please retry.'**
  String get operationFailed;

  /// No description provided for @emptyMembers.
  ///
  /// In en, this message translates to:
  /// **'No members yet'**
  String get emptyMembers;

  /// No description provided for @emptyMessages.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get emptyMessages;

  /// No description provided for @reconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting'**
  String get reconnecting;

  /// No description provided for @connected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

  /// No description provided for @onlineMemberCount.
  ///
  /// In en, this message translates to:
  /// **'{count} online'**
  String onlineMemberCount(int count);

  /// No description provided for @presenceFocusing.
  ///
  /// In en, this message translates to:
  /// **'Focusing'**
  String get presenceFocusing;

  /// No description provided for @presenceOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get presenceOnline;

  /// No description provided for @presenceIdle.
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get presenceIdle;

  /// No description provided for @presenceAway.
  ///
  /// In en, this message translates to:
  /// **'Away'**
  String get presenceAway;

  /// No description provided for @presenceOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get presenceOffline;

  /// No description provided for @noCompanions.
  ///
  /// In en, this message translates to:
  /// **'No companions yet'**
  String get noCompanions;

  /// No description provided for @start.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get start;

  /// No description provided for @play.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @resume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resume;

  /// No description provided for @finish.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get finish;

  /// No description provided for @messageHint.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get messageHint;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @memberCount.
  ///
  /// In en, this message translates to:
  /// **'{count} members'**
  String memberCount(int count);

  /// No description provided for @localDataLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load local study data'**
  String get localDataLoadFailed;

  /// No description provided for @focusAppTitle.
  ///
  /// In en, this message translates to:
  /// **'Minimal study room'**
  String get focusAppTitle;

  /// No description provided for @focusSection.
  ///
  /// In en, this message translates to:
  /// **'Focus'**
  String get focusSection;

  /// No description provided for @analyticsSection.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get analyticsSection;

  /// No description provided for @historySection.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historySection;

  /// No description provided for @settingsSection.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsSection;

  /// No description provided for @newTask.
  ///
  /// In en, this message translates to:
  /// **'New task'**
  String get newTask;

  /// No description provided for @editTask.
  ///
  /// In en, this message translates to:
  /// **'Edit task'**
  String get editTask;

  /// No description provided for @endCurrentRound.
  ///
  /// In en, this message translates to:
  /// **'End current round'**
  String get endCurrentRound;

  /// No description provided for @skipToBreak.
  ///
  /// In en, this message translates to:
  /// **'Skip to break'**
  String get skipToBreak;

  /// No description provided for @defaultGoal.
  ///
  /// In en, this message translates to:
  /// **'Complete SDK documentation'**
  String get defaultGoal;

  /// No description provided for @pomodoroProgressRemaining.
  ///
  /// In en, this message translates to:
  /// **'Pomodoro progress: {done}/{target} | About {minutes} min remaining'**
  String pomodoroProgressRemaining(int done, int target, int minutes);

  /// No description provided for @pomodoroProgress.
  ///
  /// In en, this message translates to:
  /// **'Pomodoro progress: {done}/{target}'**
  String pomodoroProgress(int done, int target);

  /// No description provided for @completionPercent.
  ///
  /// In en, this message translates to:
  /// **'{percent}% complete'**
  String completionPercent(int percent);

  /// No description provided for @goalSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to save goal'**
  String get goalSaveFailed;

  /// No description provided for @focusHistorySummary.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min · {count} pomodoros'**
  String focusHistorySummary(int minutes, int count);

  /// No description provided for @tasksForDate.
  ///
  /// In en, this message translates to:
  /// **'Tasks for {date}'**
  String tasksForDate(String date);

  /// No description provided for @noTasks.
  ///
  /// In en, this message translates to:
  /// **'No tasks'**
  String get noTasks;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @deleteTaskTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete task'**
  String get deleteTaskTitle;

  /// No description provided for @deleteTaskConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Delete “{title}”?'**
  String deleteTaskConfirmation(String title);

  /// No description provided for @taskDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to delete task'**
  String get taskDeleteFailed;

  /// No description provided for @taskSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to save task'**
  String get taskSaveFailed;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @taskName.
  ///
  /// In en, this message translates to:
  /// **'Task name'**
  String get taskName;

  /// No description provided for @taskNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Task name cannot be empty'**
  String get taskNameRequired;

  /// No description provided for @background.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get background;

  /// No description provided for @backgroundMask.
  ///
  /// In en, this message translates to:
  /// **'Overlay {percent}%'**
  String backgroundMask(int percent);

  /// No description provided for @defaultBackground.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get defaultBackground;

  /// No description provided for @silentCompanions.
  ///
  /// In en, this message translates to:
  /// **'Silent companions'**
  String get silentCompanions;

  /// No description provided for @whiteNoise.
  ///
  /// In en, this message translates to:
  /// **'White noise'**
  String get whiteNoise;

  /// No description provided for @todayPrivateData.
  ///
  /// In en, this message translates to:
  /// **'Today\'s data (private)'**
  String get todayPrivateData;

  /// No description provided for @pomodoroPresetMinutes.
  ///
  /// In en, this message translates to:
  /// **'{focus} / {rest} min'**
  String pomodoroPresetMinutes(int focus, int rest);

  /// No description provided for @customDuration.
  ///
  /// In en, this message translates to:
  /// **'Custom duration'**
  String get customDuration;

  /// No description provided for @custom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get custom;

  /// No description provided for @focusMinutes.
  ///
  /// In en, this message translates to:
  /// **'Focus minutes'**
  String get focusMinutes;

  /// No description provided for @breakMinutes.
  ///
  /// In en, this message translates to:
  /// **'Break minutes'**
  String get breakMinutes;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @pomodoroDurationInvalid.
  ///
  /// In en, this message translates to:
  /// **'Focus duration must be greater than 0 and break duration cannot be negative'**
  String get pomodoroDurationInvalid;

  /// No description provided for @saveFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed'**
  String get saveFailed;

  /// No description provided for @pomodoroReady.
  ///
  /// In en, this message translates to:
  /// **'Ready to focus'**
  String get pomodoroReady;

  /// No description provided for @pomodoroFocusing.
  ///
  /// In en, this message translates to:
  /// **'Focusing'**
  String get pomodoroFocusing;

  /// No description provided for @pomodoroPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get pomodoroPaused;

  /// No description provided for @pomodoroBreaking.
  ///
  /// In en, this message translates to:
  /// **'On a break'**
  String get pomodoroBreaking;

  /// No description provided for @pomodoroFinished.
  ///
  /// In en, this message translates to:
  /// **'Finished'**
  String get pomodoroFinished;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @todayGoal.
  ///
  /// In en, this message translates to:
  /// **'Today\'s goal'**
  String get todayGoal;

  /// No description provided for @backgroundSound.
  ///
  /// In en, this message translates to:
  /// **'Background sound'**
  String get backgroundSound;

  /// No description provided for @privateStats.
  ///
  /// In en, this message translates to:
  /// **'Personal statistics (private)'**
  String get privateStats;

  /// No description provided for @companions.
  ///
  /// In en, this message translates to:
  /// **'Studying together'**
  String get companions;

  /// No description provided for @todayFocus.
  ///
  /// In en, this message translates to:
  /// **'Focus today'**
  String get todayFocus;

  /// No description provided for @todayPomodoros.
  ///
  /// In en, this message translates to:
  /// **'Pomodoros today'**
  String get todayPomodoros;

  /// No description provided for @streak.
  ///
  /// In en, this message translates to:
  /// **'Streak'**
  String get streak;

  /// No description provided for @pomodoroCountValue.
  ///
  /// In en, this message translates to:
  /// **'{count}'**
  String pomodoroCountValue(int count);

  /// No description provided for @dayCountValue.
  ///
  /// In en, this message translates to:
  /// **'{count} days'**
  String dayCountValue(int count);

  /// No description provided for @hoursValue.
  ///
  /// In en, this message translates to:
  /// **'{value}h'**
  String hoursValue(String value);

  /// No description provided for @stats.
  ///
  /// In en, this message translates to:
  /// **'Stats'**
  String get stats;

  /// No description provided for @soundRain.
  ///
  /// In en, this message translates to:
  /// **'Rain'**
  String get soundRain;

  /// No description provided for @soundWhiteNoise.
  ///
  /// In en, this message translates to:
  /// **'White noise'**
  String get soundWhiteNoise;

  /// No description provided for @soundCafe.
  ///
  /// In en, this message translates to:
  /// **'Cafe'**
  String get soundCafe;

  /// No description provided for @soundLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get soundLibrary;

  /// No description provided for @soundKeyboard.
  ///
  /// In en, this message translates to:
  /// **'Keyboard'**
  String get soundKeyboard;

  /// No description provided for @backgroundMidnight.
  ///
  /// In en, this message translates to:
  /// **'Midnight'**
  String get backgroundMidnight;

  /// No description provided for @backgroundForest.
  ///
  /// In en, this message translates to:
  /// **'Forest'**
  String get backgroundForest;

  /// No description provided for @unableToSaveFocusSession.
  ///
  /// In en, this message translates to:
  /// **'Unable to save focus session'**
  String get unableToSaveFocusSession;

  /// No description provided for @todayGoalLabel.
  ///
  /// In en, this message translates to:
  /// **'Today goal'**
  String get todayGoalLabel;

  /// No description provided for @targetPomodoros.
  ///
  /// In en, this message translates to:
  /// **'Target pomodoros'**
  String get targetPomodoros;

  /// No description provided for @analyticsFocus.
  ///
  /// In en, this message translates to:
  /// **'Focus'**
  String get analyticsFocus;

  /// No description provided for @analyticsPomodoros.
  ///
  /// In en, this message translates to:
  /// **'Pomodoros'**
  String get analyticsPomodoros;

  /// No description provided for @analyticsStreak.
  ///
  /// In en, this message translates to:
  /// **'Streak'**
  String get analyticsStreak;

  /// No description provided for @analyticsToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get analyticsToday;

  /// No description provided for @analyticsCount.
  ///
  /// In en, this message translates to:
  /// **'Count'**
  String get analyticsCount;

  /// No description provided for @analyticsRun.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get analyticsRun;

  /// No description provided for @analyticsTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get analyticsTotal;

  /// No description provided for @analyticsSessions.
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get analyticsSessions;

  /// No description provided for @analyticsTasks.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get analyticsTasks;

  /// No description provided for @minutesValue.
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String minutesValue(int count);

  /// No description provided for @daysValue.
  ///
  /// In en, this message translates to:
  /// **'{count} days'**
  String daysValue(int count);

  /// No description provided for @pomodorosValue.
  ///
  /// In en, this message translates to:
  /// **'{count} pomodoros'**
  String pomodorosValue(int count);

  /// No description provided for @noTasksReport.
  ///
  /// In en, this message translates to:
  /// **'No tasks'**
  String get noTasksReport;

  /// No description provided for @completionValue.
  ///
  /// In en, this message translates to:
  /// **'{percent}% complete'**
  String completionValue(int percent);

  /// No description provided for @reportNoFocusSessions.
  ///
  /// In en, this message translates to:
  /// **'No focus sessions yet.'**
  String get reportNoFocusSessions;

  /// No description provided for @reportSummary.
  ///
  /// In en, this message translates to:
  /// **'{minutes} focused minutes, {pomodoros} pomodoros, {streak} day streak.'**
  String reportSummary(int minutes, int pomodoros, int streak);
}

class _GeneratedStudyRoomLocalizationsDelegate
    extends LocalizationsDelegate<GeneratedStudyRoomLocalizations> {
  const _GeneratedStudyRoomLocalizationsDelegate();

  @override
  Future<GeneratedStudyRoomLocalizations> load(Locale locale) {
    return SynchronousFuture<GeneratedStudyRoomLocalizations>(
      lookupGeneratedStudyRoomLocalizations(locale),
    );
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_GeneratedStudyRoomLocalizationsDelegate old) => false;
}

GeneratedStudyRoomLocalizations lookupGeneratedStudyRoomLocalizations(
  Locale locale,
) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return GeneratedStudyRoomLocalizationsEn();
    case 'zh':
      return GeneratedStudyRoomLocalizationsZh();
  }

  throw FlutterError(
    'GeneratedStudyRoomLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
