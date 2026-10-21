import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/models/meal_entry.dart';
import 'package:fuel/screens/estimate_result_sheet.dart';
import 'package:fuel/services/nutrition_estimator.dart';

import '../helpers/fake_services.dart';
import '../helpers/pump.dart';

void main() {
  setUpAll(setUpScreenTests);

  /// シートを開くボタンだけの画面を出し、押してシートを開く。シートの戻り値を返す。
  Future<List<bool?>> openSheet(
    WidgetTester tester,
    TestEnv env, {
    NutritionEstimate estimate = sampleEstimate,
    MealType initialMealType = MealType.lunch,
  }) async {
    final results = <bool?>[];
    await pumpApp(
      tester,
      env,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async => results.add(
                await showEstimateResultSheet(
                  context,
                  estimate: estimate,
                  dateKey: '2026-10-21',
                  dateLabel: '今日 10月21日(水)',
                  initialMealType: initialMealType,
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
    return results;
  }

  testWidgets('品目・前提・合計・残り回数・推定値である旨を出す', (tester) async {
    await openSheet(tester, TestEnv());

    expect(find.text('牛丼（並盛）'), findsOneWidget);
    expect(find.text('650 kcal'), findsOneWidget);
    expect(find.text('味噌汁（1杯）'), findsOneWidget);
    expect(find.text('並盛1杯として推定しました'), findsOneWidget);
    expect(find.text('690 kcal'), findsOneWidget); // 合計
    expect(find.textContaining('今日のAI推定の残り 48回'), findsOneWidget);
    expect(find.textContaining('AIによる推定値です'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('チェックを外すと合計とボタンの品数が変わり、全部外すと追加できない', (tester) async {
    await openSheet(tester, TestEnv());

    await tester.tap(find.text('牛丼（並盛）'));
    await tester.pump();
    expect(find.text('1品を追加'), findsOneWidget);
    expect(find.text('40 kcal'), findsNWidgets(2)); // 味噌汁の行と合計

    await tester.tap(find.text('味噌汁（1杯）'));
    await tester.pump();
    final button = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('追加する'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('値を直してから追加できる（直した値で保存される）', (tester) async {
    final env = TestEnv();
    final results = await openSheet(tester, env);

    await tester.tap(find.byTooltip('「牛丼」の値を直す'));
    await tester.pumpAndSettle();
    expect(find.text('値を直す'), findsOneWidget);

    // 大盛りだったので1.5倍にする
    await tester.tap(find.text('×1.5'));
    await tester.pump();
    await tester.enterText(textFieldWithLabel('量（任意）'), '大盛');
    await tester.tap(find.text('この内容にする'));
    await tester.pumpAndSettle();

    expect(find.text('牛丼（大盛）'), findsOneWidget);
    expect(find.text('975 kcal'), findsOneWidget);

    await tester.tap(find.text('2品を追加'));
    await tester.pumpAndSettle();

    expect(results, [true]);
    final saved = await env.savedEntries();
    expect(saved.first.food.amount, '大盛');
    expect(saved.first.nutrition.calories, 975);
    expect(saved.first.nutrition.protein, 33);
  });

  testWidgets('追加の「元に戻す」で、追加した品をまとめて取り消せる', (tester) async {
    final env = TestEnv();
    await openSheet(tester, env, initialMealType: MealType.dinner);

    await tester.tap(find.text('2品を追加'));
    await tester.pumpAndSettle();
    expect(find.text('夕食に2品を追加しました'), findsOneWidget);
    expect(await env.savedEntries(), hasLength(2));

    await tester.tap(find.text('元に戻す'));
    await tester.pumpAndSettle();
    expect(await env.savedEntries(), isEmpty);
  });

  testWidgets('キャンセルはfalseを返し、何も保存しない', (tester) async {
    final env = TestEnv();
    final results = await openSheet(tester, env);

    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();

    expect(results, [false]);
    expect(await env.savedEntries(), isEmpty);
  });

  testWidgets('品目が多くてもシートの中でスクロールでき、ボタンが画面に収まる', (tester) async {
    final many = NutritionEstimate(
      items: [
        for (var i = 0; i < 15; i++)
          sampleEstimate.items.first.copyWith(name: '料理$i'),
      ],
    );
    await openSheet(tester, TestEnv(), estimate: many);

    expect(tester.takeException(), isNull);
    expect(find.text('15品を追加'), findsOneWidget);
    expect(tester.getRect(find.text('15品を追加')).bottom, lessThanOrEqualTo(780));
  });
}
