import 'package:flutter/material.dart';
import 'package:study_room_sdk/study_room_sdk.dart';
import 'package:study_room_ui/study_room_ui.dart';

import 'l10n/generated/study_room_example_localizations.dart';
import 'live_workflow_controller.dart';
import 'live_workflow_page.dart';

void main() {
  runApp(const StudyRoomExampleApp());
}

class StudyRoomExampleApp extends StatelessWidget {
  const StudyRoomExampleApp({
    this.background,
    this.locale,
    this.workflowController,
    this.autoConnect = true,
    super.key,
  });

  final StudyBackground? background;
  final Locale? locale;
  final LiveWorkflowController? workflowController;
  final bool autoConnect;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: locale,
      localizationsDelegates: [
        StudyRoomExampleLocalizations.delegate,
        ...StudyRoomLocalizations.localizationsDelegates,
      ],
      supportedLocales: StudyRoomExampleLocalizations.supportedLocales,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2563EB),
        useMaterial3: true,
      ),
      home: Builder(
        builder: (context) => LiveWorkflowPage(
          controller: workflowController,
          autoConnect: autoConnect,
          onOpenOffline: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => OfflineFocusDemo(background: background),
            ),
          ),
        ),
      ),
    );
  }
}

class OfflineFocusDemo extends StatefulWidget {
  const OfflineFocusDemo({this.background, super.key});

  final StudyBackground? background;

  @override
  State<OfflineFocusDemo> createState() => _OfflineFocusDemoState();
}

class _OfflineFocusDemoState extends State<OfflineFocusDemo> {
  var _style = StudyFocusVisualStyle.immersiveDock;
  final _store = MemoryStudyStore();

  @override
  Widget build(BuildContext context) {
    final localizations = StudyRoomExampleLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktopLandscape =
            constraints.maxWidth >= 1100 &&
            constraints.maxWidth > constraints.maxHeight;
        return Stack(
          children: [
            StudyFocusKitView(
              store: _store,
              currentUserId: 'demo-user',
              visualStyle: _style,
              background: widget.background ?? studyFocusDefaultBackground,
              room: StudyRoom(
                id: 'demo-room',
                appId: 'demo-app',
                title: localizations.demoRoomTitle,
                version: 1,
                members: [
                  StudyMember(
                    id: 'demo-user',
                    displayName: localizations.currentUserName,
                    avatarUrl: '',
                    status: PresenceStatus.focusing,
                  ),
                  StudyMember(
                    id: 'demo-friend-1',
                    displayName: 'Lin',
                    avatarUrl: '',
                    status: PresenceStatus.focusing,
                  ),
                  StudyMember(
                    id: 'demo-friend-2',
                    displayName: 'Kai',
                    avatarUrl: '',
                    status: PresenceStatus.away,
                  ),
                ],
              ),
            ),
            SafeArea(
              child: Align(
                alignment: desktopLandscape
                    ? Alignment.topRight
                    : Alignment.topCenter,
                child: Padding(
                  padding: desktopLandscape
                      ? const EdgeInsets.fromLTRB(12, 76, 412, 12)
                      : const EdgeInsets.all(12),
                  child: SegmentedButton<StudyFocusVisualStyle>(
                    key: const Key('study_focus_style_switcher'),
                    style: _styleSwitcherStyle(),
                    segments: [
                      ButtonSegment(
                        value: StudyFocusVisualStyle.split,
                        label: Text(localizations.styleSplit),
                      ),
                      ButtonSegment(
                        value: StudyFocusVisualStyle.centered,
                        label: Text(localizations.styleCentered),
                      ),
                      ButtonSegment(
                        value: StudyFocusVisualStyle.immersiveDock,
                        label: Text(localizations.styleImmersive),
                      ),
                    ],
                    selected: {_style},
                    onSelectionChanged: (selection) {
                      setState(() => _style = selection.single);
                    },
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: IconButton.filledTonal(
                    key: const Key('close_offline_focus'),
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).backButtonTooltip,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  ButtonStyle _styleSwitcherStyle() {
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return Colors.white.withValues(alpha: 0.92);
        }
        return Colors.black.withValues(alpha: 0.18);
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const Color(0xFF10251A);
        }
        return Colors.white.withValues(alpha: 0.84);
      }),
      iconColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const Color(0xFF10251A);
        }
        return Colors.white.withValues(alpha: 0.84);
      }),
      side: WidgetStatePropertyAll(
        BorderSide(color: Colors.white.withValues(alpha: 0.24)),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    );
  }
}
