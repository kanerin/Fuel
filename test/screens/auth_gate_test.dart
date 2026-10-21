import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/screens/auth_gate.dart';
import 'package:fuel/screens/home_shell.dart';
import 'package:fuel/screens/login_screen.dart';
import 'package:fuel/screens/profile_form_screen.dart';

import '../helpers/fake_services.dart';
import '../helpers/fixtures.dart';
import '../helpers/pump.dart';

// 起動時の振り分け（未ログイン→ログイン、プロフィール未入力→はじめに、
// それ以外→ホーム）と、ログイン状態・プロフィールの変化への追従。
void main() {
  setUpAll(setUpScreenTests);

  testWidgets('未ログインならログイン画面', (tester) async {
    final env = TestEnv(auth: FakeAuthService());
    await pumpApp(tester, env, const AuthGate());

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Googleでログイン'), findsOneWidget);
  });

  testWidgets('ログイン済みでプロフィールが無ければ「はじめに」', (tester) async {
    final env = TestEnv();
    await pumpApp(tester, env, const AuthGate());

    expect(find.byType(ProfileFormScreen), findsOneWidget);
    expect(find.text('はじめに'), findsOneWidget);
  });

  testWidgets('プロフィールがあればホーム', (tester) async {
    final env = TestEnv();
    await env.seedProfile(sampleProfile);
    await pumpApp(tester, env, const AuthGate());

    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.text('今日 10月21日(水)'), findsOneWidget);
  });

  testWidgets('プロフィールの読み込みに失敗したら、無限ローディングではなくエラー表示', (tester) async {
    final env = TestEnv(profilesOverride: FailingProfileRepository.new);
    await pumpApp(tester, env, const AuthGate());

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('プロフィールを読み込めませんでした'), findsOneWidget);
  });

  testWidgets('ログインすると「はじめに」へ進み、プロフィールを保存するとホームへ切り替わる', (tester) async {
    final env = TestEnv(auth: FakeAuthService());
    await pumpApp(tester, env, const AuthGate());

    await tester.tap(find.text('Googleでログイン'));
    await tester.pumpAndSettle();
    expect(find.text('はじめに'), findsOneWidget);

    // 画面を通さずにプロフィールが保存された（別の端末で入力した）場合も追従する
    await env.seedProfile(sampleProfile);
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsOneWidget);
  });

  testWidgets('ログアウトしたらログイン画面へ戻り、開いていた画面も閉じる', (tester) async {
    final env = TestEnv();
    await env.seedProfile(sampleProfile);
    await pumpApp(tester, env, const AuthGate());

    // 設定タブからお気に入りの画面を開いた状態にする
    await tester.tap(find.text('設定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('お気に入りの食品'));
    await tester.pumpAndSettle();
    expect(find.text('お気に入りの食品'), findsOneWidget);

    env.auth.emit(null);
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('お気に入りの食品'), findsNothing);
  });
}
