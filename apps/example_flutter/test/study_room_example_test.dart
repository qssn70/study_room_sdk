import 'package:flutter_test/flutter_test.dart';
import 'package:study_room_example/main.dart';

void main() {
  testWidgets('example app renders the complete study focus kit', (
    tester,
  ) async {
    await tester.pumpWidget(const StudyRoomExampleApp());
    await tester.pumpAndSettle();

    expect(find.text('Pomodoro'), findsOneWidget);
    expect(find.text('Today goal'), findsWidgets);
    expect(find.text('Study records'), findsOneWidget);
    expect(find.text('Personal analytics'), findsOneWidget);
    expect(find.text('Background sound'), findsOneWidget);
    expect(find.text('Background'), findsOneWidget);
    expect(find.text('Companions'), findsOneWidget);
  });
}
