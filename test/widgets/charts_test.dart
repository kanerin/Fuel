import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/logic/daily_summary.dart';
import 'package:fuel/logic/date_keys.dart';
import 'package:fuel/models/nutrition.dart';
import 'package:fuel/models/weight_log.dart';
import 'package:fuel/widgets/calorie_bar_chart.dart';
import 'package:fuel/widgets/weight_line_chart.dart';

import '../helpers/fake_services.dart';
import '../helpers/pump.dart';

// グラフは描画内容そのものではなく、端の条件（記録なし・1件だけ・目標0・
// 全部同じ値など）で例外を出さずに描けることと、読み上げの説明を確かめる。
void main() {
  setUpAll(setUpScreenTests);

  List<DayTotal> days(List<double> kcals) => [
    for (var i = 0; i < kcals.length; i++)
      DayTotal(
        dateKey: dateKeyOf(DateTime(2026, 10, 21 - (kcals.length - 1 - i))),
        total: Nutrition(calories: kcals[i]),
        entryCount: kcals[i] > 0 ? 1 : 0,
      ),
  ];

  Future<void> pumpChart(WidgetTester tester, Widget chart) => pumpApp(
    tester,
    TestEnv(),
    Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: chart),
    ),
  );

  group('CalorieBarChart', () {
    for (final (label, values, target) in [
      ('7日・目標超えあり', <double>[1800, 0, 2200, 1950, 0, 1500, 2600], 1950),
      ('30日', List.generate(30, (i) => 1500.0 + i * 20), 1950),
      ('記録なし', List<double>.filled(7, 0), 1950),
      ('目標0', <double>[100, 200], 0),
      ('1日だけ', <double>[1800], 1950),
    ]) {
      testWidgets('例外を出さずに描ける: $label', (tester) async {
        await pumpChart(
          tester,
          CalorieBarChart(days: days(values), targetCalories: target),
        );

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('読み上げ用に期間・記録のある日数・目標を説明する', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpChart(
        tester,
        CalorieBarChart(days: days([1800, 0, 2200]), targetCalories: 1950),
      );

      expect(
        find.bySemanticsLabel('3日間の摂取カロリーのグラフ。記録のある日は2日、目標は1,950キロカロリー'),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });

  group('WeightLineChart', () {
    final start = DateTime(2026, 9, 22);
    final end = DateTime(2026, 10, 21);

    for (final (label, logs, target) in [
      (
        '複数・目標あり',
        const [
          WeightLog(dateKey: '2026-09-25', weightKg: 71.2),
          WeightLog(dateKey: '2026-10-10', weightKg: 70.1),
          WeightLog(dateKey: '2026-10-21', weightKg: 69.5),
        ],
        65.0,
      ),
      ('1件だけ', const [WeightLog(dateKey: '2026-10-21', weightKg: 69.5)], null),
      (
        '全部同じ値',
        const [
          WeightLog(dateKey: '2026-10-01', weightKg: 70),
          WeightLog(dateKey: '2026-10-21', weightKg: 70),
        ],
        null,
      ),
      ('記録なし', const <WeightLog>[], 65.0),
    ]) {
      testWidgets('例外を出さずに描ける: $label', (tester) async {
        await pumpChart(
          tester,
          WeightLineChart(logs: logs, start: start, end: end, targetKg: target),
        );

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('期間の始まりと終わりが同じ日でも描ける', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpChart(
        tester,
        WeightLineChart(
          logs: const [WeightLog(dateKey: '2026-10-21', weightKg: 69.5)],
          start: end,
          end: end,
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel('体重の推移のグラフ。記録は1件'), findsOneWidget);
      semantics.dispose();
    });
  });
}
