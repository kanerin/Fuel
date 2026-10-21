import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/models/user_profile.dart';
import 'package:fuel/widgets/targets_summary.dart';

import '../helpers/fake_services.dart';
import '../helpers/fixtures.dart';
import '../helpers/pump.dart';

void main() {
  setUpAll(setUpScreenTests);

  Future<void> pumpSummary(WidgetTester tester, UserProfile profile) => pumpApp(
    tester,
    TestEnv(),
    Scaffold(body: TargetsSummary(profile: profile)),
  );

  testWidgets('減量: 消費カロリーからの差とペースを添える', (tester) async {
    await pumpSummary(tester, sampleProfile);

    expect(find.text('消費カロリー − 514 kcal（週0.5kgペース）'), findsOneWidget);
    expect(find.text('（20%）'), findsOneWidget);
    expect(find.textContaining('引き上げています'), findsNothing);
  });

  testWidgets('増量は「＋」で添える', (tester) async {
    await pumpSummary(
      tester,
      sampleProfile.copyWith(goal: GoalType.gain, weeklyRateKg: 0.25),
    );

    expect(find.text('消費カロリー + 257 kcal（週0.25kgペース）'), findsOneWidget);
  });

  testWidgets('基礎代謝量まで引き上げた場合はそう書く', (tester) async {
    await pumpSummary(
      tester,
      const UserProfile(
        sex: Sex.female,
        age: 30,
        heightCm: 158,
        weightKg: 55,
        activityLevel: ActivityLevel.sedentary,
        goal: GoalType.lose,
        weeklyRateKg: 0.75,
        pfcPreset: PfcPreset.balanced,
        pfcRatio: PfcRatio(20, 25, 55),
      ),
    );

    expect(find.textContaining('基礎代謝量まで引き上げています'), findsOneWidget);
    expect(find.text('1,230 kcal'), findsOneWidget);
  });
}
