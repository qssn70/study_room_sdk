import 'package:flutter/material.dart';

class StudyRoomTheme {
  const StudyRoomTheme({
    this.activeColor = const Color(0xFF2563EB),
    this.surfaceColor = const Color(0xFFF8FAFC),
    this.borderColor = const Color(0xFFE2E8F0),
  });

  final Color activeColor;
  final Color surfaceColor;
  final Color borderColor;
}

class StudyRoomCopy {
  const StudyRoomCopy({
    this.emptyMembers,
    this.emptyMessages,
    this.reconnecting,
    this.connected,
  });

  /// Overrides the localized empty-member message when non-null.
  final String? emptyMembers;

  /// Overrides the localized empty-chat message when non-null.
  final String? emptyMessages;

  /// Overrides the localized reconnecting state when non-null.
  final String? reconnecting;

  /// Overrides the localized connected state when non-null.
  final String? connected;
}
