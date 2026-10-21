import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/models/meal_entry.dart';
import 'package:fuel/models/nutrition.dart';
import 'package:fuel/screens/entry_form_screen.dart';
import 'package:fuel/services/favorite_repository.dart';

import '../helpers/fake_services.dart';
import '../helpers/fixtures.dart';
import '../helpers/pump.dart';

void main() {
  setUpAll(setUpScreenTests);

  /// 画面をpushした状態にする（保存・削除で閉じることを確かめるため）。
  Future<void> openScreen(
    WidgetTester tester,
    TestEnv env,
    Widget screen,
  ) async {
    await pumpApp(
      tester,
      env,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute<void>(builder: (_) => screen)),
              child: const Text('開く'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.pumpAndSettle();
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  group('手入力で追加', () {
    testWidgets('入力した値で、指定した日・食事区分に「手入力」として記録する', (tester) async {
      final env = TestEnv();
      await openScreen(
        tester,
        env,
        EntryFormScreen.create(dateKey: '2026-10-21', mealType: MealType.snack),
      );

      expect(find.text('手入力で追加'), findsOneWidget);
      await tester.enterText(textFieldWithLabel('名前'), 'プロテインバー');
      await tester.enterText(textFieldWithLabel('量（任意）'), '1本');
      await tester.enterText(textFieldWithLabel('エネルギー'), '200');
      await tester.enterText(textFieldWithLabel('たんぱく質'), '15');
      await tester.enterText(textFieldWithLabel('脂質'), '9');
      await tester.enterText(textFieldWithLabel('炭水化物'), '１６．５'); // 全角でも読む
      await tapAndSettle(tester, find.text('追加する'));

      expect(find.text('開く'), findsOneWidget, reason: '保存したら閉じる');
      expect(find.text('間食に「プロテインバー」を追加しました'), findsOneWidget);
      final saved = (await env.savedEntries()).single;
      expect(saved.food.name, 'プロテインバー');
      expect(saved.food.amount, '1本');
      expect(
        saved.nutrition,
        const Nutrition(calories: 200, protein: 15, fat: 9, carbs: 16.5),
      );
      expect(saved.mealType, MealType.snack);
      expect(saved.source, EntrySource.manual);
      expect(saved.dateKey, '2026-10-21');
    });

    testWidgets('名前とエネルギーは必須。空なら理由を出して保存しない', (tester) async {
      final env = TestEnv();
      await openScreen(
        tester,
        env,
        EntryFormScreen.create(dateKey: '2026-10-21', mealType: MealType.lunch),
      );

      await tapAndSettle(tester, find.text('追加する'));

      expect(find.text('名前を入力してください'), findsOneWidget);
      expect(find.text('入力してください'), findsOneWidget);
      expect(await env.savedEntries(), isEmpty);
    });

    testWidgets('範囲外・数値でない値は保存しない', (tester) async {
      final env = TestEnv();
      await openScreen(
        tester,
        env,
        EntryFormScreen.create(dateKey: '2026-10-21', mealType: MealType.lunch),
      );

      await tester.enterText(textFieldWithLabel('名前'), 'ピザ');
      await tester.enterText(textFieldWithLabel('エネルギー'), '9000');
      await tester.enterText(textFieldWithLabel('脂質'), 'たくさん');
      await tapAndSettle(tester, find.text('追加する'));

      expect(find.text('0〜5000'), findsOneWidget);
      expect(find.text('数値で入力'), findsOneWidget);
      expect(await env.savedEntries(), isEmpty);
    });

    testWidgets('「PFCから計算」でkcalを埋められ、P・F・Cの空欄は0として扱う', (tester) async {
      final env = TestEnv();
      await openScreen(
        tester,
        env,
        EntryFormScreen.create(dateKey: '2026-10-21', mealType: MealType.lunch),
      );

      await tester.enterText(textFieldWithLabel('名前'), 'サラダチキン');
      await tester.enterText(textFieldWithLabel('たんぱく質'), '24');
      await tester.enterText(textFieldWithLabel('脂質'), '1.5');
      await tapAndSettle(tester, find.text('PFCから計算'));

      expect(
        find.widgetWithText(TextField, '110'),
        findsOneWidget,
      ); // 24×4 + 1.5×9 = 109.5

      await tapAndSettle(tester, find.text('追加する'));
      expect((await env.savedEntries()).single.nutrition.carbs, 0);
    });

    testWidgets('「お気に入りにも登録する」にチェックすると、お気に入りにも保存する', (tester) async {
      final env = TestEnv();
      await openScreen(
        tester,
        env,
        EntryFormScreen.create(
          dateKey: '2026-10-21',
          mealType: MealType.breakfast,
        ),
      );

      await tester.enterText(textFieldWithLabel('名前'), 'オートミール');
      await tester.enterText(textFieldWithLabel('量（任意）'), '30g');
      await tester.enterText(textFieldWithLabel('エネルギー'), '114');
      await tapAndSettle(tester, find.text('お気に入りにも登録する'));
      await tapAndSettle(tester, find.text('追加する'));

      final favorites = await env.docs.favorites.get();
      expect(favorites.docs.single.data()['name'], 'オートミール');
    });
  });

  group('記録の編集', () {
    testWidgets('保存済みの値が入っていて、量の倍率・食事区分を変えて保存できる', (tester) async {
      final env = TestEnv();
      final original = entry(
        'e1',
        name: '牛丼',
        amount: '並盛',
        kcal: 650,
        p: 22,
        f: 22,
        c: 90,
      );
      await env.seedEntry(original);
      await openScreen(tester, env, EntryFormScreen.edit(entry: original));

      expect(find.text('記録を編集'), findsOneWidget);
      expect(find.widgetWithText(TextField, '牛丼'), findsOneWidget);
      expect(find.textContaining('AIの推定値です'), findsOneWidget);

      await tapAndSettle(tester, find.text('×2'));
      await tapAndSettle(tester, find.text('夕食'));
      await tapAndSettle(tester, find.text('保存する'));

      expect(find.text('保存しました'), findsOneWidget);
      final saved = (await env.savedEntries()).single;
      expect(saved.id, 'e1');
      expect(saved.mealType, MealType.dinner);
      expect(
        saved.nutrition,
        const Nutrition(calories: 1300, protein: 44, fat: 44, carbs: 180),
      );
    });

    testWidgets('削除は確認してから行い、「元に戻す」で戻せる', (tester) async {
      final env = TestEnv();
      final original = entry('e1', name: '牛丼');
      await env.seedEntry(original);
      await openScreen(tester, env, EntryFormScreen.edit(entry: original));

      await tapAndSettle(tester, find.byTooltip('削除'));
      expect(find.text('この記録を削除しますか？'), findsOneWidget);
      await tapAndSettle(tester, find.text('キャンセル'));
      expect(await env.savedEntries(), hasLength(1));

      await tapAndSettle(tester, find.byTooltip('削除'));
      await tapAndSettle(tester, find.text('削除する'));
      expect(find.text('開く'), findsOneWidget);
      expect(await env.savedEntries(), isEmpty);

      await tapAndSettle(tester, find.text('元に戻す'));
      expect((await env.savedEntries()).single.id, 'e1');
    });

    testWidgets('☆でお気に入りに登録・解除できる（名前と量で見分ける）', (tester) async {
      final env = TestEnv();
      final original = entry(
        'e1',
        name: 'プロテイン',
        amount: '1杯',
        kcal: 120,
        p: 24,
        f: 1.5,
        c: 3,
      );
      await env.seedEntry(original);
      await openScreen(tester, env, EntryFormScreen.edit(entry: original));

      await tapAndSettle(tester, find.byTooltip('お気に入りに登録'));
      expect(find.text('「プロテイン」をお気に入りに登録しました'), findsOneWidget);
      expect(find.byTooltip('お気に入りから外す'), findsOneWidget);
      final id = favoriteIdFor(original.food);
      expect((await env.docs.favorites.doc(id).get()).exists, isTrue);

      await tapAndSettle(tester, find.byTooltip('お気に入りから外す'));
      expect((await env.docs.favorites.doc(id).get()).exists, isFalse);
      expect(find.byTooltip('お気に入りに登録'), findsOneWidget);
    });

    testWidgets('お気に入りを読み込めないときは☆を出さない（登録と解除を取り違えないため）', (tester) async {
      final env = TestEnv(favoritesOverride: FailingFavoriteRepository.new);
      final original = entry('e1');
      await env.seedEntry(original);
      await openScreen(tester, env, EntryFormScreen.edit(entry: original));

      expect(find.byTooltip('お気に入りに登録'), findsNothing);
      expect(find.byTooltip('お気に入りから外す'), findsNothing);
      expect(find.byTooltip('削除'), findsOneWidget);
    });
  });
}
