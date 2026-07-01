import 'package:flutter/material.dart';
import 'package:study_room_sdk/study_room_sdk.dart';
import 'package:study_room_ui/study_room_ui.dart';

void main() {
  runApp(const StudyRoomExampleApp());
}

class StudyRoomExampleApp extends StatelessWidget {
  const StudyRoomExampleApp({this.background, super.key});

  final StudyBackground? background;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2563EB),
        useMaterial3: true,
      ),
      home: StudyRoomExampleHome(background: background),
    );
  }
}

class StudyRoomExampleHome extends StatefulWidget {
  const StudyRoomExampleHome({this.background, super.key});

  final StudyBackground? background;

  @override
  State<StudyRoomExampleHome> createState() => _StudyRoomExampleHomeState();
}

class _StudyRoomExampleHomeState extends State<StudyRoomExampleHome> {
  var _style = StudyFocusVisualStyle.immersiveDock;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktopLandscape =
            constraints.maxWidth >= 1100 &&
            constraints.maxWidth > constraints.maxHeight;
        return Stack(
          children: [
            StudyFocusKitView(
              store: MemoryStudyStore(),
              currentUserId: 'demo-user',
              visualStyle: _style,
              background: widget.background ?? studyFocusDefaultBackground,
              room: const StudyRoom(
                id: 'demo-room',
                title: 'Demo Focus Room',
                members: [
                  StudyMember(
                    id: 'demo-user',
                    displayName: 'You',
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
                    segments: const [
                      ButtonSegment(
                        value: StudyFocusVisualStyle.split,
                        label: Text('Split'),
                      ),
                      ButtonSegment(
                        value: StudyFocusVisualStyle.centered,
                        label: Text('Centered'),
                      ),
                      ButtonSegment(
                        value: StudyFocusVisualStyle.immersiveDock,
                        label: Text('Immersive'),
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
