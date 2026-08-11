import 'package:flutter/widgets.dart';
import 'package:study_room_sdk/study_room_sdk.dart';

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
