import 'package:flutter/widgets.dart';
import 'package:study_room_sdk/study_room_sdk.dart';

/// High-level visual arrangement used by the focus workspace.
enum StudyFocusVisualStyle { split, centered, immersiveDock }

/// Navigable sections of the desktop focus workspace.
enum StudyFocusDesktopSection { focus, analytics, history, settings }

/// Overrides a desktop section while retaining access to its default widget.
typedef StudyFocusDesktopPageBuilder =
    Widget Function(
      BuildContext context,
      StudyFocusDesktopSection section,
      Widget defaultPage,
    );

/// Opens a host-defined create or edit flow for a dated study task.
typedef StudyTaskEditor =
    Future<StudyTaskRecord?> Function(
      BuildContext context,
      DateTime date,
      StudyTaskRecord? existing,
    );
