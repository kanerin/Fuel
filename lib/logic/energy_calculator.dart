import '../models/nutrition.dart';
import '../models/user_profile.dart';

// 1日の消費カロリーと目標値の計算（docs/requirements.md 5章）。
// 画面にもFirestoreにも依存しない純粋関数にしてあり、単体テストで式を固定している。

/// 体脂肪1kgあたりのエネルギー（kcal）。
const kKcalPerKgBodyFat = 7200;

/// 1gあたりのエネルギー（kcal）。
const kKcalPerGramProtein = 4;
const kKcalPerGramFat = 9;
const kKcalPerGramCarbs = 4;

/// プロフィールから計算した1日の目安。
class NutritionTargets {
  /// 基礎代謝量（kcal）
  final int bmr;

  /// 1日の消費カロリー（kcal）。基礎代謝量×活動係数
  final int tdee;

  /// 目標（減量・増量）による1日あたりの増減（kcal）。減量ならマイナス
  final int dailyAdjustment;

  /// 1日の目標摂取カロリー（kcal）
  final int calories;

  /// 目標のたんぱく質・脂質・炭水化物（g）
  final double protein;
  final double fat;
  final double carbs;

  /// 減量の目標が基礎代謝量を下回ったため、基礎代謝量まで引き上げた
  final bool raisedToBmr;

  /// 目標摂取カロリーを手動で指定している
  final bool isCustom;

  const NutritionTargets({
    required this.bmr,
    required this.tdee,
    required this.dailyAdjustment,
    required this.calories,
    required this.protein,
    required this.fat,
    required this.carbs,
    this.raisedToBmr = false,
    this.isCustom = false,
  });

  /// 目標摂取カロリーが基礎代謝量を下回っている（手動指定のときに起こり得る）
  bool get isBelowBmr => calories < bmr;

  Nutrition get asNutrition => Nutrition(
    calories: calories.toDouble(),
    protein: protein,
    fat: fat,
    carbs: carbs,
  );
}

/// 基礎代謝量（Mifflin-St Jeor式）。
double basalMetabolicRate({
  required Sex sex,
  required double weightKg,
  required double heightCm,
  required int age,
}) {
  final base = 10 * weightKg + 6.25 * heightCm - 5 * age;
  return switch (sex) {
    Sex.male => base + 5,
    Sex.female => base - 161,
  };
}

/// 週あたりのペース（kg/週）を1日あたりのエネルギーの増減（kcal）へ換算する。
double dailyAdjustmentFor(GoalType goal, double weeklyRateKg) {
  final perDay = weeklyRateKg * kKcalPerKgBodyFat / 7;
  return switch (goal) {
    GoalType.lose => -perDay,
    GoalType.maintain => 0,
    GoalType.gain => perDay,
  };
}

/// 目標摂取カロリーとPFC比率から、PFCそれぞれの目標グラム数を出す（整数g）。
({double protein, double fat, double carbs}) macroGramsFor(
  int calories,
  PfcRatio ratio,
) => (
  protein: (calories * ratio.protein / 100 / kKcalPerGramProtein)
      .roundToDouble(),
  fat: (calories * ratio.fat / 100 / kKcalPerGramFat).roundToDouble(),
  carbs: (calories * ratio.carbs / 100 / kKcalPerGramCarbs).roundToDouble(),
);

NutritionTargets calculateTargets(UserProfile profile) {
  final bmr = basalMetabolicRate(
    sex: profile.sex,
    weightKg: profile.weightKg,
    heightCm: profile.heightCm,
    age: profile.age,
  );
  final tdee = bmr * profile.activityLevel.factor;
  final adjustment = dailyAdjustmentFor(profile.goal, profile.weeklyRateKg);

  var computed = _roundTo10(tdee + adjustment);
  var raisedToBmr = false;
  // 極端な制限を避けるため、減量の目標は基礎代謝量を下回らせない。
  // 比較は丸める前の値で行う（丸めの都合で引き上げの有無が変わらないように）。
  if (profile.goal == GoalType.lose && tdee + adjustment < bmr) {
    computed = (bmr / 10).ceil() * 10;
    raisedToBmr = true;
  }

  final custom = profile.customTargetKcal;
  final calories = custom ?? computed;
  final grams = macroGramsFor(calories, profile.pfcRatio);

  return NutritionTargets(
    bmr: bmr.round(),
    tdee: tdee.round(),
    dailyAdjustment: adjustment.round(),
    calories: calories,
    protein: grams.protein,
    fat: grams.fat,
    carbs: grams.carbs,
    raisedToBmr: custom == null && raisedToBmr,
    isCustom: custom != null,
  );
}

/// BMI（体重kg ÷ 身長m²、小数1桁）。
double bodyMassIndex({required double weightKg, required double heightCm}) {
  final m = heightCm / 100;
  return roundTo1(weightKg / (m * m));
}

/// BMIの判定（日本肥満学会の基準）。
String bmiCategory(double bmi) {
  if (bmi < 18.5) return '低体重';
  if (bmi < 25) return '普通体重';
  if (bmi < 30) return '肥満（1度）';
  if (bmi < 35) return '肥満（2度）';
  if (bmi < 40) return '肥満（3度）';
  return '肥満（4度）';
}

int _roundTo10(double value) => (value / 10).round() * 10;
