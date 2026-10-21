import 'package:fuel/models/food_item.dart';
import 'package:fuel/models/meal_entry.dart';
import 'package:fuel/models/nutrition.dart';
import 'package:fuel/models/user_profile.dart';

// テストで繰り返し使うサンプルデータ。
// 値は docs/requirements.md 5章の式で手計算しやすい体格にしてある。

/// 男性・35歳・170cm・70kg・適度な運動・週0.5kgの減量・バランス。
/// BMR 1592.5 → 1593、TDEE 2468、目標 1950kcal、P98 F54 C268。
const sampleProfile = UserProfile(
  sex: Sex.male,
  age: 35,
  heightCm: 170,
  weightKg: 70,
  activityLevel: ActivityLevel.moderate,
  goal: GoalType.lose,
  weeklyRateKg: 0.5,
  pfcPreset: PfcPreset.balanced,
  pfcRatio: PfcRatio(20, 25, 55),
  targetWeightKg: 65,
);

FoodItem food(
  String name, {
  String amount = '',
  double kcal = 0,
  double p = 0,
  double f = 0,
  double c = 0,
}) => FoodItem(
  name: name,
  amount: amount,
  nutrition: Nutrition(calories: kcal, protein: p, fat: f, carbs: c),
);

MealEntry entry(
  String id, {
  String dateKey = '2026-10-21',
  MealType mealType = MealType.lunch,
  String name = '牛丼',
  String amount = '並盛',
  double kcal = 600,
  double p = 20,
  double f = 20,
  double c = 85,
  EntrySource source = EntrySource.ai,
  DateTime? createdAt,
}) => MealEntry(
  id: id,
  dateKey: dateKey,
  mealType: mealType,
  food: food(name, amount: amount, kcal: kcal, p: p, f: f, c: c),
  source: source,
  createdAt: createdAt ?? DateTime(2026, 10, 21, 12),
);
