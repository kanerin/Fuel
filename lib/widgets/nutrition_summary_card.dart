import 'dart:math';

import 'package:flutter/material.dart';

import '../logic/daily_summary.dart';
import '../logic/energy_calculator.dart';
import '../logic/formatters.dart';
import '../models/nutrition.dart';
import '../theme/app_theme.dart';

/// 1日の摂取量と目標の比較（カロリーのリングとPFCのバー）。
class NutritionSummaryCard extends StatelessWidget {
  const NutritionSummaryCard({
    super.key,
    required this.consumed,
    required this.targets,
  });

  final Nutrition consumed;
  final NutritionTargets targets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = targets.calories - consumed.calories;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          children: [
            Row(
              children: [
                CalorieRing(
                  consumed: consumed.calories,
                  target: targets.calories.toDouble(),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _LabeledValue(
                        label: '食べた',
                        value: '${formatKcal(consumed.calories)} kcal',
                      ),
                      const SizedBox(height: 6),
                      _LabeledValue(
                        label: '目標',
                        value: '${formatKcal(targets.calories)} kcal',
                      ),
                      const SizedBox(height: 6),
                      _LabeledValue(
                        label: remaining >= 0 ? 'あと' : '超過',
                        value: '${formatKcal(remaining.abs())} kcal',
                        color: remaining >= 0
                            ? theme.colorScheme.primary
                            : AppColors.over,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            MacroBar(
              label: 'たんぱく質',
              short: 'P',
              color: AppColors.protein,
              consumed: consumed.protein,
              target: targets.protein,
            ),
            const SizedBox(height: 10),
            MacroBar(
              label: '脂質',
              short: 'F',
              color: AppColors.fat,
              consumed: consumed.fat,
              target: targets.fat,
            ),
            const SizedBox(height: 10),
            MacroBar(
              label: '炭水化物',
              short: 'C',
              color: AppColors.carbs,
              consumed: consumed.carbs,
              target: targets.carbs,
            ),
          ],
        ),
      ),
    );
  }
}

class _LabeledValue extends StatelessWidget {
  const _LabeledValue({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        SizedBox(
          width: 40,
          child: Text(label, style: theme.textTheme.bodySmall),
        ),
        Flexible(
          child: Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// 摂取カロリーのリング。中央に「あと◯kcal」または「◯kcal超過」を出す。
class CalorieRing extends StatelessWidget {
  const CalorieRing({
    super.key,
    required this.consumed,
    required this.target,
    this.size = 112,
  });

  final double consumed;
  final double target;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = progressOf(consumed, target);
    final over = progress > 1;
    final percent = (progress * 100).round();
    return Semantics(
      label: '目標カロリーの$percent%',
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _RingPainter(
            progress: progress,
            trackColor: theme.colorScheme.surfaceContainerHighest,
            color: over ? AppColors.over : theme.colorScheme.primary,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$percent%',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: over ? AppColors.over : null,
                  ),
                ),
                Text('目標比', style: theme.textTheme.labelSmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.trackColor,
    required this.color,
  });

  final double progress;
  final Color trackColor;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 10.0;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(arcRect, 0, 2 * pi, false, track);
    if (progress <= 0) return;
    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    canvas.drawArc(arcRect, -pi / 2, 2 * pi * min(progress, 1), false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.trackColor != trackColor;
}

/// PFCの1本のバー（摂取量 / 目標量）。
class MacroBar extends StatelessWidget {
  const MacroBar({
    super.key,
    required this.label,
    required this.short,
    required this.color,
    required this.consumed,
    required this.target,
  });

  final String label;
  final String short;
  final Color color;
  final double consumed;
  final double target;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = progressOf(consumed, target);
    final over = progress > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            MacroDot(color: color, label: short),
            const SizedBox(width: 6),
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            Text(
              '${formatGrams(consumed)} / ${formatGrams(target)} g',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: over ? AppColors.over : null,
                fontWeight: over ? FontWeight.w600 : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: min(progress, 1),
            minHeight: 8,
            color: color,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}

/// P・F・Cの頭文字を丸で囲んだ印。
class MacroDot extends StatelessWidget {
  const MacroDot({super.key, required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    width: 20,
    height: 20,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    child: Text(
      label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}

/// 「P 22 · F 22 · C 90」の1行表示。
class MacroText extends StatelessWidget {
  const MacroText(this.nutrition, {super.key, this.style});

  final Nutrition nutrition;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.bodySmall;
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          _part('P', nutrition.protein, AppColors.protein),
          const TextSpan(text: ' · '),
          _part('F', nutrition.fat, AppColors.fat),
          const TextSpan(text: ' · '),
          _part('C', nutrition.carbs, AppColors.carbs),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  TextSpan _part(String label, double grams, Color color) => TextSpan(
    children: [
      TextSpan(
        text: label,
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
      TextSpan(text: ' ${formatGrams(grams)}'),
    ],
  );
}
