import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/models/meal_entry.dart';
import 'package:fuel/screens/history_screen.dart';
import 'package:fuel/services/meal_repository.dart';
import 'package:fuel/widgets/calorie_bar_chart.dart';

import '../helpers/fake_services.dart';
import '../helpers/fixtures.dart';
import '../helpers/pump.dart';

class _PendingMealRepository extends MealRepository {
  _PendingMealRepository(super.docs);

  @override
  Stream<List<MealEntry>> watchRange(String startKey, String endKey) =>
      StreamController<List<MealEntry>>().stream;
}

void main() {
  setUpAll(setUpScreenTests);

  Future<List<DateTime>> pumpHistory(WidgetTester tester, TestEnv env) async {
    final opened = <DateTime>[];
    await pumpApp(
      tester,
      env,
      HistoryScreen(profile: sampleProfile, onOpenDay: opened.add),
    );
    return opened;
  }

  testWidgets('データが来る前はローディング表示', (tester) async {
    await pumpHistory(
      tester,
      TestEnv(mealsOverride: _PendingMealRepository.new),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('読み込みに失敗したら、無限ローディングではなくエラー表示にする', (tester) async {
    await pumpHistory(
      tester,
      TestEnv(mealsOverride: FailingMealRepository.new),
    );

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('履歴を読み込めませんでした'), findsOneWidget);
  });

  testWidgets('記録が無ければ案内を出す', (tester) async {
    await pumpHistory(tester, TestEnv());

    expect(find.text('この期間の記録はまだありません'), findsOneWidget);
    expect(find.text('記録を付けると、ここに1日あたりの平均が出ます'), findsOneWidget);
    expect(find.byType(CalorieBarChart), findsOneWidget);
  });

  testWidgets('平均は記録のある日だけで出し、目標以内の日を数える', (tester) async {
    final env = TestEnv();
    // 10/21（今日）1800kcal、10/19 2200kcal、10/20は記録なし
    await env.seedEntry(
      entry('a', dateKey: '2026-10-21', kcal: 1800, p: 80, f: 50, c: 250),
    );
    await env.seedEntry(
      entry('b', dateKey: '2026-10-19', kcal: 2200, p: 100, f: 70, c: 290),
    );
    // 期間外（8日前）は7日表示には入らない
    await env.seedEntry(entry('c', dateKey: '2026-10-13', kcal: 5000));
    await pumpHistory(tester, env);

    expect(find.text('1日あたりの平均（記録のある2日）'), findsOneWidget);
    expect(find.text('2,000 kcal'), findsOneWidget);
    expect(find.text('目標以内の日: 1 / 2日（記録のある日）'), findsOneWidget);
    expect(find.text('90 / 98 g'), findsOneWidget); // たんぱく質の平均
    expect(find.text('PFCバランス'), findsOneWidget);
  });

  testWidgets('30日に切り替えると期間が広がる', (tester) async {
    final env = TestEnv();
    await env.seedEntry(entry('a', dateKey: '2026-10-21', kcal: 1800));
    await env.seedEntry(entry('c', dateKey: '2026-10-01', kcal: 1600));
    await pumpHistory(tester, env);
    expect(find.text('1日あたりの平均（記録のある1日）'), findsOneWidget);

    await tester.tap(find.text('30日'));
    await tester.pumpAndSettle();

    expect(find.text('1日あたりの平均（記録のある2日）'), findsOneWidget);
    expect(find.text('1,700 kcal'), findsOneWidget);
  });

  testWidgets('日ごとの一覧をタップすると、その日を開く', (tester) async {
    final env = TestEnv();
    await env.seedEntry(entry('a', dateKey: '2026-10-20', kcal: 1800));
    final opened = await pumpHistory(tester, env);

    await scrollToFind(tester, find.text('昨日'));
    await tester.tap(find.text('昨日'));

    expect(opened, [DateTime(2026, 10, 20)]);
  });

  testWidgets('30日表示でもグラフのラベルがはみ出さない', (tester) async {
    final env = TestEnv();
    for (var d = 1; d <= 21; d++) {
      final key = '2026-10-${d.toString().padLeft(2, '0')}';
      await env.seedEntry(entry('e$d', dateKey: key, kcal: 1500.0 + d * 30));
    }
    await pumpHistory(tester, env);
    await tester.tap(find.text('30日'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
