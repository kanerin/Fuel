import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/app.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'helpers/fake_services.dart';
import 'helpers/fixtures.dart';

// アプリ本体（FuelApp）の組み立て: AppScopeがMaterialAppより上にあり、
// pushした画面からもサービスを引けること、日本語化されていること。
void main() {
  setUpAll(() => initializeDateFormatting('ja'));

  testWidgets('未ログインならログイン画面から始まる', (tester) async {
    final env = TestEnv(auth: FakeAuthService());
    await tester.pumpWidget(FuelApp(services: env.services));
    await tester.pump();

    expect(find.text('Googleでログイン'), findsOneWidget);
  });

  testWidgets('pushした画面からもサービスを使える（AppScopeがMaterialAppの外側にある）', (
    tester,
  ) async {
    final env = TestEnv();
    await env.seedProfile(sampleProfile);
    await tester.pumpWidget(FuelApp(services: env.services));
    await tester.pumpAndSettle();

    await tester.tap(find.text('設定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('お気に入りの食品'));
    await tester.pumpAndSettle();

    expect(find.textContaining('1タップで記録できます'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Flutter標準のダイアログの文言も日本語になる', (tester) async {
    final env = TestEnv();
    await env.seedProfile(sampleProfile);
    await tester.pumpWidget(FuelApp(services: env.services));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Scaffold).first);
    expect(MaterialLocalizations.of(context).cancelButtonLabel, 'キャンセル');
  });
}
