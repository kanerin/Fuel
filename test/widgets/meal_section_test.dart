import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/logic/daily_summary.dart';
import 'package:fuel/models/meal_entry.dart';
import 'package:fuel/widgets/meal_section.dart';

import '../helpers/fake_services.dart';
import '../helpers/fixtures.dart';
import '../helpers/pump.dart';

void main() {
  setUpAll(setUpScreenTests);

  Future<List<String>> pumpSection(
    WidgetTester tester,
    List<MealEntry> entries,
  ) async {
    final calls = <String>[];
    final summary = DailySummary.of(entries);
    await pumpApp(
      tester,
      TestEnv(),
      Scaffold(
        body: MealSection(
          type: MealType.lunch,
          entries: summary.entriesFor(MealType.lunch),
          subtotal: summary.totalFor(MealType.lunch),
          onAdd: () => calls.add('add'),
          onTapEntry: (e) => calls.add('tap:${e.id}'),
          onDeleteEntry: (e) => calls.add('delete:${e.id}'),
        ),
      ),
    );
    return calls;
  }

  testWidgets('記録が無ければ案内だけで、小計は出さない', (tester) async {
    await pumpSection(tester, const []);

    expect(find.text('昼食'), findsOneWidget);
    expect(find.text('まだ記録がありません'), findsOneWidget);
    expect(find.textContaining('kcal'), findsNothing);
  });

  testWidgets('記録・量・小計・AI推定の印を出し、タップ・追加を伝える', (tester) async {
    final calls = await pumpSection(tester, [
      entry('a', name: '牛丼', amount: '並盛', kcal: 650),
      entry(
        'b',
        name: '味噌汁',
        amount: '',
        kcal: 40,
        source: EntrySource.manual,
        createdAt: DateTime(2026, 10, 21, 12, 1),
      ),
    ]);

    expect(find.text('690 kcal'), findsOneWidget); // 小計
    expect(find.text('並盛'), findsOneWidget);
    expect(find.text('AI'), findsOneWidget, reason: '手入力の記録には付けない');

    await tester.tap(find.text('味噌汁'));
    await tester.tap(find.byTooltip('昼食に追加'));
    expect(calls, ['tap:b', 'add']);
  });

  testWidgets('左へスワイプすると削除を伝える', (tester) async {
    final calls = await pumpSection(tester, [entry('a', name: '牛丼')]);

    await tester.drag(find.text('牛丼'), const Offset(-600, 0));
    await tester.pumpAndSettle();

    expect(calls, ['delete:a']);
  });

  testWidgets('長い名前でもはみ出さない', (tester) async {
    await pumpSection(tester, [
      entry('a', name: '具だくさんの豚汁と炊き込みご飯と焼き鮭の和定食（ご飯大盛り）', amount: '1人前（約800g）'),
    ]);

    expect(tester.takeException(), isNull);
  });
}
