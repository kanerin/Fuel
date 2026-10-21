import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/models/nutrition.dart';

void main() {
  const a = Nutrition(calories: 600, protein: 20, fat: 20, carbs: 85);
  const b = Nutrition(calories: 40, protein: 3, fat: 1, carbs: 5);

  test('足し算・引き算', () {
    expect(
      a + b,
      const Nutrition(calories: 640, protein: 23, fat: 21, carbs: 90),
    );
    expect(
      a - b,
      const Nutrition(calories: 560, protein: 17, fat: 19, carbs: 80),
    );
  });

  test('scaled: 量の倍率をすべての値にかける', () {
    expect(
      a.scaled(1.5),
      const Nutrition(calories: 900, protein: 30, fat: 30, carbs: 127.5),
    );
  });

  test('rounded: kcalは整数、gは小数1桁に丸める', () {
    const raw = Nutrition(
      calories: 123.456,
      protein: 1.26,
      fat: 0.04,
      carbs: 9.95,
    );

    expect(
      raw.rounded(),
      const Nutrition(calories: 123, protein: 1.3, fat: 0, carbs: 10),
    );
  });

  test('caloriesFromMacros: P×4＋F×9＋C×4', () {
    expect(a.caloriesFromMacros, 20 * 4 + 20 * 9 + 85 * 4);
  });

  group('fromMap', () {
    test('数値を読む（intもdoubleも）', () {
      expect(
        Nutrition.fromMap({
          'calories': 600,
          'protein': 20.5,
          'fat': 20,
          'carbs': 85,
        }),
        const Nutrition(calories: 600, protein: 20.5, fat: 20, carbs: 85),
      );
    });

    test('欠けている・数値でない・負・無限大の値は0（1件の壊れた記録で画面を落とさない）', () {
      expect(
        Nutrition.fromMap({
          'calories': '600',
          'protein': -1,
          'fat': double.infinity,
        }),
        Nutrition.zero,
      );
    });
  });

  test('toMap と fromMap で往復できる', () {
    expect(Nutrition.fromMap(a.toMap()), a);
  });
}
