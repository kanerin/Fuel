import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/nutrition_estimator.dart';

/// きょう画面の下部に常に出している「食べたものを書く欄」。
///
/// 送信するとAIがPFCを推定する。カメラボタンで食事の写真も添えられる。
class FoodInputBar extends StatelessWidget {
  const FoodInputBar({
    super.key,
    required this.controller,
    required this.image,
    required this.busy,
    required this.onSubmit,
    required this.onPickPhoto,
    required this.onRemovePhoto,
  });

  final TextEditingController controller;
  final EstimateImage? image;

  /// 推定中（入力・送信を止める）
  final bool busy;
  final VoidCallback onSubmit;
  final VoidCallback onPickPhoto;
  final VoidCallback onRemovePhoto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final photo = image;
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (photo != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 0, 8),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        photo.bytes,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox.square(
                          dimension: 48,
                          child: Icon(Icons.image_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '写真を添えて推定します',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    IconButton(
                      onPressed: busy ? null : onRemovePhoto,
                      tooltip: '写真を外す',
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: busy ? null : onPickPhoto,
                  tooltip: '写真から推定',
                  icon: const Icon(Icons.photo_camera_outlined),
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    enabled: !busy,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSubmit(),
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(kMaxEstimateTextLength),
                    ],
                    decoration: const InputDecoration(
                      hintText: '食べたものを入力（例: 牛丼並盛と味噌汁）',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  )
                else
                  ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) {
                      final canSend =
                          controller.text.trim().isNotEmpty || photo != null;
                      return IconButton.filled(
                        onPressed: canSend ? onSubmit : null,
                        tooltip: 'AIでPFCを推定',
                        icon: const Icon(Icons.auto_awesome),
                      );
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
