import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_profile.dart';
import '../models/weight_log.dart';
import 'user_docs.dart';

/// AI推定の1日の上限の既定値。サーバー（functions/src/nutrition_logic.ts の
/// AI_DAILY_CALL_LIMIT）が aiUsage/{uid}.limit に書き込む値が正で、
/// これはまだ一度も使っていない日の表示用。
const kDefaultAiDailyLimit = 50;

/// 今日のAI推定の利用状況。
class AiUsage {
  final int used;
  final int limit;

  const AiUsage({required this.used, required this.limit});

  int get remaining => max(0, limit - used);
}

class ProfileRepository {
  ProfileRepository(this._docs);

  final UserDocs _docs;

  /// プロフィール。未入力ならnull（→ オンボーディング）。
  Stream<UserProfile?> watchProfile() => _docs.user.snapshots().map(
    (snap) => UserProfile.fromMap(snap.data()?['profile']),
  );

  /// プロフィールを保存する。
  ///
  /// [weightLogDateKey] を渡すと、その日の体重記録も同じバッチで保存する
  /// （初回入力・設定画面で体重を変えたとき。プロフィールの体重と
  /// 体重記録の最新値を食い違わせないため）。
  Future<void> saveProfile(UserProfile profile, {String? weightLogDateKey}) {
    final batch = _docs.db.batch()
      ..set(
        _docs.user,
        {'profile': profile.toMap(), 'updatedAt': FieldValue.serverTimestamp()},
        // profileを丸ごと置き換える（merge: true だと、消した任意項目が残る）
        SetOptions(mergeFields: const ['profile', 'updatedAt']),
      );
    if (weightLogDateKey != null) {
      batch.set(
        _docs.weights.doc(weightLogDateKey),
        weightLogData(
          WeightLog(dateKey: weightLogDateKey, weightKg: profile.weightKg),
        ),
      );
    }
    return batch.commit();
  }

  /// 今日のAI推定の利用状況。[todayKey] と違う日の記録は「まだ使っていない」とみなす。
  Stream<AiUsage> watchAiUsage(String todayKey) =>
      _docs.aiUsage.snapshots().map((snap) {
        final data = snap.data();
        final limit = data?['limit'];
        final resolvedLimit = limit is num
            ? limit.toInt()
            : kDefaultAiDailyLimit;
        if (data == null || data['date'] != todayKey) {
          return AiUsage(used: 0, limit: resolvedLimit);
        }
        final count = data['count'];
        return AiUsage(
          used: count is num ? count.toInt() : 0,
          limit: resolvedLimit,
        );
      });
}

/// 体重記録のドキュメントの中身。WeightRepository と共有する。
Map<String, dynamic> weightLogData(WeightLog log) => {
  ...log.toMap(),
  'updatedAt': FieldValue.serverTimestamp(),
};
