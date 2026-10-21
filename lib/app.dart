import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/auth_gate.dart';
import 'services/app_services.dart';
import 'theme/app_theme.dart';

class FuelApp extends StatelessWidget {
  const FuelApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    // AppScopeはMaterialAppより上に置く（pushした画面からも見えるように）
    return AppScope(
      services: services,
      child: MaterialApp(
        title: 'Fuel',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        // 日付ピッカーなどFlutter標準のダイアログも日本語にする
        // （localizationsDelegatesを渡さないと英語のまま出る）
        locale: const Locale('ja'),
        supportedLocales: const [Locale('ja')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const AuthGate(),
      ),
    );
  }
}
