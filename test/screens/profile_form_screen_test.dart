import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/models/user_profile.dart';
import 'package:fuel/screens/profile_form_screen.dart';

import '../helpers/fake_services.dart';
import '../helpers/fixtures.dart';
import '../helpers/pump.dart';

void main() {
  setUpAll(setUpScreenTests);

  // watchProfile().first はウィジェットテストの偽の時計の中では値が届かず
  // 待ち続けてしまうので、getで読む
  Future<UserProfile?> savedProfile(TestEnv env) async =>
      UserProfile.fromMap((await env.docs.user.get()).data()?['profile']);

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    // 直前の入力（enterText）が予約した「カーソルを画面内へ」のスクロールを
    // 先に済ませる。後から走ると、せっかく移動した位置から入力欄へ戻されてしまう
    await tester.pumpAndSettle();
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  /// 「はじめに」でサンプルと同じ体格（男性・35歳・170cm・70kg・適度な運動）を入力する。
  Future<void> fillBasics(WidgetTester tester) async {
    await scrollTo(tester, find.text('男性'));
    await tester.tap(find.text('男性'));
    await tester.enterText(textFieldWithLabel('年齢'), '35');
    await tester.enterText(textFieldWithLabel('身長'), '170');
    await tester.enterText(textFieldWithLabel('体重'), '70');
    await scrollTo(tester, find.text('適度な運動'));
    await tester.tap(find.text('適度な運動'));
    await tester.pumpAndSettle();
  }

  group('はじめに（初回の入力）', () {
    testWidgets('入力するとその場で消費カロリーと目標を計算して見せる', (tester) async {
      final env = TestEnv();
      await pumpApp(tester, env, const ProfileFormScreen());

      await scrollTo(tester, find.text('1日の目安'));
      expect(find.text('すべて入力すると、ここに計算結果が表示されます'), findsOneWidget);

      await fillBasics(tester);
      await scrollTo(tester, find.text('1日の目安'));

      // 既定は「減量・ふつう（週0.5kg）・バランス」
      expect(find.text('1,593 kcal'), findsOneWidget); // 基礎代謝量
      expect(find.text('2,468 kcal'), findsOneWidget); // 消費カロリー
      expect(find.text('1,950 kcal'), findsOneWidget); // 目標摂取カロリー
      expect(find.text('98 g'), findsOneWidget);
      expect(find.text('54 g'), findsOneWidget);
      expect(find.text('268 g'), findsOneWidget);
    });

    testWidgets('「はじめる」でプロフィールと、今日の体重の記録を保存する', (tester) async {
      final env = TestEnv();
      await pumpApp(tester, env, const ProfileFormScreen());
      await fillBasics(tester);
      await scrollTo(tester, textFieldWithLabel('目標体重（任意）'));
      await tester.enterText(textFieldWithLabel('目標体重（任意）'), '65');

      await scrollTo(tester, find.text('はじめる'));
      await tester.tap(find.text('はじめる'));
      await tester.pumpAndSettle();

      expect(await savedProfile(env), sampleProfile);
      final log = await env.docs.weights.doc('2026-10-21').get();
      expect(log.data()?['weightKg'], 70);
    });

    testWidgets('性別と運動の頻度を選ばずに「はじめる」を押すと、理由を出して保存しない', (tester) async {
      final env = TestEnv();
      await pumpApp(tester, env, const ProfileFormScreen());
      await tester.enterText(textFieldWithLabel('年齢'), '35');

      await scrollTo(tester, find.text('はじめる'));
      await tester.tap(find.text('はじめる'));
      await tester.pumpAndSettle();

      expect(find.text('入力内容を確認してください（赤字の項目）'), findsOneWidget);
      expect(find.text('運動の頻度を選んでください'), findsOneWidget);
      await scrollTo(tester, find.text('性別を選んでください'));
      expect(find.text('性別を選んでください'), findsOneWidget);
      expect(await savedProfile(env), isNull);
    });

    testWidgets('範囲外の値は欄の下に理由を出す', (tester) async {
      final env = TestEnv();
      await pumpApp(tester, env, const ProfileFormScreen());
      await fillBasics(tester);
      await scrollTo(tester, textFieldWithLabel('年齢'));
      await tester.enterText(textFieldWithLabel('年齢'), '8');
      await tester.enterText(textFieldWithLabel('身長'), '170.5cm');

      await scrollTo(tester, find.text('はじめる'));
      await tester.tap(find.text('はじめる'));
      await tester.pumpAndSettle();
      await scrollTo(tester, textFieldWithLabel('年齢'));

      expect(find.text('15〜100'), findsOneWidget);
      expect(find.text('数値で入力'), findsOneWidget);
      expect(await savedProfile(env), isNull);
    });

    testWidgets('維持を選ぶとペースの選択肢が消え、目標は消費カロリーと同じになる', (tester) async {
      final env = TestEnv();
      await pumpApp(tester, env, const ProfileFormScreen());
      await fillBasics(tester);

      await scrollTo(tester, find.text('維持'));
      await tester.tap(find.text('維持'));
      await tester.pumpAndSettle();
      expect(find.text('ふつう 0.5kg'), findsNothing);

      await scrollTo(tester, find.text('1日の目安'));
      expect(find.text('2,470 kcal'), findsOneWidget);
      expect(find.text('消費カロリーと同じ（維持）'), findsOneWidget);
    });

    testWidgets('カスタムのPFC比率は合計100%でないと保存できない', (tester) async {
      final env = TestEnv();
      await pumpApp(tester, env, const ProfileFormScreen());
      await fillBasics(tester);

      await scrollTo(tester, find.text('カスタム'));
      await tester.tap(find.text('カスタム'));
      await tester.pumpAndSettle();
      // 直前のプリセット（バランス 20:25:55）から調整できる
      expect(find.text('合計 100%'), findsOneWidget);

      await scrollTo(tester, textFieldWithLabel('たんぱく質'));
      await tester.enterText(textFieldWithLabel('たんぱく質'), '30');
      await tester.pump();
      expect(find.text('合計 110%（100%にしてください）'), findsOneWidget);

      await scrollTo(tester, find.text('はじめる'));
      await tester.tap(find.text('はじめる'));
      await tester.pumpAndSettle();
      expect(await savedProfile(env), isNull);

      await scrollTo(tester, textFieldWithLabel('炭水化物'));
      await tester.enterText(textFieldWithLabel('炭水化物'), '45');
      await scrollTo(tester, find.text('はじめる'));
      await tester.tap(find.text('はじめる'));
      await tester.pumpAndSettle();

      final saved = await savedProfile(env);
      expect(saved?.pfcPreset, PfcPreset.custom);
      expect(saved?.pfcRatio, const PfcRatio(30, 25, 45));
    });

    testWidgets('目標カロリーを自分で決めると、その値を目標にする', (tester) async {
      final env = TestEnv();
      await pumpApp(tester, env, const ProfileFormScreen());
      await fillBasics(tester);

      await scrollTo(tester, find.text('目標カロリーを自分で決める'));
      await tester.tap(find.text('目標カロリーを自分で決める'));
      await tester.pumpAndSettle();
      await tester.enterText(textFieldWithLabel('1日の目標'), '1800');
      await scrollTo(tester, find.text('1日の目安'));

      expect(find.text('1,800 kcal'), findsOneWidget);
      expect(find.text('手動で設定した値'), findsOneWidget);
    });
  });

  group('編集（設定画面から）', () {
    testWidgets('保存済みの値が入っていて、変えた体重はその日の記録にもなる', (tester) async {
      final env = TestEnv();
      await env.seedProfile(sampleProfile);
      await pumpApp(
        tester,
        env,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const ProfileFormScreen(initial: sampleProfile),
                  ),
                ),
                child: const Text('開く'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('開く'));
      await tester.pumpAndSettle();

      expect(find.text('プロフィールと目標'), findsOneWidget);
      expect(find.widgetWithText(TextField, '35'), findsOneWidget);

      await tester.enterText(textFieldWithLabel('体重'), '68.5');
      await scrollTo(tester, find.text('保存する'));
      await tester.tap(find.text('保存する'));
      await tester.pumpAndSettle();

      expect(find.text('開く'), findsOneWidget, reason: '保存したら閉じる');
      expect(find.text('保存しました'), findsOneWidget);
      expect((await savedProfile(env))?.weightKg, 68.5);
      final log = await env.docs.weights.doc('2026-10-21').get();
      expect(log.data()?['weightKg'], 68.5);
    });

    testWidgets('体重を変えなければ体重の記録は作らない', (tester) async {
      final env = TestEnv();
      await env.seedProfile(sampleProfile);
      await pumpApp(
        tester,
        env,
        const ProfileFormScreen(initial: sampleProfile),
      );

      await tester.enterText(textFieldWithLabel('年齢'), '36');
      await scrollTo(tester, find.text('保存する'));
      await tester.tap(find.text('保存する'));
      await tester.pumpAndSettle();

      expect((await savedProfile(env))?.age, 36);
      expect((await env.docs.weights.get()).docs, isEmpty);
    });
  });
}
