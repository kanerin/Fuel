import '../models/nutrition.dart';
import '../models/weight_log.dart';
import 'profile_repository.dart';
import 'user_docs.dart';

class WeightRepository {
  WeightRepository(this._docs);

  final UserDocs _docs;

  /// 体重の記録（新しい日付順）。
  Stream<List<WeightLog>> watchLogs({int limit = 400}) => _docs.weights
      .orderBy('date', descending: true)
      .limit(limit)
      .snapshots()
      .map(
        (snap) => [
          for (final doc in snap.docs) ?WeightLog.fromMap(doc.id, doc.data()),
        ],
      );

  /// その日の体重を記録する（同じ日に入れ直したら上書き）。
  ///
  /// [current] は画面に表示中の記録の一覧。記録した日が最新なら、同じバッチで
  /// プロフィールの体重（消費カロリーの計算に使う値）も更新する。
  /// 「最新かどうか」を問い合わせ直さずに手元の一覧で判定するのは、
  /// オフラインでも書き込みを待たずに整合した状態を作れるようにするため。
  Future<void> saveLog(
    String dateKey,
    double weightKg, {
    required List<WeightLog> current,
  }) {
    final log = WeightLog(dateKey: dateKey, weightKg: roundTo1(weightKg));
    final batch = _docs.db.batch()
      ..set(_docs.weights.doc(dateKey), weightLogData(log));
    final latest = latestWeightAfterSave(current, log);
    if (latest != null) {
      batch.update(_docs.user, {'profile.weightKg': latest});
    }
    return batch.commit();
  }

  /// 記録を削除する。最新の記録を消した場合は、ひとつ前の記録を
  /// プロフィールの体重へ戻す。
  Future<void> deleteLog(String dateKey, {required List<WeightLog> current}) {
    final batch = _docs.db.batch()..delete(_docs.weights.doc(dateKey));
    final latest = latestWeightAfterDelete(current, dateKey);
    if (latest != null) {
      batch.update(_docs.user, {'profile.weightKg': latest});
    }
    return batch.commit();
  }
}

/// [log] を保存したあとに「現在の体重」が変わるならその値、変わらないならnull。
///
/// 保存する日付が既存のどの記録よりも新しい（または同じ日）ときだけ、
/// 最新の体重が入れ替わる。過去の日付を後から入力しても現在の体重は動かさない。
double? latestWeightAfterSave(List<WeightLog> current, WeightLog log) {
  final newestKey = _newestKey(current);
  if (newestKey == null || log.dateKey.compareTo(newestKey) >= 0) {
    return log.weightKg;
  }
  return null;
}

/// [dateKey] の記録を削除したあとに「現在の体重」が変わるならその値、変わらないならnull。
///
/// 最新の記録以外を消しても変わらない。最後の1件を消した場合も、
/// 戻す先が無いのでプロフィールの体重はそのまま残す。
double? latestWeightAfterDelete(List<WeightLog> current, String dateKey) {
  if (_newestKey(current) != dateKey) return null;
  final remaining = current.where((l) => l.dateKey != dateKey).toList()
    ..sort((a, b) => b.dateKey.compareTo(a.dateKey));
  return remaining.isEmpty ? null : remaining.first.weightKg;
}

String? _newestKey(List<WeightLog> logs) {
  String? newest;
  for (final l in logs) {
    if (newest == null || l.dateKey.compareTo(newest) > 0) newest = l.dateKey;
  }
  return newest;
}
