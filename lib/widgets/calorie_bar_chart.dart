import 'dart:math';

import 'package:flutter/material.dart';

import '../logic/daily_summary.dart';
import '../logic/date_keys.dart';
import '../logic/formatters.dart';
import '../theme/app_theme.dart';

/// 日ごとの摂取カロリーの棒グラフ。目標カロリーを破線で重ねる。
class CalorieBarChart extends StatelessWidget {
  const CalorieBarChart({
    super.key,
    required this.days,
    required this.targetCalories,
    this.height = 180,
  });

  /// 古い順。
  final List<DayTotal> days;
  final int targetCalories;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recorded = days.where((d) => d.hasRecords).length;
    return Semantics(
      label:
          '${days.length}日間の摂取カロリーのグラフ。記録のある日は$recorded日、'
          '目標は${formatKcal(targetCalories)}キロカロリー',
      container: true,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _BarChartPainter(
            days: days,
            target: targetCalories.toDouble(),
            barColor: theme.colorScheme.primary,
            overColor: AppColors.over,
            gridColor: theme.colorScheme.outlineVariant,
            labelStyle: theme.textTheme.labelSmall!.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  _BarChartPainter({
    required this.days,
    required this.target,
    required this.barColor,
    required this.overColor,
    required this.gridColor,
    required this.labelStyle,
  });

  final List<DayTotal> days;
  final double target;
  final Color barColor;
  final Color overColor;
  final Color gridColor;
  final TextStyle labelStyle;

  static const _bottomLabelHeight = 18.0;
  static const _topPadding = 16.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;
    final chartHeight = size.height - _bottomLabelHeight - _topPadding;
    final maxValue = max(
      target * 1.25,
      days.map((d) => d.total.calories).fold<double>(0, max) * 1.1,
    );
    if (maxValue <= 0) return;
    double yOf(double v) => _topPadding + chartHeight * (1 - v / maxValue);

    // 基準線
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, yOf(0)), Offset(size.width, yOf(0)), grid);

    // 棒
    final slot = size.width / days.length;
    final barWidth = min(28.0, slot * 0.6);
    final labelEvery = days.length <= 7 ? 1 : (days.length / 6).ceil();
    for (var i = 0; i < days.length; i++) {
      final day = days[i];
      final cx = slot * i + slot / 2;
      if (day.hasRecords) {
        final kcal = day.total.calories;
        final rect = RRect.fromRectAndCorners(
          Rect.fromLTRB(
            cx - barWidth / 2,
            yOf(kcal),
            cx + barWidth / 2,
            yOf(0),
          ),
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        );
        canvas.drawRRect(
          rect,
          Paint()..color = kcal > target ? overColor : barColor,
        );
      }
      // 日付のラベル。30日表示では間引く。最新の日から数えて等間隔に出すので、
      // 最新の日には必ずラベルが付き、ラベル同士が重ならない。
      if ((days.length - 1 - i) % labelEvery == 0) {
        final date = tryParseDateKey(day.dateKey);
        if (date != null) {
          _drawText(
            canvas,
            days.length <= 7 ? formatDateShort(date) : '${date.day}',
            Offset(cx, size.height - _bottomLabelHeight + 4),
          );
        }
      }
    }

    // 目標の破線
    final targetPaint = Paint()
      ..color = overColor.withValues(alpha: 0.7)
      ..strokeWidth = 1.5;
    final ty = yOf(target);
    const dash = 6.0;
    for (var x = 0.0; x < size.width; x += dash * 2) {
      canvas.drawLine(
        Offset(x, ty),
        Offset(min(x + dash, size.width), ty),
        targetPaint,
      );
    }
    _drawText(
      canvas,
      '目標 ${formatKcal(target)}',
      Offset(size.width, ty - 14),
      alignRight: true,
    );
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset anchor, {
    bool alignRight = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = alignRight
        ? anchor.dx - painter.width
        : anchor.dx - painter.width / 2;
    painter.paint(canvas, Offset(dx, anchor.dy));
  }

  @override
  bool shouldRepaint(_BarChartPainter old) =>
      old.days != days || old.target != target || old.barColor != barColor;
}
