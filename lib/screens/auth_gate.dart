import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../services/app_services.dart';
import '../services/auth_service.dart';
import '../widgets/async_views.dart';
import 'home_shell.dart';
import 'login_screen.dart';
import 'profile_form_screen.dart';

/// 起動時の振り分け: 未ログイン → ログイン、プロフィール未入力 → はじめに、
/// それ以外 → ホーム。
///
/// ルーターのリダイレクトではなくストリームで切り替えるので、ログアウトや
/// 退会、別の端末でのプロフィール変更にも画面がそのまま追従する。
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  Stream<AppUser?>? _authChanges;
  String? _lastUid;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _authChanges ??= AppScope.of(context).auth.authStateChanges();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppUser?>(
      stream: _authChanges,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Scaffold(body: ErrorView(message: 'ログイン状態を確認できませんでした'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: LoadingView());
        }
        final user = snapshot.data;
        if (user == null) {
          if (_lastUid != null) {
            // ログアウト・退会したとき、ホームの上に開いていた画面（設定から
            // 開いた画面など）が残らないよう、ルートまで戻す
            _lastUid = null;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
            });
          }
          return const LoginScreen();
        }
        _lastUid = user.uid;
        // 別のアカウントでログインし直したとき、前の人の画面の状態を引き継がない
        return ProfileGate(key: ValueKey(user.uid));
      },
    );
  }
}

/// プロフィールの有無で、はじめに（入力）とホームを切り替える。
class ProfileGate extends StatefulWidget {
  const ProfileGate({super.key});

  @override
  State<ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<ProfileGate> {
  Stream<UserProfile?>? _profile;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _profile ??= AppScope.of(context).profiles.watchProfile();
  }

  void _retry() {
    setState(() => _profile = AppScope.of(context).profiles.watchProfile());
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UserProfile?>(
      stream: _profile,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: ErrorView(message: 'プロフィールを読み込めませんでした', onRetry: _retry),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: LoadingView());
        }
        final profile = snapshot.data;
        if (profile == null) return const ProfileFormScreen();
        return HomeShell(profile: profile);
      },
    );
  }
}
