import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/services/app_services.dart';
import 'package:fuel/theme/app_theme.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fake_services.dart';

/// 画面のテストの前準備（日付の日本語表記）。setUpAll から呼ぶ。
Future<void> setUpScreenTests() => initializeDateFormatting('ja');

/// 画面を、アプリ本体と同じ設定（テーマ・日本語化・AppScope）で描画する。
///
/// [phoneSize] を true にすると、一般的なAndroidスマートフォン（360×780dp）の
/// 大きさで描画する。日本語は文字幅が広く、テストの既定（800×600）では
/// 起きないはみ出しが実機で起きるため、主要な画面はこの大きさでも確かめる。
Future<void> pumpApp(
  WidgetTester tester,
  TestEnv env,
  Widget home, {
  bool phoneSize = true,
  double textScale = 1.0,
}) async {
  if (phoneSize) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }
  await tester.pumpWidget(
    AppScope(
      services: env.services,
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ja'),
        supportedLocales: const [Locale('ja')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  // FakeFirebaseFirestoreのストリームは購読の直後に非同期で最初の値を流す
  await tester.pump();
  await tester.pump();
}

/// hintTextで入力欄を特定する（このリポジトリの画面はテスト用のKeyを持たない方針）。
Finder textFieldWithHint(String hintPrefix) => find.byWidgetPredicate(
  (w) =>
      w is TextField && (w.decoration?.hintText ?? '').startsWith(hintPrefix),
  description: 'hintTextが「$hintPrefix」で始まるTextField',
);

/// labelTextで入力欄を特定する。
Finder textFieldWithLabel(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
  description: 'labelTextが「$label」のTextField',
);

/// 1×1の透明なPNG（Image.memoryに渡せる本物の画像データ）。
final tinyPng = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];
