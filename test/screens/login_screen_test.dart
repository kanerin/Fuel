import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/screens/login_screen.dart';
import 'package:fuel/services/auth_service.dart';

import '../helpers/fake_services.dart';
import '../helpers/pump.dart';

void main() {
  setUpAll(setUpScreenTests);

  testWidgets('アプリ名・できること・ログインボタン・注意書きを出す', (tester) async {
    await pumpApp(
      tester,
      TestEnv(auth: FakeAuthService()),
      const LoginScreen(),
    );

    expect(find.text('Fuel'), findsOneWidget);
    expect(find.text('Googleでログイン'), findsOneWidget);
    expect(find.textContaining('医療上の助言ではありません'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ログイン中はボタンの代わりにローディングを出す（二重に押せない）', (tester) async {
    final auth = FakeAuthService();
    final pending = Completer<AppUser?>();
    auth.onSignIn = () => pending.future;
    await pumpApp(tester, TestEnv(auth: auth), const LoginScreen());

    await tester.tap(find.text('Googleでログイン'));
    await tester.pump();

    expect(find.text('Googleでログイン'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    pending.complete(null); // キャンセル
    await tester.pumpAndSettle();
    expect(find.text('Googleでログイン'), findsOneWidget);
    expect(auth.signInCalls, 1);
  });

  testWidgets('ログインに失敗したら知らせて、もう一度押せるようにする', (tester) async {
    final auth = FakeAuthService()
      ..onSignIn = () async => throw Exception('network');
    await pumpApp(tester, TestEnv(auth: auth), const LoginScreen());

    await tester.tap(find.text('Googleでログイン'));
    await tester.pumpAndSettle();

    expect(find.textContaining('ログインに失敗しました'), findsOneWidget);
    expect(find.text('Googleでログイン'), findsOneWidget);
  });
}
