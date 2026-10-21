import '../models/meal_entry.dart';
import '../models/nutrition.dart';
import 'energy_calculator.dart';

/// 1日分の記録の集計（きょう画面）。
class DailySummary {
  /// 食事区分ごと・記録した順の一覧。
  final Map<MealType, List<MealEntry>> byMeal;
  final Nutrition total;

  DailySummary._(this.byMeal, this.total);

  factory DailySummary.of(List<MealEntry> entries) {
    final sorted = [...entries]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final byMeal = {for (final t in MealType.values) t: <MealEntry>[]};
    var total = Nutrition.zero;
    for (final e in sorted) {
      byMeal[e.mealType]!.add(e);
      total += e.nutrition;
    }
    return DailySummary._(byMeal, total);
  }

  bool get isEmpty => byMeal.values.every((list) => list.isEmpty);

  List<MealEntry> entriesFor(MealType type) => byMeal[type]!;

  Nutrition totalFor(MealType type) =>
      byMeal[type]!.fold(Nutrition.zero, (sum, e) => sum + e.nutrition);
}

/// 目標に対する割合（0〜）。目標が0以下なら0。
double progressOf(double consumed, double target) =>
    target > 0 ? consumed / target : 0;

/// 実際に食べたもののPFC比率（%）。
///
/// エネルギー（kcal）の値ではなく三大栄養素から計算する。kcalには
/// アルコールなどPFC以外の分も含まれ得るため、比率の分母に使うと
/// 合計が100%にならない。
class PfcShare {
  final double protein;
  final double fat;
  final double carbs;

  const PfcShare(this.protein, this.fat, this.carbs);

  /// 三大栄養素がすべて0ならnull（比率を出せない）。
  static PfcShare? of(Nutrition n) {
    final p = n.protein * kKcalPerGramProtein;
    final f = n.fat * kKcalPerGramFat;
    final c = n.carbs * kKcalPerGramCarbs;
    final sum = p + f + c;
    if (sum <= 0) return null;
    return PfcShare(p / sum * 100, f / sum * 100, c / sum * 100);
  }
}

/// 1日の合計（履歴画面の1行・グラフの1本）。
class DayTotal {
  final String dateKey;
  final Nutrition total;
  final int entryCount;

  const DayTotal({
    required this.dateKey,
    required this.total,
    required this.entryCount,
  });

  bool get hasRecords => entryCount > 0;
}

/// 期間の集計（履歴画面）。
class PeriodSummary {
  /// 期間内のすべての日（記録の無い日も含む）、古い順。
  final List<DayTotal> days;

  const PeriodSummary(this.days);

  /// 記録のある日の数。
  int get recordedDays => days.where((d) => d.hasRecords).length;

  /// 記録のある日だけの1日あたりの平均。
  ///
  /// 記録を付け忘れた日（0kcal）を含めると平均が実態より下がって
  /// 「まだ食べられる」と誤解させるため、記録の無い日は除く。
  Nutrition? get average {
    final recorded = days.where((d) => d.hasRecords).toList();
    if (recorded.isEmpty) return null;
    final sum = recorded.fold(Nutrition.zero, (s, d) => s + d.total);
    return sum.scaled(1 / recorded.length);
  }

  /// 記録のある日のうち、目標カロリー以内に収まった日の数。
  int daysWithinTarget(int targetCalories) => days
      .where((d) => d.hasRecords && d.total.calories <= targetCalories)
      .length;
}

/// [dateKeys]（古い順）の各日について記録を集計する。範囲外の記録は無視する。
PeriodSummary summarizePeriod(List<String> dateKeys, List<MealEntry> entries) {
  final totals = {for (final k in dateKeys) k: Nutrition.zero};
  final counts = {for (final k in dateKeys) k: 0};
  for (final e in entries) {
    if (!totals.containsKey(e.dateKey)) continue;
    totals[e.dateKey] = totals[e.dateKey]! + e.nutrition;
    counts[e.dateKey] = counts[e.dateKey]! + 1;
  }
  return PeriodSummary([
    for (final k in dateKeys)
      DayTotal(dateKey: k, total: totals[k]!, entryCount: counts[k]!),
  ]);
}
