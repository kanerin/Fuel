// 結合テスト: 小さい画面・大きい文字サイズで、主な画面のレイアウトが崩れない
// （はみ出し・重なりが起きない）ことを実機の描画で確かめる。
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/app.dart';
import 'package:fuel/services/app_services.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/e2e.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initE2E);
  tearDownAll(() => FirebaseAuth.instance.signOut());

  for (final (label, size, textScale) in [
    ('小さい画面（320×568）', const Size(320, 568), 1.0),
    ('文字サイズ大（1.3倍）', const Size(360, 780), 1.3),
  ]) {
    testWidgets('主な画面がはみ出さない: $label', (tester) async {
      await signInAsNewUser(tester, profile: e2eProfile);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(FuelApp(services: AppServices.firebase()));
      await settle(tester);
      await pumpUntil(tester, () => find.text('きょう').evaluate().isNotEmpty);
      expectNoLayoutOverflow(tester, context: '$label・きょう');

      for (final tab in ['履歴', '体重', '設定']) {
        await tester.tap(find.text(tab));
        await settle(tester);
        expectNoLayoutOverflow(tester, context: '$label・$tab');
      }
    });
  }
}
