import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/logic/energy_calculator.dart';
import 'package:fuel/models/user_profile.dart';

import '../helpers/fixtures.dart';

// 消費カロリー・目標値の式（docs/requirements.md 5章）を固定するテスト。
// 期待値はすべて式から手計算した値。式を変えるときは要件定義も直すこと。
void main() {
  group('basalMetabolicRate（Mifflin-St Jeor式）', () {
    test('男性: 10×体重 + 6.25×身長 − 5×年齢 + 5', () {
      expect(
        basalMetabolicRate(sex: Sex.male, weightKg: 70, heightCm: 170, age: 35),
        1592.5,
      );
    });

    test('女性: 10×体重 + 6.25×身長 − 5×年齢 − 161', () {
      expect(
        basalMetabolicRate(
          sex: Sex.female,
          weightKg: 55,
          heightCm: 158,
          age: 30,
        ),
        1226.5,
      );
    });
  });

  group('dailyAdjustmentFor', () {
    test('体脂肪1kg=7200kcalとして週のペースを1日あたりに換算する', () {
      expect(dailyAdjustmentFor(GoalType.lose, 0.5), closeTo(-514.29, 0.01));
      expect(dailyAdjustmentFor(GoalType.gain, 0.25), closeTo(257.14, 0.01));
    });

    test('維持は増減なし', () {
      expect(dailyAdjustmentFor(GoalType.maintain, 0), 0);
    });
  });

  group('calculateTargets', () {
    test('減量: TDEEから1日あたりの減量分を引き、10kcal単位に丸める', () {
      final t = calculateTargets(sampleProfile);

      expect(t.bmr, 1593); // 1592.5
      expect(t.tdee, 2468); // 1592.5 × 1.55 = 2468.375
      expect(t.dailyAdjustment, -514);
      expect(t.calories, 1950); // 2468.375 − 514.29 = 1954.09
      expect(t.raisedToBmr, isFalse);
      expect(t.isCustom, isFalse);
    });

    test('PFCの目標gは目標kcal×比率÷(4,9,4)', () {
      final t = calculateTargets(sampleProfile);

      expect(t.protein, 98); // 1950 × 20% ÷ 4 = 97.5
      expect(t.fat, 54); // 1950 × 25% ÷ 9 = 54.2
      expect(t.carbs, 268); // 1950 × 55% ÷ 4 = 268.1
    });

    test('維持: 目標はTDEEそのもの（10kcal単位）', () {
      final t = calculateTargets(
        sampleProfile.copyWith(goal: GoalType.maintain, weeklyRateKg: 0),
      );

      expect(t.dailyAdjustment, 0);
      expect(t.calories, 2470);
    });

    test('増量: TDEEに1日あたりの増量分を足す', () {
      final t = calculateTargets(
        sampleProfile.copyWith(goal: GoalType.gain, weeklyRateKg: 0.25),
      );

      expect(t.dailyAdjustment, 257);
      expect(t.calories, 2730); // 2468.375 + 257.14 = 2725.5
    });

    test('活動係数が大きいほど消費カロリーも大きい', () {
      final tdees = [
        for (final level in ActivityLevel.values)
          calculateTargets(sampleProfile.copyWith(activityLevel: level)).tdee,
      ];

      expect(tdees, [1911, 2190, 2468, 2747, 3026]);
    });

    test('減量の目標が基礎代謝量を下回る場合は、基礎代謝量まで引き上げる', () {
      // 女性・30歳・158cm・55kg・ほとんど運動しない・週0.75kg
      // TDEE 1471.8 − 771.4 = 700kcal は基礎代謝量 1226.5 を大きく下回る
      final t = calculateTargets(
        const UserProfile(
          sex: Sex.female,
          age: 30,
          heightCm: 158,
          weightKg: 55,
          activityLevel: ActivityLevel.sedentary,
          goal: GoalType.lose,
          weeklyRateKg: 0.75,
          pfcPreset: PfcPreset.balanced,
          pfcRatio: PfcRatio(20, 25, 55),
        ),
      );

      expect(t.bmr, 1227);
      expect(t.calories, 1230); // 1226.5 を10kcal単位で切り上げ
      expect(t.raisedToBmr, isTrue);
      expect(t.isBelowBmr, isFalse);
    });

    test('目標カロリーを手動で指定した場合はそれを優先する', () {
      final t = calculateTargets(
        sampleProfile.copyWith(customTargetKcal: () => 1800),
      );

      expect(t.calories, 1800);
      expect(t.isCustom, isTrue);
      expect(t.protein, 90); // 1800 × 20% ÷ 4
      expect(t.fat, 50); // 1800 × 25% ÷ 9
      expect(t.carbs, 248); // 1800 × 55% ÷ 4 = 247.5
    });

    test('手動指定は基礎代謝量を下回っても尊重し、下回っていることだけ知らせる', () {
      final t = calculateTargets(
        sampleProfile.copyWith(customTargetKcal: () => 1200),
      );

      expect(t.calories, 1200);
      expect(t.raisedToBmr, isFalse);
      expect(t.isBelowBmr, isTrue);
    });

    test('PFC比率が変われば目標gも変わる（高たんぱく 30:25:45）', () {
      final t = calculateTargets(
        sampleProfile.copyWith(
          pfcPreset: PfcPreset.highProtein,
          pfcRatio: PfcPreset.highProtein.ratio,
        ),
      );

      expect(t.protein, 146); // 1950 × 30% ÷ 4 = 146.25
      expect(t.fat, 54);
      expect(t.carbs, 219); // 1950 × 45% ÷ 4 = 219.4
    });

    test('目標gから戻したエネルギーは目標kcalとほぼ一致する', () {
      final t = calculateTargets(sampleProfile);
      final fromMacros = t.protein * 4 + t.fat * 9 + t.carbs * 4;

      expect(fromMacros, closeTo(t.calories, 15));
    });
  });

  group('bodyMassIndex', () {
    test('体重 ÷ 身長(m)² を小数1桁で', () {
      expect(bodyMassIndex(weightKg: 70, heightCm: 170), 24.2);
    });

    test('判定は日本肥満学会の基準', () {
      expect(bmiCategory(18.4), '低体重');
      expect(bmiCategory(18.5), '普通体重');
      expect(bmiCategory(24.9), '普通体重');
      expect(bmiCategory(25), '肥満（1度）');
      expect(bmiCategory(35), '肥満（3度）');
      expect(bmiCategory(42), '肥満（4度）');
    });
  });
}
