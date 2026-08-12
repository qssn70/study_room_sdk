// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'study_room_example_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class StudyRoomExampleLocalizationsZh extends StudyRoomExampleLocalizations {
  StudyRoomExampleLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get styleSplit => '分栏';

  @override
  String get styleCentered => '居中';

  @override
  String get styleImmersive => '沉浸';

  @override
  String get openRoomWorkflow => '打开在线房间流程';

  @override
  String get rooms => '房间';

  @override
  String get workflowTitle => 'Study Room 0.4 流程';

  @override
  String get membersTab => '成员';

  @override
  String get requestsTab => '申请';

  @override
  String get configurationInstructions =>
      '请使用 --dart-define=STUDY_ROOM_API_URL=http://localhost:3000 --dart-define=STUDY_ROOM_REALTIME_URL=ws://localhost:3000/v1/realtime --dart-define=STUDY_ROOM_DEV_TOKEN_URL=http://localhost:4000/token 运行。';

  @override
  String get demoRoomTitle => '示例专注房间';

  @override
  String get currentUserName => '你';

  @override
  String get startupFailed => '无法启动在线房间流程，请检查配置后重试。';
}
