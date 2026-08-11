import 'package:flutter/widgets.dart';

/// Package-internal clock injection used by deterministic visual tests.
class StudyFocusClockScope extends InheritedWidget {
  const StudyFocusClockScope({
    required this.now,
    required super.child,
    super.key,
  });

  final DateTime Function() now;

  static DateTime nowOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<StudyFocusClockScope>()
            ?.now() ??
        DateTime.now();
  }

  @override
  bool updateShouldNotify(StudyFocusClockScope oldWidget) =>
      now != oldWidget.now;
}
