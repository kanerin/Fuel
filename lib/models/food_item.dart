import 'nutrition.dart';

// アプリ・Cloud Functions・セキュリティルールの3か所で共通の上限
// （docs/requirements.md 6章）。ここを変えるときは
// functions/src/nutrition_logic.ts と firestore.rules も揃えること。
const kMaxFoodNameLength = 60;
const kMaxFoodAmountLength = 40;
const kMaxCaloriesPerItem = 5000.0;
const kMaxMacroGramsPerItem = 500.0;

/// 食べ物1品（名前・量・栄養）。
///
/// AIの推定結果・お気に入り・最近食べたもの・記録のどれにも共通の形。
/// 記録（MealEntry）はこれに日付と食事区分を足したもの。
class FoodItem {
  final String name;

  /// 量の目安（例:「1杯（約250g）」「5個」）。空文字なら未指定。
  final String amount;

  final Nutrition nutrition;

  const FoodItem({
    required this.name,
    this.amount = '',
    required this.nutrition,
  });

  FoodItem copyWith({String? name, String? amount, Nutrition? nutrition}) =>
      FoodItem(
        name: name ?? this.name,
        amount: amount ?? this.amount,
        nutrition: nutrition ?? this.nutrition,
      );

  /// 「最近食べたもの」で同じものを1つにまとめるためのキー。
  String get identity => '${name.trim()}\u0000${amount.trim()}';

  Map<String, dynamic> toMap() => {
    'name': name,
    'amount': amount,
    ...nutrition.toMap(),
  };

  /// 文字列でない値（AIの応答の崩れ・壊れたドキュメント）は空文字として読む。
  factory FoodItem.fromMap(Map<String, dynamic> map) => FoodItem(
    name: _readString(map['name']),
    amount: _readString(map['amount']),
    nutrition: Nutrition.fromMap(map),
  );

  @override
  bool operator ==(Object other) =>
      other is FoodItem &&
      other.name == name &&
      other.amount == amount &&
      other.nutrition == nutrition;

  @override
  int get hashCode => Object.hash(name, amount, nutrition);

  @override
  String toString() => 'FoodItem($name, $amount, $nutrition)';
}

/// 入力された1品が保存できる値かを検証し、問題があれば理由を返す（問題なければnull）。
///
/// 画面のフォーム検証とテストの両方から使う。セキュリティルールでも
/// 同じ範囲を検証しているので、ここを通らない値は保存しても拒否される。
String? validateFoodItem(FoodItem item) {
  final name = item.name.trim();
  if (name.isEmpty) return '名前を入力してください';
  if (name.length > kMaxFoodNameLength) {
    return '名前は$kMaxFoodNameLength文字以内にしてください';
  }
  if (item.amount.trim().length > kMaxFoodAmountLength) {
    return '量は$kMaxFoodAmountLength文字以内にしてください';
  }
  final n = item.nutrition;
  if (n.calories < 0 || n.calories > kMaxCaloriesPerItem) {
    return 'エネルギーは0〜${kMaxCaloriesPerItem.toInt()}kcalで入力してください';
  }
  for (final grams in [n.protein, n.fat, n.carbs]) {
    if (grams < 0 || grams > kMaxMacroGramsPerItem) {
      return 'P・F・Cは0〜${kMaxMacroGramsPerItem.toInt()}gで入力してください';
    }
  }
  return null;
}

/// 保存・表示に使える形へ整える。前後の空白を落とし、長すぎる文字列は
/// 切り詰め、数値は範囲内に収めて丸める。
///
/// AIの推定結果のように「概ね正しいが範囲を少しはみ出すかもしれない」値を
/// 記録できる形にするために使う。利用者の手入力はフォームの検証
/// （[validateFoodItem]）で弾き、黙って値を書き換えない。
FoodItem normalizeFoodItem(FoodItem item) {
  final n = item.nutrition;
  return FoodItem(
    name: _clip(item.name, kMaxFoodNameLength),
    amount: _clip(item.amount, kMaxFoodAmountLength),
    nutrition: Nutrition(
      calories: _clampValue(n.calories, kMaxCaloriesPerItem),
      protein: _clampValue(n.protein, kMaxMacroGramsPerItem),
      fat: _clampValue(n.fat, kMaxMacroGramsPerItem),
      carbs: _clampValue(n.carbs, kMaxMacroGramsPerItem),
    ).rounded(),
  );
}

String _readString(Object? value) => value is String ? value.trim() : '';

String _clip(String text, int maxLength) {
  final trimmed = text.trim();
  if (trimmed.length <= maxLength) return trimmed;
  var end = maxLength;
  // 絵文字などのサロゲートペアを真ん中で切ると文字化けするので、手前で切る
  final last = trimmed.codeUnitAt(end - 1);
  if (last >= 0xD800 && last <= 0xDBFF) end--;
  return trimmed.substring(0, end);
}

double _clampValue(double value, double max) =>
    value.isFinite ? value.clamp(0, max).toDouble() : 0;

/// お気に入りに登録した食べ物。
class FavoriteFood {
  final String id;
  final FoodItem food;
  final DateTime createdAt;

  const FavoriteFood({
    required this.id,
    required this.food,
    required this.createdAt,
  });
}
