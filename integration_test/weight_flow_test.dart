// 結合テスト: 体重を記録すると、体重の記録とプロフィールの体重（消費カロリーの
// 計算に使う値）が同じバッチで更新され、実際のセキュリティルールを通ることを確かめる。
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/e2e.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initE2E);
  tearDownAll(() => FirebaseAuth.instance.signOut());

  testWidgets('体重タブで記録 → 記録とプロフィールの体重がサーバーで更新され、目安も変わる', (tester) async {
    final uid = await signInAsNewUser(tester, profile: e2eProfile);
    await pumpFuelApp(tester);
    await pumpUntil(tester, () => find.text('体重').evaluate().isNotEmpty);

    await tester.tap(find.text('体重'));
    await settle(tester);
    await pumpUntil(tester, () => find.text('記録する').evaluate().isNotEmpty);
    // 「記録する」ボタンは一覧を読み込んでから拡大しながら現れるので、出きってから押す
    await scrollAndTap(tester, find.text('記録する'));

    await tester.enterText(find.byType(TextField), '68');
    await tester.tap(find.widgetWithText(FilledButton, '記録する'));
    await settle(tester);

    final userDoc = FirebaseFirestore.instance.collection('users').doc(uid);
    await pumpUntilAsync(tester, () async {
      final snap = await userDoc.get(const GetOptions(source: Source.server));
      final profile = snap.data()?['profile'] as Map<String, dynamic>?;
      return profile?['weightKg'] == 68;
    }, reason: 'プロフィールの体重がサーバーで更新されない（ルールで拒否された可能性）');
    final log = await userDoc
        .collection('weights')
        .doc(todayKey())
        .get(const GetOptions(source: Source.server));
    expect(log.data()?['weightKg'], 68);

    // 設定の目安は新しい体重で計算し直される（70kg→68kg で基礎代謝量は1,593→1,573kcal）
    await tester.tap(find.text('設定'));
    await settle(tester);
    await pumpUntil(
      tester,
      () => find.text('1,573 kcal').evaluate().isNotEmpty,
      reason: '体重の変更が消費カロリーの計算に反映されない',
    );
    expectNoLayoutOverflow(tester, context: '体重の記録');
  });
}
