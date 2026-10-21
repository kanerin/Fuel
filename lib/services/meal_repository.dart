import '../models/food_item.dart';
import '../models/meal_entry.dart';
import 'user_docs.dart';

class MealRepository {
  MealRepository(this._docs, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final UserDocs _docs;
  final DateTime Function() _clock;

  /// 1日分の記録（記録した順）。
  ///
  /// orderByを付けると date との複合インデックスが要るので、並べ替えは手元で行う
  /// （1日の件数は多くても数十件）。
  Stream<List<MealEntry>> watchDay(String dateKey) => _docs.meals
      .where('date', isEqualTo: dateKey)
      .snapshots()
      .map(
        (snap) =>
            _sorted(snap.docs.map((d) => MealEntry.fromMap(d.id, d.data()))),
      );

  /// 期間内（両端を含む）の記録。履歴画面の集計に使う。
  Stream<List<MealEntry>> watchRange(String startKey, String endKey) => _docs
      .meals
      .where('date', isGreaterThanOrEqualTo: startKey)
      .where('date', isLessThanOrEqualTo: endKey)
      .snapshots()
      .map(
        (snap) =>
            _sorted(snap.docs.map((d) => MealEntry.fromMap(d.id, d.data()))),
      );

  /// 最近食べたもの（新しい順・同じ名前と量は1つにまとめる）。
  ///
  /// 再記録してもAIを呼ばないので、1日の推定回数の上限を消費しない。
  Future<List<FoodItem>> recentFoods({int limit = 20}) async {
    final snap = await _docs.meals
        .orderBy('createdAt', descending: true)
        .limit(100)
        .get();
    final seen = <String>{};
    final foods = <FoodItem>[];
    for (final doc in snap.docs) {
      final food = MealEntry.fromMap(doc.id, doc.data()).food;
      if (food.name.isEmpty || !seen.add(food.identity)) continue;
      foods.add(food);
      if (foods.length >= limit) break;
    }
    return foods;
  }

  /// 複数の品をまとめて記録する（AIの推定結果の「追加する」など）。
  ///
  /// 1つのバッチで書くので、一部の品だけ記録される中途半端な状態にならない。
  /// 作成した記録を返すので、呼び出し側は書き込みの完了を待たずに
  /// 「元に戻す」に使える。
  List<MealEntry> buildEntries({
    required String dateKey,
    required MealType mealType,
    required List<FoodItem> foods,
    required EntrySource source,
  }) {
    final now = _clock();
    return [
      for (var i = 0; i < foods.length; i++)
        MealEntry(
          id: _docs.meals.doc().id,
          dateKey: dateKey,
          mealType: mealType,
          food: normalizeFoodItem(foods[i]),
          source: source,
          // 同じ瞬間に複数作ると並び順が不定になるため、渡された順に1msずつずらす
          createdAt: now.add(Duration(milliseconds: i)),
        ),
    ];
  }

  /// [buildEntries] で作った記録を保存する。
  Future<void> saveEntries(List<MealEntry> entries) {
    final batch = _docs.db.batch();
    for (final e in entries) {
      batch.set(_docs.meals.doc(e.id), e.toMap());
    }
    return batch.commit();
  }

  Future<void> updateEntry(MealEntry entry) => _docs.meals
      .doc(entry.id)
      .set(entry.copyWith(food: normalizeFoodItem(entry.food)).toMap());

  Future<void> deleteEntry(MealEntry entry) =>
      _docs.meals.doc(entry.id).delete();

  /// 削除の「元に戻す」。同じIDで書き戻す。
  Future<void> restoreEntry(MealEntry entry) =>
      _docs.meals.doc(entry.id).set(entry.toMap());

  static List<MealEntry> _sorted(Iterable<MealEntry> entries) =>
      entries.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
}
