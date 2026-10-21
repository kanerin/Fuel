import 'package:flutter/material.dart';

import '../logic/energy_calculator.dart';
import '../logic/formatters.dart';
import '../models/user_profile.dart';
import '../theme/app_theme.dart';
import 'nutrition_summary_card.dart';

/// 1日の目安（基礎代謝量・消費カロリー・目標摂取カロリー・PFCの目標）の表。
/// プロフィール入力のプレビューと設定画面で使う。
class TargetsSummary extends StatelessWidget {
  const TargetsSummary({super.key, required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = calculateTargets(profile);
    final ratio = profile.pfcRatio;
    final adjustment = t.dailyAdjustment;
    final caption = t.isCustom
        ? '手動で設定した値'
        : adjustment == 0
        ? '消費カロリーと同じ（維持）'
        : '消費カロリー ${adjustment < 0 ? '−' : '+'} ${formatKcal(adjustment.abs())} kcal'
              '（週${formatPace(profile.weeklyRateKg)}kgペース）';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Row(label: '基礎代謝量', value: '${formatKcal(t.bmr)} kcal'),
        _Row(label: '1日の消費カロリー', value: '${formatKcal(t.tdee)} kcal'),
        _Row(
          label: '目標摂取カロリー',
          value: '${formatKcal(t.calories)} kcal',
          emphasized: true,
          caption: caption,
        ),
        const Divider(height: 20),
        _MacroRow(
          color: AppColors.protein,
          short: 'P',
          label: 'たんぱく質',
          grams: t.protein,
          percent: ratio.protein,
        ),
        _MacroRow(
          color: AppColors.fat,
          short: 'F',
          label: '脂質',
          grams: t.fat,
          percent: ratio.fat,
        ),
        _MacroRow(
          color: AppColors.carbs,
          short: 'C',
          label: '炭水化物',
          grams: t.carbs,
          percent: ratio.carbs,
        ),
        if (t.raisedToBmr)
          const _Note(
            icon: Icons.info_outline,
            text: 'このペースだと基礎代謝量を下回るため、目標を基礎代謝量まで引き上げています。',
          ),
        if (t.isBelowBmr)
          _Note(
            icon: Icons.warning_amber_outlined,
            color: theme.colorScheme.error,
            text: '目標が基礎代謝量を下回っています。極端な制限は体調を崩す原因になります。',
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.emphasized = false,
    this.caption,
  });

  final String label;
  final String value;
  final bool emphasized;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
              Text(
                value,
                style: emphasized
                    ? theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      )
                    : theme.textTheme.titleMedium,
              ),
            ],
          ),
          if (caption != null)
            Text(
              caption!,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

class _MacroRow extends StatelessWidget {
  const _MacroRow({
    required this.color,
    required this.short,
    required this.label,
    required this.grams,
    required this.percent,
  });

  final Color color;
  final String short;
  final String label;
  final double grams;
  final int percent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          MacroDot(color: color, label: short),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text('${formatGrams(grams)} g', style: theme.textTheme.titleMedium),
          SizedBox(
            width: 52,
            child: Text(
              '（$percent%）',
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: c),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: c),
            ),
          ),
        ],
      ),
    );
  }
}
