import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_room_example/main.dart';
import 'package:study_room_ui/study_room_ui.dart';

const _testBackground = StudyBackground.color(
  Color(0xFF20162D),
  maskOpacity: 0.25,
);

void main() {
  testWidgets('example app switches between the three visual styles', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const StudyRoomExampleApp(background: _testBackground),
    );
    await tester.pumpAndSettle();

    expect(find.text('Split'), findsOneWidget);
    expect(find.text('Centered'), findsOneWidget);
    expect(find.text('Immersive'), findsOneWidget);
    expect(
      find.byKey(const Key('study_focus_style_immersiveDock_portrait')),
      findsOneWidget,
    );

    await tester.tap(find.text('Split'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('study_focus_style_split_portrait')),
      findsOneWidget,
    );

    await tester.tap(find.text('Centered'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('study_focus_style_centered_portrait')),
      findsOneWidget,
    );
  });

  testWidgets('example app keeps style switcher in the desktop toolbar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const StudyRoomExampleApp(background: _testBackground),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('study_focus_desktop_shell')), findsOneWidget);
    final switcherFinder = find.byKey(const Key('study_focus_style_switcher'));
    final switcherTopLeft = tester.getTopLeft(switcherFinder);
    final switcherBottomRight = tester.getBottomRight(switcherFinder);
    final sidebarLeft = tester
        .getTopLeft(find.byKey(const Key('study_focus_desktop_sidebar')))
        .dx;

    expect(switcherTopLeft.dy, inInclusiveRange(72, 132));
    expect(switcherBottomRight.dy, lessThan(180));
    expect(switcherBottomRight.dx, lessThan(sidebarLeft - 16));

    final switcher = tester.widget<SegmentedButton<StudyFocusVisualStyle>>(
      switcherFinder,
    );
    expect(switcher.style?.backgroundColor?.resolve({}), isNotNull);
    expect(switcher.style?.foregroundColor?.resolve({}), isNotNull);
  });

  testWidgets('example shell follows the platform locale', (tester) async {
    await tester.pumpWidget(
      const StudyRoomExampleApp(
        background: _testBackground,
        locale: Locale('zh'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('分栏'), findsOneWidget);
    expect(find.text('居中'), findsOneWidget);
    expect(find.text('沉浸'), findsOneWidget);
    expect(find.byTooltip('房间'), findsOneWidget);
  });
}
