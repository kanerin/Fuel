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
}
