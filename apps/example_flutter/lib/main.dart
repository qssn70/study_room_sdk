import 'dart:async';

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
      localizationsDelegates: StudyRoomLocalizations.localizationsDelegates,
      supportedLocales: StudyRoomLocalizations.supportedLocales,
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
  final _store = MemoryStudyStore();

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
              store: _store,
              currentUserId: 'demo-user',
              visualStyle: _style,
              background: widget.background ?? studyFocusDefaultBackground,
              room: StudyRoom(
                id: 'demo-room',
                appId: 'demo-app',
                title: 'Demo Focus Room',
                version: 1,
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
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Semantics(
                    button: true,
                    label: 'Open live room workflow',
                    child: IconButton.filledTonal(
                      key: const Key('open_room_workflow'),
                      tooltip: 'Rooms',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const LiveStudyRoomManagementPage(),
                        ),
                      ),
                      icon: const Icon(Icons.groups_2_outlined),
                    ),
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

class LiveStudyRoomManagementPage extends StatefulWidget {
  const LiveStudyRoomManagementPage({super.key});

  @override
  State<LiveStudyRoomManagementPage> createState() =>
      _LiveStudyRoomManagementPageState();
}

class _LiveStudyRoomManagementPageState
    extends State<LiveStudyRoomManagementPage> {
  static const _apiUrl = String.fromEnvironment('STUDY_ROOM_API_URL');
  static const _realtimeUrl = String.fromEnvironment('STUDY_ROOM_REALTIME_URL');
  static const _token = String.fromEnvironment('STUDY_ROOM_TOKEN');
  static const _expiresAtUnix = int.fromEnvironment(
    'STUDY_ROOM_TOKEN_EXPIRES_AT',
  );
  static const _userId = String.fromEnvironment(
    'STUDY_ROOM_USER_ID',
    defaultValue: 'demo-user',
  );

  StudyRoomSdk? _sdk;
  Future<void>? _started;

  @override
  void initState() {
    super.initState();
    if (_apiUrl.isNotEmpty && _realtimeUrl.isNotEmpty && _token.isNotEmpty) {
      _sdk = StudyRoomSdk(
        StudyRoomSdkConfig(
          apiBaseUri: Uri.parse(_apiUrl),
          realtimeUri: Uri.parse(_realtimeUrl),
          tokenProvider: (_) async => StudyRoomAccessToken(
            value: _token,
            expiresAt: _expiresAtUnix > 0
                ? DateTime.fromMillisecondsSinceEpoch(
                    _expiresAtUnix * 1000,
                    isUtc: true,
                  )
                : DateTime.now().add(const Duration(minutes: 10)),
          ),
        ),
      );
      _started = _sdk!.start();
    }
  }

  @override
  void dispose() {
    final sdk = _sdk;
    if (sdk != null) unawaited(sdk.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Study Room 0.4 workflow')),
      body: _sdk == null
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: SelectableText(
                'Run with --dart-define=STUDY_ROOM_API_URL=http://localhost:3000 '
                '--dart-define=STUDY_ROOM_REALTIME_URL=ws://localhost:3000/v1/realtime '
                '--dart-define=STUDY_ROOM_TOKEN=<jwt> '
                '--dart-define=STUDY_ROOM_TOKEN_EXPIRES_AT=<unix-seconds>.',
              ),
            )
          : FutureBuilder<void>(
              future: _started,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: SelectableText('${snapshot.error}'));
                }
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                return StudyRoomLobbyView(
                  sdk: _sdk!,
                  currentUserId: _userId,
                  onRoomSelected: (room) => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _RoomAdministrationPage(
                        sdk: _sdk!,
                        room: room,
                        currentUserId: _userId,
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _RoomAdministrationPage extends StatelessWidget {
  const _RoomAdministrationPage({
    required this.sdk,
    required this.room,
    required this.currentUserId,
  });
  final StudyRoomSdk sdk;
  final StudyRoom room;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(room.title),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Members'),
              Tab(text: 'Requests'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            RoomMemberManagementView(
              sdk: sdk,
              room: room,
              currentUserId: currentUserId,
            ),
            JoinRequestInboxView(sdk: sdk, roomId: room.id),
          ],
        ),
      ),
    );
  }
}
