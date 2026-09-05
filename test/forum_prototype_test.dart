import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islander_flutter/prototypes/forum/forum_prototype_app.dart';
import 'package:islander_flutter/shared/widgets/pixel_shore.dart';

void main() {
  testWidgets('renders the responsive forum shell and animated shore', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ForumPrototypeApp());
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('时间线'), findsWidgets);
    expect(find.text('搜索标题、正文或 No.'), findsOneWidget);
    expect(find.text('ISLANDER.TOP'), findsOneWidget);
    expect(find.byType(PixelShore), findsOneWidget);
    expect(find.byKey(const Key('fab-compose')), findsOneWidget);

    await tester.tap(find.byKey(const Key('fab-compose')));
    await tester.pump(const Duration(milliseconds: 400));

    final sheetRect = tester.getRect(
      find.byKey(const Key('composer-sheet-surface')),
    );
    expect(sheetRect.left, 0);
    expect(sheetRect.right, 1200);
  });

  testWidgets('opens a thread and publishes a reply from the bottom sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ForumPrototypeApp());
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const Key('thread-1842')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('引用 No.1842'), findsOneWidget);

    await tester.tap(find.byKey(const Key('fab-compose')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('写下回复'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('composer-body')),
      'Flutter 原型回复测试',
    );
    final submit = find.byKey(const Key('composer-submit'));
    final submitButton = tester.widget<FilledButton>(submit);
    submitButton.onPressed!.call();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('已回复 No.1842'), findsOneWidget);
  });
}
