import 'dart:math';

import 'package:flutter/material.dart';

import '../logic/date_keys.dart';
import '../logic/formatters.dart';
import '../models/weight_log.dart';
import '../theme/app_theme.dart';

/// 体重の推移の折れ線グラフ。目標体重があれば破線で重ねる。
///
/// 横軸は [start]〜[end] の日付で、記録の無い日は線をつなぐだけにする
/// （毎日測っていなくても推移が読めるように）。
class WeightLineChart extends StatelessWidget {
  const WeightLineChart({
    super.key,
    required this.logs,
    required this.start,
    required this.end,
    this.targetKg,
    this.height = 180,
  });

  /// 期間内の記録（順不同でよい）。
  final List<WeightLog> logs;
  final DateTime start;
  final DateTime end;
  final double? targetKg;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final points = [
      for (final log in logs)
        if (tryParseDateKey(log.dateKey) case final date?)
          (date: date, kg: log.weightKg),
    ]..sort((a, b) => a.date.compareTo(b.date));
    return Semantics(
      label: '体重の推移のグラフ。記録は${points.length}件',
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _LinePainter(
            points: points,
            start: dateOnly(start),
            end: dateOnly(end),
            targetKg: targetKg,
            lineColor: theme.colorScheme.primary,
            targetColor: AppColors.over,
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

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.points,
    required this.start,
    required this.end,
    required this.targetKg,
    required this.lineColor,
    required this.targetColor,
    required this.gridColor,
    required this.labelStyle,
  });

  final List<({DateTime date, double kg})> points;
  final DateTime start;
  final DateTime end;
  final double? targetKg;
  final Color lineColor;
  final Color targetColor;
  final Color gridColor;
  final TextStyle labelStyle;

  static const _leftLabelWidth = 36.0;
  static const _bottomLabelHeight = 18.0;
  static const _verticalPadding = 10.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final values = [for (final p in points) p.kg, ?targetKg];
    var lo = values.reduce(min);
    var hi = values.reduce(max);
    // 変化が小さくても線が潰れないよう、最低2kg幅は取る
    if (hi - lo < 2) {
      final mid = (hi + lo) / 2;
      lo = mid - 1;
      hi = mid + 1;
    }
    lo = (lo - 0.5).floorToDouble();
    hi = (hi + 0.5).ceilToDouble();

    final chartLeft = _leftLabelWidth;
    final chartWidth = size.width - chartLeft - 8;
    final chartTop = _verticalPadding;
    final chartHeight = size.height - _bottomLabelHeight - _verticalPadding * 2;
    final totalDays = max(1, end.difference(start).inHours / 24);

    double xOf(DateTime d) =>
        chartLeft + chartWidth * (d.difference(start).inHours / 24) / totalDays;
    double yOf(double kg) =>
        chartTop + chartHeight * (1 - (kg - lo) / (hi - lo));

    // 目盛り（上・中・下）
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final kg in [lo, (lo + hi) / 2, hi]) {
      final y = yOf(kg);
      canvas.drawLine(Offset(chartLeft, y), Offset(size.width, y), grid);
      _drawText(canvas, formatGrams(kg), Offset(0, y - 7));
    }

    // 目標体重
    final target = targetKg;
    if (target != null) {
      final ty = yOf(target);
      final paint = Paint()
        ..color = targetColor.withValues(alpha: 0.7)
        ..strokeWidth = 1.5;
      const dash = 6.0;
      for (var x = chartLeft; x < size.width; x += dash * 2) {
        canvas.drawLine(
          Offset(x, ty),
          Offset(min(x + dash, size.width), ty),
          paint,
        );
      }
    }

    // 折れ線と点
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final o = Offset(xOf(points[i].date), yOf(points[i].kg));
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
    final dot = Paint()..color = lineColor;
    for (final p in points) {
      canvas.drawCircle(Offset(xOf(p.date), yOf(p.kg)), 3.5, dot);
    }

    // 期間の両端の日付
    final labelY = size.height - _bottomLabelHeight + 4;
    _drawText(canvas, formatDateShort(start), Offset(chartLeft, labelY));
    _drawText(
      canvas,
      formatDateShort(end),
      Offset(size.width, labelY),
      alignRight: true,
    );
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset at, {
    bool alignRight = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(alignRight ? at.dx - painter.width : at.dx, at.dy),
    );
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.points != points ||
      old.targetKg != targetKg ||
      old.start != start ||
      old.end != end ||
      old.lineColor != lineColor;
}
