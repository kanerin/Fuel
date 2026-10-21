import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/logic/energy_calculator.dart';
import 'package:fuel/models/nutrition.dart';
import 'package:fuel/theme/app_theme.dart';
import 'package:fuel/widgets/nutrition_summary_card.dart';

import '../helpers/fake_services.dart';
import '../helpers/fixtures.dart';
import '../helpers/pump.dart';

void main() {
  setUpAll(setUpScreenTests);

  final targets = calculateTargets(sampleProfile); // 1950kcal・P98 F54 C268

  Future<void> pumpCard(WidgetTester tester, Nutrition consumed) => pumpApp(
    tester,
    TestEnv(),
    Scaffold(
      body: NutritionSummaryCard(consumed: consumed, targets: targets),
    ),
  );

  testWidgets('目標内なら「あと」と残りのkcal、目標比を出す', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpCard(
      tester,
      const Nutrition(calories: 975, protein: 49, fat: 27, carbs: 134),
    );

    expect(find.text('あと'), findsOneWidget);
    expect(find.text('975 kcal'), findsNWidgets(2)); // 食べた・あと
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('49 / 98 g'), findsOneWidget);
    expect(find.bySemanticsLabel('目標カロリーの50%'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('超えたら「超過」と超えた分を赤で出す', (tester) async {
    await pumpCard(tester, const Nutrition(calories: 2100, protein: 120));

    expect(find.text('超過'), findsOneWidget);
    expect(find.text('150 kcal'), findsOneWidget);
    expect(find.text('108%'), findsOneWidget);
    final over = tester.widget<Text>(find.text('120 / 98 g'));
    expect(over.style?.color, AppColors.over);
  });

  testWidgets('MacroText は P・F・C を1行で出す', (tester) async {
    await pumpApp(
      tester,
      TestEnv(),
      const Scaffold(
        body: MacroText(Nutrition(protein: 22, fat: 21.5, carbs: 90)),
      ),
    );

    expect(find.textContaining('P 22'), findsOneWidget);
    expect(find.textContaining('F 21.5'), findsOneWidget);
    expect(find.textContaining('C 90'), findsOneWidget);
  });
}
