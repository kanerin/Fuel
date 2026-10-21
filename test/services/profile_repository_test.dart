import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/models/user_profile.dart';
import 'package:fuel/services/profile_repository.dart';

import '../helpers/fake_services.dart';
import '../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late ProfileRepository repo;

  setUp(() {
    env = TestEnv();
    repo = env.services.profiles;
  });

  group('watchProfile', () {
    test('未入力ならnull（→ オンボーディング）', () async {
      expect(await repo.watchProfile().first, isNull);
    });

    test('保存したプロフィールを読める', () async {
      await repo.saveProfile(sampleProfile);

      expect(await repo.watchProfile().first, sampleProfile);
    });

    test('保存されている値が壊れていたらnull（誤った目標を出さず入力し直してもらう）', () async {
      await env.docs.user.set({
        'profile': {...sampleProfile.toMap(), 'age': 'thirty'},
      });

      expect(await repo.watchProfile().first, isNull);
    });
  });

  group('saveProfile', () {
    test('任意項目を消して保存したら、古い値が残らない', () async {
      await repo.saveProfile(sampleProfile);
      await repo.saveProfile(
        sampleProfile.copyWith(targetWeightKg: () => null),
      );

      final saved = await repo.watchProfile().first;
      expect(saved!.targetWeightKg, isNull);
    });

    test('weightLogDateKeyを渡すと、その日の体重記録も同時に作る', () async {
      await repo.saveProfile(sampleProfile, weightLogDateKey: '2026-10-21');

      final log = await env.docs.weights.doc('2026-10-21').get();
      expect(log.data()!['weightKg'], 70);
      expect(log.data()!['date'], '2026-10-21');
    });

    test('weightLogDateKeyを渡さなければ体重記録は作らない', () async {
      await repo.saveProfile(sampleProfile);

      final logs = await env.docs.weights.get();
      expect(logs.docs, isEmpty);
    });
  });

  group('watchAiUsage', () {
    test('まだ一度も使っていなければ上限いっぱい残っている', () async {
      final usage = await repo.watchAiUsage('2026-10-21').first;

      expect(usage.used, 0);
      expect(usage.limit, kDefaultAiDailyLimit);
      expect(usage.remaining, kDefaultAiDailyLimit);
    });

    test('今日の回数と、サーバーが書いた上限を読む', () async {
      await env.firestore.collection('aiUsage').doc(testUid).set({
        'date': '2026-10-21',
        'count': 12,
        'limit': 30,
      });

      final usage = await repo.watchAiUsage('2026-10-21').first;
      expect(usage.used, 12);
      expect(usage.remaining, 18);
    });

    test('前日の記録は今日の回数に数えない', () async {
      await env.firestore.collection('aiUsage').doc(testUid).set({
        'date': '2026-10-20',
        'count': 50,
        'limit': 50,
      });

      final usage = await repo.watchAiUsage('2026-10-21').first;
      expect(usage.remaining, 50);
    });

    test('上限を超えた回数でも残りはマイナスにしない', () async {
      await env.firestore.collection('aiUsage').doc(testUid).set({
        'date': '2026-10-21',
        'count': 60,
        'limit': 50,
      });

      expect((await repo.watchAiUsage('2026-10-21').first).remaining, 0);
    });
  });

  test('UserProfileの比率もそのまま往復する（カスタム）', () async {
    final custom = sampleProfile.copyWith(
      pfcPreset: PfcPreset.custom,
      pfcRatio: const PfcRatio(35, 20, 45),
    );
    await repo.saveProfile(custom);

    expect(
      (await repo.watchProfile().first)!.pfcRatio,
      const PfcRatio(35, 20, 45),
    );
  });
}
