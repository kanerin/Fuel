import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/models/user_profile.dart';

import '../helpers/fixtures.dart';

void main() {
  group('UserProfile.validate', () {
    test('サンプルは有効', () {
      expect(sampleProfile.validate(), isNull);
    });

    test('範囲外の年齢・身長・体重を弾く', () {
      expect(sampleProfile.copyWith(age: 14).validate(), contains('年齢'));
      expect(sampleProfile.copyWith(age: 101).validate(), contains('年齢'));
      expect(sampleProfile.copyWith(heightCm: 119).validate(), contains('身長'));
      expect(sampleProfile.copyWith(weightKg: 251).validate(), contains('体重'));
      expect(
        sampleProfile.copyWith(targetWeightKg: () => 20).validate(),
        contains('目標体重'),
      );
    });

    test('目標に合わないペースを弾く（維持なのに週0.5kgなど）', () {
      expect(
        sampleProfile
            .copyWith(goal: GoalType.maintain, weeklyRateKg: 0.5)
            .validate(),
        contains('ペース'),
      );
      expect(
        sampleProfile
            .copyWith(goal: GoalType.gain, weeklyRateKg: 0.75)
            .validate(),
        contains('ペース'),
      );
    });

    test('PFC比率は各5〜70%・合計100%', () {
      expect(
        sampleProfile.copyWith(pfcRatio: const PfcRatio(20, 20, 50)).validate(),
        contains('PFC'),
      );
      expect(
        sampleProfile.copyWith(pfcRatio: const PfcRatio(4, 26, 70)).validate(),
        contains('PFC'),
      );
      expect(
        sampleProfile.copyWith(pfcRatio: const PfcRatio(5, 25, 70)).validate(),
        isNull,
      );
    });

    test('手動の目標カロリーは1000〜5000kcal', () {
      expect(
        sampleProfile.copyWith(customTargetKcal: () => 999).validate(),
        contains('目標カロリー'),
      );
      expect(
        sampleProfile.copyWith(customTargetKcal: () => 5000).validate(),
        isNull,
      );
    });
  });

  group('toMap / fromMap', () {
    test('往復できる', () {
      expect(UserProfile.fromMap(sampleProfile.toMap()), sampleProfile);
    });

    test('任意項目（目標体重・手動の目標カロリー）はnullでも読める', () {
      final profile = sampleProfile.copyWith(targetWeightKg: () => null);

      expect(UserProfile.fromMap(profile.toMap()), profile);
    });

    test('Firestoreから整数で返ってきた数値も読める', () {
      final map = sampleProfile.toMap()
        ..['heightCm'] = 170
        ..['weightKg'] = 70
        ..['weeklyRateKg'] = 0.5;

      expect(UserProfile.fromMap(map), sampleProfile);
    });

    test('未入力（null・マップでない）ならnull → オンボーディングへ', () {
      expect(UserProfile.fromMap(null), isNull);
      expect(UserProfile.fromMap('profile'), isNull);
    });

    test('必須項目が欠けている・不明な値・範囲外ならnull（誤った目標を出さない）', () {
      expect(UserProfile.fromMap(sampleProfile.toMap()..remove('age')), isNull);
      expect(
        UserProfile.fromMap(
          sampleProfile.toMap()..['activityLevel'] = 'unknown',
        ),
        isNull,
      );
      expect(UserProfile.fromMap(sampleProfile.toMap()..['age'] = 5), isNull);
    });
  });

  group('GoalType', () {
    test('ペースの選択肢と初期値', () {
      expect(GoalType.lose.rateOptions, [0.25, 0.5, 0.75]);
      expect(GoalType.maintain.rateOptions, [0]);
      expect(GoalType.gain.rateOptions, [0.25, 0.5]);
      for (final goal in GoalType.values) {
        expect(goal.rateOptions, contains(goal.defaultRate));
      }
    });
  });

  test('プリセットの比率はすべて有効', () {
    for (final preset in PfcPreset.values) {
      if (preset == PfcPreset.custom) {
        expect(preset.ratio, isNull);
      } else {
        expect(preset.ratio!.isValid, isTrue, reason: preset.label);
      }
    }
  });

  test('paceLabel', () {
    expect(paceLabel(0.25), 'ゆっくり');
    expect(paceLabel(0.5), 'ふつう');
    expect(paceLabel(0.75), 'しっかり');
    expect(paceLabel(0), '');
  });
}
