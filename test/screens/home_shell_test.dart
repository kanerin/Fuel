import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/screens/home_shell.dart';

import '../helpers/fake_services.dart';
import '../helpers/fixtures.dart';
import '../helpers/pump.dart';

void main() {
  setUpAll(setUpScreenTests);

  Future<TestEnv> pumpHome(WidgetTester tester) async {
    final env = TestEnv();
    await env.seedProfile(sampleProfile);
    await env.seedEntry(
      entry('a', dateKey: '2026-10-19', name: '月曜のカレー', kcal: 800),
    );
    await pumpApp(tester, env, const HomeShell(profile: sampleProfile));
    return env;
  }

  testWidgets('4つのタブを切り替えられる', (tester) async {
    await pumpHome(tester);

    expect(find.text('今日 10月21日(水)'), findsOneWidget);
    for (final (tab, title) in [
      ('履歴', '摂取カロリー'),
      ('体重', '推移'),
      ('設定', '1日の目安'),
    ]) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget, reason: '$tabタブ');
    }
  });

  testWidgets('タブを切り替えても、書きかけの文章は消えない', (tester) async {
    await pumpHome(tester);

    await tester.enterText(textFieldWithHint('食べたものを入力'), 'ラーメン大盛り');
    await tester.tap(find.text('設定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('きょう'));
    await tester.pumpAndSettle();

    expect(find.text('ラーメン大盛り'), findsOneWidget);
  });

  testWidgets('履歴の日付をタップすると、「きょう」タブでその日を開く', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.text('履歴'));
    await tester.pumpAndSettle();
    await scrollToFind(tester, find.text('10月19日(月)'));
    await tester.tap(find.text('10月19日(月)'));
    await tester.pumpAndSettle();

    expect(find.text('10月19日(月)'), findsOneWidget);
    expect(find.text('月曜のカレー'), findsOneWidget);
  });

  // integration_test/layout_test.dart と同じ条件を、ウィジェットテストでも先に確かめる
  // （結合テストは1回20分かかるので、レイアウト崩れはここで早く見つける）
  for (final (label, size, textScale) in [
    ('小さい画面（320×568）', const Size(320, 568), 1.0),
    ('文字サイズ大（1.3倍）', const Size(360, 780), 1.3),
    ('小さい画面で文字サイズ大', const Size(320, 568), 1.3),
  ]) {
    testWidgets('主な画面がはみ出さない: $label', (tester) async {
      final env = TestEnv();
      await env.seedProfile(sampleProfile);
      await env.seedEntry(
        entry('a', name: '具だくさんの豚汁と炊き込みご飯', amount: '1人前（約800g）'),
      );
      await pumpApp(
        tester,
        env,
        const HomeShell(profile: sampleProfile),
        logicalSize: size,
        textScale: textScale,
      );
      expect(tester.takeException(), isNull, reason: '$label・きょう');

      // 今日以外を表示すると「今日へ」が増えてAppBarが一番窮屈になる
      await tester.tap(find.byTooltip('前の日'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$label・きょう（前の日）');

      for (final tab in ['履歴', '体重', '設定']) {
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$label・$tab');
      }
    });
  }
}
