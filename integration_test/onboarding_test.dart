// 結合テスト: 初めての利用者が「はじめに」でプロフィールを入力するとホームへ進み、
// 入力した値が実際のセキュリティルールを通ってFirestoreに保存されることを確かめる。
// （ルールはプロフィールの型・範囲を厳しく検証しているので、アプリが保存する
// 値の型——整数か小数か——がずれるとここで拒否される）
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/models/user_profile.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/e2e.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initE2E);
  tearDownAll(() => FirebaseAuth.instance.signOut());

  testWidgets('はじめに → 入力 → はじめる でホームへ進み、プロフィールと体重の記録が保存される', (tester) async {
    final uid = await signInAsNewUser(tester);
    await pumpFuelApp(tester);

    await pumpUntil(
      tester,
      () => find.text('はじめに').evaluate().isNotEmpty,
      reason: 'プロフィール未入力なのに「はじめに」が出ない',
    );

    await scrollAndTap(tester, find.text('女性'));
    await tester.enterText(textFieldWithLabel('年齢'), '30');
    await tester.enterText(textFieldWithLabel('身長'), '158.5');
    await tester.enterText(textFieldWithLabel('体重'), '55');
    await scrollAndTap(tester, find.text('軽い運動'));
    await scrollAndTap(tester, find.text('維持'));
    await scrollAndTap(tester, find.text('はじめる'));

    await pumpUntil(
      tester,
      () => find.text('きょう').evaluate().isNotEmpty,
      reason: 'プロフィールを保存してもホームへ切り替わらない（ルールで拒否された可能性）',
    );

    final userDoc = FirebaseFirestore.instance.collection('users').doc(uid);
    await pumpUntilAsync(tester, () async {
      final snap = await userDoc.get(const GetOptions(source: Source.server));
      return snap.data()?['profile'] != null;
    }, reason: 'プロフィールがサーバーに保存されない');
    final saved = UserProfile.fromMap((await userDoc.get()).data()!['profile']);
    expect(saved?.sex, Sex.female);
    expect(saved?.heightCm, 158.5);
    expect(saved?.goal, GoalType.maintain);

    final weight = await userDoc
        .collection('weights')
        .doc(todayKey())
        .get(const GetOptions(source: Source.server));
    expect(weight.data()?['weightKg'], 55);
    expectNoLayoutOverflow(tester, context: 'はじめに→ホーム');
  });
}
