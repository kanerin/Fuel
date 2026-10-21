import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/models/meal_entry.dart';
import 'package:fuel/screens/entry_form_screen.dart';
import 'package:fuel/screens/quick_add_sheet.dart';

import '../helpers/fake_services.dart';
import '../helpers/fixtures.dart';
import '../helpers/pump.dart';

void main() {
  setUpAll(setUpScreenTests);

  Future<void> openSheet(
    WidgetTester tester,
    TestEnv env, {
    MealType mealType = MealType.breakfast,
  }) async {
    await pumpApp(
      tester,
      env,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showQuickAddSheet(
                context,
                dateKey: '2026-10-21',
                mealType: mealType,
              ),
              child: const Text('開く'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();
  }

  testWidgets('お気に入りをタップすると、AIを使わずにその区分へ記録する', (tester) async {
    final env = TestEnv();
    await env.services.favorites.addFavorite(
      food('プロテイン', amount: '1杯', kcal: 120, p: 24, f: 1.5, c: 3),
    );
    await openSheet(tester, env);

    expect(find.text('朝食に追加'), findsOneWidget);
    await tester.tap(find.text('プロテイン（1杯）'));
    await tester.pumpAndSettle();

    expect(find.text('朝食に「プロテイン」を追加しました'), findsOneWidget);
    final saved = (await env.savedEntries()).single;
    expect(saved.food.name, 'プロテイン');
    expect(saved.mealType, MealType.breakfast);
    expect(saved.source, EntrySource.favorite);
    expect(env.estimator.calls, isEmpty);
  });

  testWidgets('最近食べたものからも記録でき、「元に戻す」で取り消せる', (tester) async {
    final env = TestEnv();
    await env.seedEntry(
      entry('old', dateKey: '2026-10-20', name: 'カレー', amount: '1皿', kcal: 750),
    );
    await openSheet(tester, env, mealType: MealType.dinner);

    await tester.tap(find.text('最近食べたもの'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('カレー（1皿）'));
    await tester.pumpAndSettle();

    final added = (await env.savedEntries()).where((e) => e.id != 'old').single;
    expect(added.dateKey, '2026-10-21');
    expect(added.mealType, MealType.dinner);
    expect(added.source, EntrySource.recent);

    await tester.tap(find.text('元に戻す'));
    await tester.pumpAndSettle();
    expect((await env.savedEntries()).map((e) => e.id), ['old']);
  });

  testWidgets('お気に入り・最近食べたものが空なら案内を出す', (tester) async {
    await openSheet(tester, TestEnv());

    expect(find.textContaining('お気に入りに登録できます'), findsOneWidget);
    await tester.tap(find.text('最近食べたもの'));
    await tester.pumpAndSettle();
    expect(find.text('まだ記録がありません'), findsOneWidget);
  });

  testWidgets('読み込みに失敗したら、無限ローディングではなくエラー表示にする', (tester) async {
    final env = TestEnv(
      favoritesOverride: FailingFavoriteRepository.new,
      mealsOverride: FailingMealRepository.new,
    );
    await openSheet(tester, env);

    expect(find.text('お気に入りを読み込めませんでした'), findsOneWidget);
    await tester.tap(find.text('最近食べたもの'));
    await tester.pumpAndSettle();
    expect(find.text('最近食べたものを読み込めませんでした'), findsOneWidget);
  });

  testWidgets('「手入力」でシートを閉じて手入力の画面を開く', (tester) async {
    await openSheet(tester, TestEnv(), mealType: MealType.lunch);

    await tester.tap(find.text('手入力'));
    await tester.pumpAndSettle();

    expect(find.byType(EntryFormScreen), findsOneWidget);
    expect(find.text('手入力で追加'), findsOneWidget);
  });
}
