import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/widgets/async_views.dart';

import '../helpers/fake_services.dart';
import '../helpers/pump.dart';

void main() {
  setUpAll(setUpScreenTests);

  testWidgets('ErrorView は理由と「再読み込み」を出し、押すと伝える', (tester) async {
    var retried = 0;
    await pumpApp(
      tester,
      TestEnv(),
      Scaffold(
        body: ErrorView(message: '記録を読み込めませんでした', onRetry: () => retried++),
      ),
    );

    expect(find.text('記録を読み込めませんでした'), findsOneWidget);
    await tester.tap(find.text('再読み込み'));
    expect(retried, 1);
  });

  testWidgets('ErrorView は onRetry が無ければボタンを出さない', (tester) async {
    await pumpApp(
      tester,
      TestEnv(),
      const Scaffold(body: ErrorView(message: '読み込めませんでした')),
    );

    expect(find.text('再読み込み'), findsNothing);
  });

  group('saveInBackground', () {
    Future<ScaffoldMessengerState> pumpMessenger(WidgetTester tester) async {
      await pumpApp(tester, TestEnv(), const Scaffold(body: SizedBox()));
      return tester.state<ScaffoldMessengerState>(
        find.byType(ScaffoldMessenger),
      );
    }

    testWidgets('成功したら何も出さない', (tester) async {
      final messenger = await pumpMessenger(tester);

      saveInBackground(messenger, Future.value(), failureMessage: '保存できませんでした');
      await tester.pumpAndSettle();

      expect(find.text('保存できませんでした'), findsNothing);
    });

    testWidgets('失敗したときだけ知らせる', (tester) async {
      final messenger = await pumpMessenger(tester);

      saveInBackground(
        messenger,
        Future.error(Exception('PERMISSION_DENIED')),
        failureMessage: '保存できませんでした',
      );
      await tester.pumpAndSettle();

      expect(find.text('保存できませんでした'), findsOneWidget);
    });
  });
}
