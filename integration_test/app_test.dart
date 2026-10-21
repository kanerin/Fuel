// 結合テスト: アプリ本体（main.dart）を起動し、google-services.json からの
// Firebaseの初期化と、ログイン状態による振り分けが実機で動くことを確かめる。
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/main.dart' as app;
import 'package:integration_test/integration_test.dart';

import 'helpers/e2e.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initE2E();
    // 別のテストファイルのログイン状態が端末に残っている可能性があるので、未ログインから始める
    await FirebaseAuth.instance.signOut();
  });

  testWidgets('起動: 未ログインならログイン画面に到達する', (tester) async {
    await app.main();
    await settle(tester);

    await pumpUntil(
      tester,
      () => find.text('Googleでログイン').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 40),
      reason: 'ログイン画面に到達しない（main()の初期化で止まっている可能性）',
    );
    expect(find.text('Fuel'), findsOneWidget);
    expectNoLayoutOverflow(tester, context: 'ログイン画面');
  });
}
