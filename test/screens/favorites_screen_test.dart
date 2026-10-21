import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/screens/favorites_screen.dart';

import '../helpers/fake_services.dart';
import '../helpers/fixtures.dart';
import '../helpers/pump.dart';

void main() {
  setUpAll(setUpScreenTests);

  testWidgets('読み込みに失敗したら、無限ローディングではなくエラー表示にする', (tester) async {
    await pumpApp(
      tester,
      TestEnv(favoritesOverride: FailingFavoriteRepository.new),
      const FavoritesScreen(),
    );

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('お気に入りを読み込めませんでした'), findsOneWidget);
  });

  testWidgets('空なら使い方を案内する', (tester) async {
    await pumpApp(tester, TestEnv(), const FavoritesScreen());

    expect(find.textContaining('1タップで記録できます'), findsOneWidget);
  });

  testWidgets('一覧を出し、外したものは「元に戻す」で戻せる', (tester) async {
    final env = TestEnv();
    await env.services.favorites.addFavorite(
      food('プロテイン', amount: '1杯', kcal: 120, p: 24),
    );
    await pumpApp(tester, env, const FavoritesScreen());

    expect(find.text('プロテイン（1杯）'), findsOneWidget);
    expect(find.text('120 kcal'), findsOneWidget);

    await tester.tap(find.byTooltip('「プロテイン」をお気に入りから外す'));
    await tester.pumpAndSettle();
    expect(find.text('プロテイン（1杯）'), findsNothing);
    expect((await env.docs.favorites.get()).docs, isEmpty);

    await tester.tap(find.text('元に戻す'));
    await tester.pumpAndSettle();
    expect(find.text('プロテイン（1杯）'), findsOneWidget);
  });

  testWidgets('「登録する」から手入力でお気に入りを登録できる', (tester) async {
    final env = TestEnv();
    await pumpApp(tester, env, const FavoritesScreen());

    await tester.tap(find.text('登録する'));
    await tester.pumpAndSettle();
    expect(find.text('お気に入りを登録'), findsOneWidget);

    await tester.enterText(textFieldWithLabel('名前'), 'ゆで卵');
    await tester.enterText(textFieldWithLabel('量（任意）'), '1個');
    await tester.enterText(textFieldWithLabel('エネルギー'), '76');
    await tester.enterText(textFieldWithLabel('たんぱく質'), '6.3');
    await tester.tap(find.text('この内容にする'));
    await tester.pumpAndSettle();

    expect(find.text('「ゆで卵」を登録しました'), findsOneWidget);
    expect(find.text('ゆで卵（1個）'), findsOneWidget);
  });
}
