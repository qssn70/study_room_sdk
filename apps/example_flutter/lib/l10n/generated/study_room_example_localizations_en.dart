// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'study_room_example_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class StudyRoomExampleLocalizationsEn extends StudyRoomExampleLocalizations {
  StudyRoomExampleLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get styleSplit => 'Split';

  @override
  String get styleCentered => 'Centered';

  @override
  String get styleImmersive => 'Immersive';

  @override
  String get openRoomWorkflow => 'Open live room workflow';

  @override
  String get rooms => 'Rooms';

  @override
  String get workflowTitle => 'Study Room 0.4 workflow';

  @override
  String get membersTab => 'Members';

  @override
  String get requestsTab => 'Requests';

  @override
  String get configurationInstructions =>
      'Run with --dart-define=STUDY_ROOM_API_URL=http://localhost:3000 --dart-define=STUDY_ROOM_REALTIME_URL=ws://localhost:3000/v1/realtime --dart-define=STUDY_ROOM_DEV_TOKEN_URL=http://localhost:4000/token.';

  @override
  String get demoRoomTitle => 'Demo Focus Room';

  @override
  String get currentUserName => 'You';

  @override
  String get startupFailed =>
      'Unable to start the live room workflow. Check the configuration and try again.';
}
