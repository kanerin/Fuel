import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/models/user_profile.dart';
import 'package:fuel/screens/favorites_screen.dart';
import 'package:fuel/screens/profile_form_screen.dart';
import 'package:fuel/screens/settings_screen.dart';

import '../helpers/fake_services.dart';
import '../helpers/fixtures.dart';
import '../helpers/pump.dart';

void main() {
  setUpAll(setUpScreenTests);

  Future<void> pumpSettings(
    WidgetTester tester,
    TestEnv env, {
    UserProfile profile = sampleProfile,
  }) => pumpApp(tester, env, SettingsScreen(profile: profile));

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    // ダイアログのボタンは一覧の外にあるので、スクロールせずに押す
    final inDialog = find
        .ancestor(of: finder, matching: find.byType(AlertDialog))
        .evaluate()
        .isNotEmpty;
    if (!inDialog) await scrollToFind(tester, finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('1日の目安（基礎代謝量・消費カロリー・目標・PFC）を出す', (tester) async {
    await pumpSettings(tester, TestEnv());

    expect(find.text('1,593 kcal'), findsOneWidget);
    expect(find.text('2,468 kcal'), findsOneWidget);
    expect(find.text('1,950 kcal'), findsOneWidget);
    expect(find.text('消費カロリー − 514 kcal（週0.5kgペース）'), findsOneWidget);
    expect(find.text('98 g'), findsOneWidget);
    expect(
      find.text('男性・35歳・170cm・70.0kg\n適度な運動・減量（ふつう 週0.5kg）'),
      findsOneWidget,
    );
  });

  testWidgets('目標が基礎代謝量を下回る手動設定なら注意を出す', (tester) async {
    await pumpSettings(
      tester,
      TestEnv(),
      profile: sampleProfile.copyWith(customTargetKcal: () => 1200),
    );

    expect(find.text('手動で設定した値'), findsOneWidget);
    expect(find.textContaining('基礎代謝量を下回っています'), findsOneWidget);
  });

  testWidgets('今日のAI推定の残り回数を出す（読めなければ「確認できません」）', (tester) async {
    final env = TestEnv();
    await env.firestore.collection('aiUsage').doc(testUid).set({
      'date': '2026-10-21',
      'count': 12,
      'limit': 50,
    });
    await pumpSettings(tester, env);
    expect(find.text('38 / 50回'), findsOneWidget);
  });

  testWidgets('残り回数が読めなくても画面は壊れない', (tester) async {
    await pumpSettings(
      tester,
      TestEnv(profilesOverride: FailingProfileRepository.new),
    );

    expect(find.text('確認できません'), findsOneWidget);
    expect(find.text('1日の目安'), findsOneWidget);
  });

  testWidgets('プロフィールと目標・お気に入りの画面を開ける', (tester) async {
    await pumpSettings(tester, TestEnv());

    await tapAndSettle(tester, find.text('プロフィールと目標'));
    expect(find.byType(ProfileFormScreen), findsOneWidget);
    await tapBack(tester);

    await tapAndSettle(tester, find.text('お気に入りの食品'));
    expect(find.byType(FavoritesScreen), findsOneWidget);
  });

  testWidgets('ログアウトは確認してから行う', (tester) async {
    final env = TestEnv();
    await pumpSettings(tester, env);

    await tapAndSettle(tester, find.text('ログアウト'));
    expect(find.text('ログアウトしますか？'), findsOneWidget);
    await tapAndSettle(tester, find.text('キャンセル'));
    expect(env.auth.signOutCalls, 0);

    await tapAndSettle(tester, find.text('ログアウト'));
    await tapAndSettle(tester, find.widgetWithText(FilledButton, 'ログアウト'));
    expect(env.auth.signOutCalls, 1);
  });

  group('アカウントの削除', () {
    testWidgets('2段階の確認を経てから削除する', (tester) async {
      final env = TestEnv();
      await pumpSettings(tester, env);

      await tapAndSettle(tester, find.text('アカウントを削除'));
      expect(find.text('アカウントを削除しますか？'), findsOneWidget);
      await tapAndSettle(tester, find.text('次へ'));
      expect(find.text('本当に削除しますか？'), findsOneWidget);
      expect(env.auth.deleteCalls, 0, reason: '最後の確認まで削除しない');

      await tapAndSettle(tester, find.text('削除する'));
      expect(env.auth.deleteCalls, 1);
      expect(find.text('削除しています…'), findsNothing, reason: '完了したら進捗の表示を閉じる');
    });

    testWidgets('途中でキャンセルしたら削除しない', (tester) async {
      final env = TestEnv();
      await pumpSettings(tester, env);

      await tapAndSettle(tester, find.text('アカウントを削除'));
      await tapAndSettle(tester, find.text('次へ'));
      await tapAndSettle(tester, find.text('キャンセル'));

      expect(env.auth.deleteCalls, 0);
    });

    testWidgets('削除中は進捗を出し、失敗したら閉じて知らせる', (tester) async {
      final env = TestEnv();
      final pending = Completer<void>();
      env.auth.onDelete = () => pending.future;
      await pumpSettings(tester, env);

      await tapAndSettle(tester, find.text('アカウントを削除'));
      await tapAndSettle(tester, find.text('次へ'));
      await tester.tap(find.text('削除する'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('削除しています…'), findsOneWidget);

      pending.completeError(Exception('unavailable'));
      await tester.pumpAndSettle();

      expect(find.text('削除しています…'), findsNothing);
      expect(find.textContaining('削除できませんでした'), findsOneWidget);
    });
  });
}
