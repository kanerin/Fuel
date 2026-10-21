import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/models/food_item.dart';
import 'package:fuel/screens/food_edit_screen.dart';

import '../helpers/fake_services.dart';
import '../helpers/fixtures.dart';
import '../helpers/pump.dart';

void main() {
  setUpAll(setUpScreenTests);

  Future<List<FoodItem?>> openEditor(
    WidgetTester tester, {
    FoodItem? initial,
  }) async {
    final results = <FoodItem?>[];
    await pumpApp(
      tester,
      TestEnv(),
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async => results.add(
                await Navigator.of(context).push<FoodItem>(
                  MaterialPageRoute(
                    builder: (_) => FoodEditScreen(initial: initial),
                  ),
                ),
              ),
              child: const Text('開く'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();
    return results;
  }

  testWidgets('直した値を返す（保存はしない）', (tester) async {
    final results = await openEditor(
      tester,
      initial: food('牛丼', amount: '並盛', kcal: 650, p: 22, f: 22, c: 90),
    );

    await tester.tap(find.text('×0.5'));
    await tester.pump();
    await tester.tap(find.text('この内容にする'));
    await tester.pumpAndSettle();

    expect(
      results.single,
      food('牛丼', amount: '並盛', kcal: 325, p: 11, f: 11, c: 45),
    );
  });

  testWidgets('入力に不備があれば返さない', (tester) async {
    final results = await openEditor(tester, initial: food('牛丼', kcal: 650));

    await tester.enterText(textFieldWithLabel('名前'), '');
    await tester.tap(find.text('この内容にする'));
    await tester.pumpAndSettle();

    expect(find.text('名前を入力してください'), findsOneWidget);
    expect(results, isEmpty);
  });

  testWidgets('戻るボタンで閉じたらnull', (tester) async {
    final results = await openEditor(tester);

    await tapBack(tester);

    expect(results, [null]);
  });
}
