import 'dart:async';

import 'package:flutter/material.dart';

/// 読み込み中の表示。
class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

/// 読み込みに失敗したときの表示。
///
/// StreamBuilder/FutureBuilder でエラーを見ずに hasData だけで分岐すると、
/// 権限エラーや通信エラーのとき無限ローディングのまま固まる（aimaruで実際に
/// 起きた）。読み込む画面は必ずこれを出すこと。
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 40,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 4),
            Text(
              '電波の良いところで開き直してください。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('再読み込み'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Firestoreへの書き込みを待たずに進め、失敗したときだけ知らせる。
///
/// Firestoreの書き込みは端末内（画面）にはすぐ反映されるが、Futureはサーバーに
/// 届くまで完了しない。電波の無い場所で完了を待つと「保存中」のまま固まるため、
/// 待たずに画面を進める。失敗（ルールで拒否された等）したときだけスナックバーで
/// 知らせる。[messenger] は画面を閉じる前に取っておくこと（閉じた画面の
/// contextからは引けない）。
void saveInBackground(
  ScaffoldMessengerState messenger,
  Future<void> write, {
  required String failureMessage,
}) {
  unawaited(
    write.then(
      (_) {},
      onError: (Object error, StackTrace stack) {
        debugPrint('[保存に失敗] $error\n$stack');
        messenger.showSnackBar(SnackBar(content: Text(failureMessage)));
      },
    ),
  );
}
