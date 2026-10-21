import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/models/weight_log.dart';
import 'package:fuel/screens/weight_screen.dart';
import 'package:fuel/widgets/weight_line_chart.dart';

import '../helpers/fake_services.dart';
import '../helpers/fixtures.dart';
import '../helpers/pump.dart';

void main() {
  setUpAll(setUpScreenTests);

  Future<void> seedLog(TestEnv env, String dateKey, double kg) => env
      .docs
      .weights
      .doc(dateKey)
      .set({'date': dateKey, 'weightKg': kg, 'updatedAt': DateTime(2026)});

  Future<double> profileWeight(TestEnv env) async {
    final data = (await env.docs.user.get()).data()!;
    return ((data['profile'] as Map)['weightKg'] as num).toDouble();
  }

  Future<TestEnv> setUpEnv() async {
    final env = TestEnv();
    await env.seedProfile(sampleProfile); // 170cm・70kg・目標65kg
    return env;
  }

  Future<void> pumpWeight(WidgetTester tester, TestEnv env) async {
    await pumpApp(tester, env, const WeightScreen(profile: sampleProfile));
    // 「記録する」ボタンは一覧を読み込んでから拡大しながら現れるので、出きるまで待つ
    await tester.pumpAndSettle();
  }

  testWidgets('読み込みに失敗したら、無限ローディングではなくエラー表示にする', (tester) async {
    await pumpWeight(
      tester,
      TestEnv(weightsOverride: FailingWeightRepository.new),
    );

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('体重の記録を読み込めませんでした'), findsOneWidget);
    expect(find.text('記録する'), findsNothing, reason: '一覧が無いまま記録させない');
  });

  testWidgets('記録が無ければプロフィールの体重と、記録の案内を出す', (tester) async {
    await pumpWeight(tester, await setUpEnv());

    expect(find.text('70.0 kg'), findsOneWidget);
    expect(find.text('24.2'), findsOneWidget); // BMI
    expect(find.text('普通体重'), findsOneWidget);
    expect(find.textContaining('この期間の記録はありません'), findsOneWidget);
    expect(find.byType(WeightLineChart), findsNothing);
  });

  testWidgets('最新の体重・前回比・目標までの差・推移のグラフ・一覧を出す', (tester) async {
    final env = await setUpEnv();
    await seedLog(env, '2026-10-19', 70.2);
    await seedLog(env, '2026-10-21', 69.5);
    await pumpWeight(tester, env);

    expect(find.text('69.5 kg'), findsNWidgets(2)); // 現在の値と一覧
    expect(find.text('前回比 -0.7'), findsOneWidget);
    expect(find.text('-4.5 kg'), findsOneWidget); // 目標65kgまで
    expect(find.byType(WeightLineChart), findsOneWidget);
    await scrollToFind(tester, find.text('10月19日(月)'));
    expect(find.text('10月19日(月)'), findsOneWidget);
  });

  testWidgets('「記録する」で今日の体重を記録すると、プロフィールの体重も更新される', (tester) async {
    final env = await setUpEnv();
    await pumpWeight(tester, env);

    await tester.tap(find.text('記録する'));
    await tester.pumpAndSettle();
    expect(find.text('体重を記録'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, '70.0'),
      findsOneWidget,
      reason: '初期値は直近の体重',
    );

    await tester.enterText(find.byType(TextField), '69.8');
    await tester.tap(find.widgetWithText(FilledButton, '記録する'));
    await tester.pumpAndSettle();

    expect(find.text('今日の体重（69.8kg）を記録しました'), findsOneWidget);
    final saved = await env.docs.weights.doc('2026-10-21').get();
    expect(saved.data()?['weightKg'], 69.8);
    expect(await profileWeight(env), 69.8);
  });

  testWidgets('範囲外の体重は記録しない', (tester) async {
    final env = await setUpEnv();
    await pumpWeight(tester, env);

    await tester.tap(find.text('記録する'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '500');
    await tester.tap(find.widgetWithText(FilledButton, '記録する'));
    await tester.pumpAndSettle();

    expect(find.text('30〜250kgで入力してください'), findsOneWidget);
    expect((await env.docs.weights.get()).docs, isEmpty);
  });

  testWidgets('一覧の記録をタップすると、その日の値を直せる（上書き）', (tester) async {
    final env = await setUpEnv();
    await seedLog(env, '2026-10-21', 69.5);
    await pumpWeight(tester, env);

    await scrollToFind(tester, find.text('今日'));
    await tester.tap(find.text('今日'));
    await tester.pumpAndSettle();
    expect(find.text('この日は記録済みです。上書きします'), findsOneWidget);
    expect(find.widgetWithText(TextField, '69.5'), findsOneWidget);
  });

  testWidgets('削除は確認してから行い、最新を消したらひとつ前の体重に戻す', (tester) async {
    final env = await setUpEnv();
    await seedLog(env, '2026-10-20', 69.8);
    await seedLog(env, '2026-10-21', 69.5);
    await pumpWeight(tester, env);

    await scrollToFind(tester, find.byTooltip('削除').first);
    await tester.tap(find.byTooltip('削除').first);
    await tester.pumpAndSettle();
    expect(find.text('今日の記録を削除しますか？'), findsOneWidget);
    await tester.tap(find.text('削除する'));
    await tester.pumpAndSettle();

    expect((await env.docs.weights.doc('2026-10-21').get()).exists, isFalse);
    expect(await profileWeight(env), 69.8);
  });

  group('WeightDialog', () {
    testWidgets('記録済みの日を選ぶと、その日の値が入る', (tester) async {
      WeightLog? result;
      await pumpApp(
        tester,
        TestEnv(),
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showDialog<WeightLog>(
              context: context,
              builder: (_) => WeightDialog(
                initialDate: DateTime(2026, 10, 20),
                today: DateTime(2026, 10, 21),
                fallbackKg: 70,
                existing: const {'2026-10-20': 69.8},
              ),
            ),
            child: const Text('開く'),
          ),
        ),
      );
      await tester.tap(find.text('開く'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, '69.8'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '記録する'));
      await tester.pumpAndSettle();
      expect(result, const WeightLog(dateKey: '2026-10-20', weightKg: 69.8));
    });
  });
}
