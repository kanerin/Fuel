// エネルギーと三大栄養素（PFC）の組。
//
// 記録1品・1日の合計・目標値のどれにも同じ形を使う。足し算・倍率の計算を
// このクラスに閉じ込めておくと、集計や「量を1.5倍に」といった操作を
// 画面側で個別に書かずに済む。
class Nutrition {
  /// エネルギー（kcal）
  final double calories;

  /// たんぱく質（g）
  final double protein;

  /// 脂質（g）
  final double fat;

  /// 炭水化物（g）
  final double carbs;

  const Nutrition({
    this.calories = 0,
    this.protein = 0,
    this.fat = 0,
    this.carbs = 0,
  });

  static const zero = Nutrition();

  Nutrition operator +(Nutrition other) => Nutrition(
    calories: calories + other.calories,
    protein: protein + other.protein,
    fat: fat + other.fat,
    carbs: carbs + other.carbs,
  );

  Nutrition operator -(Nutrition other) => Nutrition(
    calories: calories - other.calories,
    protein: protein - other.protein,
    fat: fat - other.fat,
    carbs: carbs - other.carbs,
  );

  /// 量を [factor] 倍した値（「大盛りにした」「半分残した」など）。
  Nutrition scaled(double factor) => Nutrition(
    calories: calories * factor,
    protein: protein * factor,
    fat: fat * factor,
    carbs: carbs * factor,
  );

  /// 保存用に丸めた値。kcalは整数、gは小数1桁。
  ///
  /// 倍率をかけた結果（例: 123.456kcal）をそのまま保存すると、
  /// 表示と合計がずれて見えるため、保存の直前に必ずここを通す。
  Nutrition rounded() => Nutrition(
    calories: calories.roundToDouble(),
    protein: roundTo1(protein),
    fat: roundTo1(fat),
    carbs: roundTo1(carbs),
  );

  /// 三大栄養素から計算したエネルギー（P×4＋F×9＋C×4）。
  double get caloriesFromMacros => protein * 4 + fat * 9 + carbs * 4;

  bool get isZero => calories == 0 && protein == 0 && fat == 0 && carbs == 0;

  Map<String, dynamic> toMap() => {
    'calories': calories,
    'protein': protein,
    'fat': fat,
    'carbs': carbs,
  };

  /// Firestore・Cloud Functionsから受け取ったマップを読む。
  /// 欠けている・数値でない値は0として扱う（壊れた1件で画面全体を落とさない）。
  factory Nutrition.fromMap(Map<String, dynamic> map) => Nutrition(
    calories: readNonNegative(map['calories']),
    protein: readNonNegative(map['protein']),
    fat: readNonNegative(map['fat']),
    carbs: readNonNegative(map['carbs']),
  );

  @override
  bool operator ==(Object other) =>
      other is Nutrition &&
      other.calories == calories &&
      other.protein == protein &&
      other.fat == fat &&
      other.carbs == carbs;

  @override
  int get hashCode => Object.hash(calories, protein, fat, carbs);

  @override
  String toString() => 'Nutrition(${calories}kcal, P$protein, F$fat, C$carbs)';
}

/// 小数1桁に丸める。
double roundTo1(double value) => (value * 10).roundToDouble() / 10;

/// 有限の0以上の数値として読む。読めなければ0。
double readNonNegative(Object? value) {
  if (value is num && value.isFinite && value >= 0) return value.toDouble();
  return 0;
}
