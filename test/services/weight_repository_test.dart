import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/models/weight_log.dart';
import 'package:fuel/services/weight_repository.dart';

import '../helpers/fake_services.dart';
import '../helpers/fixtures.dart';

void main() {
  const logs = [
    WeightLog(dateKey: '2026-10-21', weightKg: 69.5),
    WeightLog(dateKey: '2026-10-19', weightKg: 70.2),
    WeightLog(dateKey: '2026-10-20', weightKg: 69.8),
  ];

  group('latestWeightAfterSave', () {
    test('最新の日付（または同じ日）を保存したら現在の体重が入れ替わる', () {
      expect(
        latestWeightAfterSave(
          logs,
          const WeightLog(dateKey: '2026-10-22', weightKg: 69),
        ),
        69,
      );
      expect(
        latestWeightAfterSave(
          logs,
          const WeightLog(dateKey: '2026-10-21', weightKg: 69.3),
        ),
        69.3,
      );
    });

    test('過去の日付を後から入力しても現在の体重は動かさない', () {
      expect(
        latestWeightAfterSave(
          logs,
          const WeightLog(dateKey: '2026-10-18', weightKg: 71),
        ),
        isNull,
      );
    });

    test('初めての記録なら、それが現在の体重', () {
      expect(
        latestWeightAfterSave(
          const [],
          const WeightLog(dateKey: '2026-10-01', weightKg: 72),
        ),
        72,
      );
    });
  });

  group('latestWeightAfterDelete', () {
    test('最新の記録を消したら、ひとつ前の記録に戻す', () {
      expect(latestWeightAfterDelete(logs, '2026-10-21'), 69.8);
    });

    test('最新以外を消しても変わらない', () {
      expect(latestWeightAfterDelete(logs, '2026-10-19'), isNull);
    });

    test('最後の1件を消したら戻す先が無いのでそのまま', () {
      expect(
        latestWeightAfterDelete(const [
          WeightLog(dateKey: '2026-10-21', weightKg: 69),
        ], '2026-10-21'),
        isNull,
      );
    });
  });

  group('WeightRepository（Firestore）', () {
    late TestEnv env;
    late WeightRepository repo;

    setUp(() async {
      env = TestEnv();
      repo = env.services.weights;
      await env.seedProfile(sampleProfile); // 体重70kg
    });

    Future<double> profileWeight() async {
      final snap = await env.docs.user.get();
      return ((snap.data()!['profile'] as Map)['weightKg'] as num).toDouble();
    }

    test('最新の体重を記録するとプロフィールの体重も更新する', () async {
      await repo.saveLog('2026-10-21', 69.46, current: const []);

      expect(await profileWeight(), 69.5);
      final saved = await repo.watchLogs().first;
      expect(saved, const [WeightLog(dateKey: '2026-10-21', weightKg: 69.5)]);
    });

    test('過去の日付の記録ではプロフィールの体重を変えない', () async {
      await repo.saveLog('2026-10-21', 69.5, current: const []);
      final current = await repo.watchLogs().first;

      await repo.saveLog('2026-10-10', 71, current: current);

      expect(await profileWeight(), 69.5);
    });

    test('同じ日に入れ直したら上書き（1日1件）', () async {
      await repo.saveLog('2026-10-21', 69.5, current: const []);
      await repo.saveLog(
        '2026-10-21',
        69.2,
        current: await repo.watchLogs().first,
      );

      expect(await repo.watchLogs().first, const [
        WeightLog(dateKey: '2026-10-21', weightKg: 69.2),
      ]);
    });

    test('一覧は新しい日付順で、壊れた記録は除く', () async {
      await repo.saveLog('2026-10-19', 70.2, current: const []);
      await repo.saveLog(
        '2026-10-21',
        69.5,
        current: await repo.watchLogs().first,
      );
      await env.docs.weights.doc('2026-10-20').set({
        'date': '2026-10-20',
        'weightKg': 'x',
      });

      final saved = await repo.watchLogs().first;
      expect(saved.map((l) => l.dateKey), ['2026-10-21', '2026-10-19']);
    });

    test('最新の記録を消したら、ひとつ前の体重をプロフィールへ戻す', () async {
      await repo.saveLog('2026-10-20', 69.8, current: const []);
      await repo.saveLog(
        '2026-10-21',
        69.5,
        current: await repo.watchLogs().first,
      );

      await repo.deleteLog('2026-10-21', current: await repo.watchLogs().first);

      expect(await profileWeight(), 69.8);
      expect((await repo.watchLogs().first).map((l) => l.dateKey), [
        '2026-10-20',
      ]);
    });
  });
}
