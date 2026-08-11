import 'package:flutter_test/flutter_test.dart';
import 'package:study_room_sdk/study_room_sdk.dart';
import 'package:study_room_ui/src/focus_contracts.dart';
import 'package:study_room_ui/study_room_ui.dart';

void main() {
  test('internal layout contracts snapshot mutable input collections', () {
    final members = <StudyMember>[];
    final tracks = <StudySoundTrack>[...StudySoundTrack.builtIns];
    final backgrounds = <StudyBackgroundOption>[
      ...StudyBackgroundOption.builtIns,
    ];

    final shell = StudyFocusShellModel(
      loadPhase: StudyFocusLoadPhase.ready,
      visualStyle: StudyFocusVisualStyle.immersiveDock,
      desktopSection: StudyFocusDesktopSection.focus,
      background: studyFocusDefaultBackground,
      backgrounds: backgrounds,
      activeBackgroundId: 'default',
      activeBackgroundMaskOpacity: 0.2,
    );
    final data = StudyFocusDataModel(
      store: MemoryStudyStore(),
      date: DateTime(2026, 8, 11),
      timerState: PomodoroState.initial(PomodoroConfig()),
      timerConfig: PomodoroConfig(),
      members: members,
      currentUserId: 'user-1',
      showCompanions: true,
      dataRevision: 0,
    );
    final sound = StudyFocusSoundModel(
      tracks: tracks,
      selectedTrackId: tracks.first.id,
      playing: false,
      volume: 0.5,
    );

    members.add(
      const StudyMember(
        id: 'member-1',
        displayName: 'Lin',
        avatarUrl: '',
        status: PresenceStatus.online,
      ),
    );
    tracks.clear();
    backgrounds.clear();

    expect(data.members, isEmpty);
    expect(sound.tracks, isNotEmpty);
    expect(shell.backgrounds, isNotEmpty);
    expect(() => data.members.add(members.single), throwsUnsupportedError);
  });
}
