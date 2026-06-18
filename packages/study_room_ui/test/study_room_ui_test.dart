import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_room_sdk/study_room_sdk.dart';
import 'package:study_room_ui/study_room_ui.dart';

void main() {
  testWidgets('MemberGrid renders names and presence labels', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MemberGrid(
          members: const [
            StudyMember(
              id: 'u1',
              displayName: 'Lin',
              avatarUrl: '',
              status: PresenceStatus.focusing,
            ),
          ],
        ),
      ),
    );

    expect(find.text('Lin'), findsOneWidget);
    expect(find.text('Focusing'), findsOneWidget);
  });

  testWidgets('FocusTimer exposes start and pause actions', (tester) async {
    var started = false;
    var paused = false;

    await tester.pumpWidget(
      MaterialApp(
        home: FocusTimer(
          elapsed: const Duration(minutes: 25),
          status: StudySessionStatus.running,
          onStart: () => started = true,
          onPause: () => paused = true,
        ),
      ),
    );

    expect(find.text('25:00'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.pause));
    expect(paused, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        home: FocusTimer(
          elapsed: Duration.zero,
          status: StudySessionStatus.idle,
          onStart: () => started = true,
          onPause: () => paused = true,
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.play_arrow));
    expect(started, isTrue);
  });

  testWidgets('ChatPanel sends trimmed non-empty text', (tester) async {
    String? sent;

    await tester.pumpWidget(
      MaterialApp(
        home: ChatPanel(
          messages: const [],
          onSend: (text) async {
            sent = text;
          },
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), ' hello ');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(sent, 'hello');
  });
}
