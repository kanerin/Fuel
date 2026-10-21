import 'package:cloud_firestore/cloud_firestore.dart';

import 'food_item.dart';
import 'nutrition.dart';

/// 食事区分。表示順もこの並び。
enum MealType {
  breakfast('朝食'),
  lunch('昼食'),
  dinner('夕食'),
  snack('間食');

  final String label;
  const MealType(this.label);

  static MealType fromName(Object? name) => MealType.values.firstWhere(
    (t) => t.name == name,
    orElse: () => MealType.snack,
  );

  /// 時刻から食事区分の初期値を推定する。
  ///
  /// 5〜10時台は朝食、11〜14時台は昼食、15〜16時台は間食、17〜21時台は夕食、
  /// それ以外（夜遅く・早朝）は間食。あくまで初期値で、画面で変えられる。
  static MealType suggestFor(DateTime time) {
    final h = time.hour;
    if (h >= 5 && h < 11) return MealType.breakfast;
    if (h >= 11 && h < 15) return MealType.lunch;
    if (h >= 17 && h < 22) return MealType.dinner;
    return MealType.snack;
  }
}

/// その記録がどうやって作られたか。AIの推定値かどうかを記録の一覧に
/// 明示するため（推定値であることを利用者が忘れないように）に使う。
enum EntrySource {
  ai,
  manual,
  favorite,
  recent;

  static EntrySource fromName(Object? name) => EntrySource.values.firstWhere(
    (s) => s.name == name,
    orElse: () => EntrySource.manual,
  );
}

/// 食事の記録1品。users/{uid}/meals/{id} に1品＝1ドキュメントで保存する。
class MealEntry {
  final String id;

  /// 何日の食事か（'YYYY-MM-DD'、端末のローカル日付）。
  final String dateKey;

  final MealType mealType;
  final FoodItem food;
  final EntrySource source;
  final DateTime createdAt;

  const MealEntry({
    required this.id,
    required this.dateKey,
    required this.mealType,
    required this.food,
    required this.source,
    required this.createdAt,
  });

  Nutrition get nutrition => food.nutrition;

  MealEntry copyWith({
    String? dateKey,
    MealType? mealType,
    FoodItem? food,
    EntrySource? source,
  }) => MealEntry(
    id: id,
    dateKey: dateKey ?? this.dateKey,
    mealType: mealType ?? this.mealType,
    food: food ?? this.food,
    source: source ?? this.source,
    createdAt: createdAt,
  );

  Map<String, dynamic> toMap() => {
    'date': dateKey,
    'mealType': mealType.name,
    ...food.toMap(),
    'source': source.name,
    'createdAt': Timestamp.fromDate(createdAt),
  };

  factory MealEntry.fromMap(String id, Map<String, dynamic> map) {
    final createdAt = map['createdAt'];
    final date = map['date'];
    return MealEntry(
      id: id,
      dateKey: date is String ? date : '',
      mealType: MealType.fromName(map['mealType']),
      food: FoodItem.fromMap(map),
      source: EntrySource.fromName(map['source']),
      createdAt: createdAt is Timestamp
          ? createdAt.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  @override
  String toString() => 'MealEntry($id, $dateKey, ${mealType.name}, $food)';
}
