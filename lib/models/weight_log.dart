/// 体重の記録。users/{uid}/weights/{YYYY-MM-DD} に1日1件で保存する
/// （ドキュメントIDを日付にしているので、同じ日に入れ直すと上書きになる）。
class WeightLog {
  final String dateKey;
  final double weightKg;

  const WeightLog({required this.dateKey, required this.weightKg});

  Map<String, dynamic> toMap() => {'date': dateKey, 'weightKg': weightKg};

  /// 壊れたドキュメントはnull（一覧から除外する）。
  static WeightLog? fromMap(String id, Map<String, dynamic> map) {
    final weight = map['weightKg'];
    final date = map['date'];
    if (weight is! num || !weight.isFinite || weight <= 0) return null;
    return WeightLog(
      dateKey: date is String ? date : id,
      weightKg: weight.toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WeightLog &&
      other.dateKey == dateKey &&
      other.weightKg == weightKg;

  @override
  int get hashCode => Object.hash(dateKey, weightKg);

  @override
  String toString() => 'WeightLog($dateKey, ${weightKg}kg)';
}
