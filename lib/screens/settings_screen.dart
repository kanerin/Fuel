import 'dart:async';

import 'package:flutter/material.dart';

import '../logic/date_keys.dart';
import '../logic/formatters.dart';
import '../models/user_profile.dart';
import '../services/app_services.dart';
import '../services/profile_repository.dart';
import '../widgets/targets_summary.dart';
import 'favorites_screen.dart';
import 'profile_form_screen.dart';

/// 設定: 1日の目安・プロフィールと目標・お気に入り・AIの残り回数・アカウント。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _usageKey;
  Stream<AiUsage>? _usage;

  Stream<AiUsage> _usageFor(String todayKey) {
    if (_usageKey != todayKey || _usage == null) {
      _usageKey = todayKey;
      _usage = AppScope.of(context).profiles.watchAiUsage(todayKey);
    }
    return _usage!;
  }

  Future<void> _signOut() async {
    final services = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ログアウトしますか？'),
        content: const Text('記録はアカウントに保存されているので、もう一度ログインすれば続きから使えます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ログアウト'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      // 成功するとAuthGateがログイン画面へ切り替える
      await services.auth.signOut();
    } catch (e) {
      debugPrint('[ログアウトに失敗] $e');
      messenger.showSnackBar(const SnackBar(content: Text('ログアウトできませんでした')));
    }
  }

  Future<void> _deleteAccount() async {
    final services = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final errorColor = Theme.of(context).colorScheme.error;

    // 取り消せない操作なので2段階で確認する
    final first = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('アカウントを削除しますか？'),
        content: const Text('食事・体重・お気に入りの記録と、アカウントがすべて削除されます。この操作は取り消せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('次へ'),
          ),
        ],
      ),
    );
    if (first != true || !mounted) return;
    final second = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('本当に削除しますか？'),
        content: const Text('削除した記録は復元できません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: errorColor),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除する'),
          ),
        ],
      ),
    );
    if (second != true || !mounted) return;

    // 削除はサーバーで行うので完了まで待つ（オフラインでは失敗して知らせる）。
    // 進捗のダイアログ自体は待たず、削除が終わったらこちらから閉じる
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Expanded(child: Text('削除しています…')),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      await services.auth.deleteAccount();
      navigator.pop(); // 進捗のダイアログを閉じる。ログイン画面へはAuthGateが切り替える
    } catch (e) {
      debugPrint('[アカウントの削除に失敗] $e');
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('削除できませんでした。通信状態を確認して、もう一度お試しください。')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final services = AppScope.of(context);
    final user = services.auth.currentUser;
    final profile = widget.profile;
    final usage = _usageFor(dateKeyOf(services.today()));

    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('1日の目安', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TargetsSummary(profile: profile),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outline),
            title: const Text('プロフィールと目標'),
            subtitle: Text(profileSummary(profile)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ProfileFormScreen(initial: profile),
              ),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.star_outline),
            title: const Text('お気に入りの食品'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const FavoritesScreen()),
            ),
          ),
          StreamBuilder<AiUsage>(
            stream: usage,
            builder: (context, snapshot) {
              final data = snapshot.data;
              final value = snapshot.hasError
                  ? '確認できません'
                  : data == null
                  ? '…'
                  : '${data.remaining} / ${data.limit}回';
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.auto_awesome_outlined),
                title: const Text('今日のAI推定の残り回数'),
                subtitle: const Text('毎日0時（日本時間）にリセットされます'),
                trailing: Text(value, style: theme.textTheme.titleSmall),
              );
            },
          ),
          const _Header('アカウント'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.account_circle_outlined),
            title: Text(user?.email ?? user?.displayName ?? 'ログイン中'),
            subtitle: const Text('Googleアカウントでログイン中'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.logout),
            title: const Text('ログアウト'),
            onTap: _signOut,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.delete_forever_outlined,
              color: theme.colorScheme.error,
            ),
            title: Text(
              'アカウントを削除',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            onTap: _deleteAccount,
          ),
          const _Header('このアプリについて'),
          const ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.only(bottom: 12),
            leading: Icon(Icons.functions),
            title: Text('計算方法'),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '・基礎代謝量: Mifflin-St Jeor式（男性 10×体重＋6.25×身長−5×年齢＋5、女性は＋5の代わりに−161）\n'
                '・1日の消費カロリー: 基礎代謝量 × 運動の頻度の係数（1.2〜1.9）\n'
                '・目標摂取カロリー: 体脂肪1kg＝7,200kcalとして、週のペースを1日あたりに換算して増減。'
                '減量で基礎代謝量を下回る場合は基礎代謝量まで引き上げます\n'
                '・PFCの目標: 目標摂取カロリー × 比率 ÷ 4（P・C）または 9（F）',
              ),
            ],
          ),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.info_outline),
            title: Text('注意事項'),
            subtitle: Text(
              'AIの推定値・目標値は一般的な目安で、正確さを保証するものではありません。'
              '医療上の助言ではないため、持病がある方や妊娠中の方は医師に相談してください。',
            ),
          ),
        ],
      ),
    );
  }
}

/// 「男性・35歳・170cm・70.0kg / 適度な運動・減量（ふつう 週0.5kg）」
String profileSummary(UserProfile p) {
  final goal = p.goal == GoalType.maintain
      ? p.goal.label
      : '${p.goal.label}（${paceLabel(p.weeklyRateKg)} 週${formatPace(p.weeklyRateKg)}kg）';
  return '${p.sex.label}・${p.age}歳・${formatGrams(p.heightCm)}cm・${formatWeight(p.weightKg)}kg\n'
      '${p.activityLevel.label}・$goal';
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}
