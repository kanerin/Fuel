import 'package:flutter/material.dart';

import '../services/app_services.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _loading = false;

  Future<void> _signIn() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _loading = true);
    try {
      // 成功するとAuthGateがホーム（初回ははじめに）へ切り替える。
      // キャンセルされた場合（null）は何もせずこの画面に留まる。
      await AppScope.of(context).auth.signInWithGoogle();
    } catch (e) {
      debugPrint('[ログインに失敗] $e');
      messenger.showSnackBar(
        const SnackBar(content: Text('ログインに失敗しました。通信状態を確認して、もう一度お試しください。')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Icon(
                      Icons.restaurant,
                      size: 44,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Fuel',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '食べたものを書くだけで、AIがPFCを計算',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 32),
                  const _Feature(
                    icon: Icons.auto_awesome_outlined,
                    text: '文章や写真から、カロリーとPFC（たんぱく質・脂質・炭水化物）を推定',
                  ),
                  const _Feature(
                    icon: Icons.track_changes_outlined,
                    text: '年齢・体重・運動の頻度から、1日の消費カロリーと目標を計算',
                  ),
                  const _Feature(
                    icon: Icons.show_chart,
                    text: '食事と体重の記録をグラフでふりかえり',
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : FilledButton.icon(
                            onPressed: _signIn,
                            icon: const Icon(Icons.login),
                            label: const Text('Googleでログイン'),
                          ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'AIの推定値や目標値は目安です。医療上の助言ではありません。',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
