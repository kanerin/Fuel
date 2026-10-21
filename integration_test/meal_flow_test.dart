// 結合テスト: 食事の記録が、実際のFirestore（セキュリティルール込み）に保存され、
// ストリーム経由で画面に反映され、削除・元に戻すまで通ることを確かめる。
// あわせて、AI推定の呼び出しがCloud Functions（エミュレータ）まで届くことを確かめる。
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/services/nutrition_estimator.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/e2e.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initE2E);
  tearDownAll(() => FirebaseAuth.instance.signOut());

  CollectionReference<Map<String, dynamic>> mealsOf(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('meals');

  testWidgets('手入力で追加 → 一覧とFirestoreに反映 → スワイプで削除 → 元に戻す', (tester) async {
    final uid = await signInAsNewUser(tester, profile: e2eProfile);
    await pumpFuelApp(tester);
    await pumpUntil(tester, () => find.text('きょう').evaluate().isNotEmpty);

    await scrollAndTap(tester, find.byTooltip('朝食に追加'));
    await scrollAndTap(tester, find.text('手入力'));
    await tester.enterText(textFieldWithLabel('名前'), 'オートミール');
    await tester.enterText(textFieldWithLabel('量（任意）'), '30g');
    await tester.enterText(textFieldWithLabel('エネルギー'), '114');
    await tester.enterText(textFieldWithLabel('たんぱく質'), '4.1');
    await tester.enterText(textFieldWithLabel('脂質'), '1.7');
    await tester.enterText(textFieldWithLabel('炭水化物'), '20.7');
    await scrollAndTap(tester, find.text('追加する'));

    await pumpUntil(
      tester,
      () => find.text('オートミール').evaluate().isNotEmpty,
      reason: '追加した記録が一覧に出ない',
    );
    await pumpUntilAsync(tester, () async {
      final snap = await mealsOf(
        uid,
      ).get(const GetOptions(source: Source.server));
      return snap.docs.length == 1;
    }, reason: '記録がサーバーに保存されない（ルールで拒否された可能性）');
    final saved = (await mealsOf(uid).get()).docs.single.data();
    expect(saved['date'], todayKey());
    expect(saved['mealType'], 'breakfast');
    expect(saved['source'], 'manual');
    expect(saved['calories'], 114);

    await tester.drag(find.text('オートミール'), const Offset(-600, 0));
    await settle(tester);
    await pumpUntilAsync(tester, () async {
      final snap = await mealsOf(
        uid,
      ).get(const GetOptions(source: Source.server));
      return snap.docs.isEmpty;
    }, reason: '削除がサーバーに反映されない');

    await tester.tap(find.text('元に戻す'));
    await settle(tester);
    await pumpUntil(tester, () => find.text('オートミール').evaluate().isNotEmpty);
    await pumpUntilAsync(tester, () async {
      final snap = await mealsOf(
        uid,
      ).get(const GetOptions(source: Source.server));
      return snap.docs.length == 1;
    }, reason: '元に戻した記録がサーバーに保存されない');
    expectNoLayoutOverflow(tester, context: '記録の追加・削除');
  });

  testWidgets('AI推定: Cloud Functions まで届き、APIキー未設定の理由が画面に出る', (tester) async {
    // CIのFunctionsエミュレータにはGEMINI_API_KEYを渡していないので、関数は
    // failed-precondition を返す。関数名・リージョン・認証の受け渡しが正しければ
    // その理由が画面に出る（どれかがずれていると「用意されていません」になる）。
    await signInAsNewUser(tester, profile: e2eProfile);
    await pumpFuelApp(tester);
    await pumpUntil(tester, () => find.text('きょう').evaluate().isNotEmpty);

    await tester.enterText(textFieldWithHint('食べたものを入力'), '牛丼並盛と味噌汁');
    await tester.pump();
    await tester.tap(find.byTooltip('AIでPFCを推定'));

    await pumpUntil(
      tester,
      () => find.text(kEstimateNotReadyMessage).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 60),
      reason: 'AI推定の呼び出しが関数に届いていない（関数名・リージョン・未デプロイ）',
    );
    expect(find.text('牛丼並盛と味噌汁'), findsOneWidget, reason: '失敗したら入力は残す');
  });
}
