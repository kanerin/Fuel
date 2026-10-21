import 'package:flutter/material.dart';

import '../logic/formatters.dart';
import '../models/meal_entry.dart';
import '../models/nutrition.dart';
import '../theme/app_theme.dart';
import 'nutrition_summary_card.dart';

IconData mealTypeIcon(MealType type) => switch (type) {
  MealType.breakfast => Icons.free_breakfast_outlined,
  MealType.lunch => Icons.lunch_dining_outlined,
  MealType.dinner => Icons.dinner_dining_outlined,
  MealType.snack => Icons.cookie_outlined,
};

/// 食事区分ごとの記録の一覧（きょう画面）。
class MealSection extends StatelessWidget {
  const MealSection({
    super.key,
    required this.type,
    required this.entries,
    required this.subtotal,
    required this.onAdd,
    required this.onTapEntry,
    required this.onDeleteEntry,
  });

  final MealType type;
  final List<MealEntry> entries;
  final Nutrition subtotal;
  final VoidCallback onAdd;
  final ValueChanged<MealEntry> onTapEntry;
  final ValueChanged<MealEntry> onDeleteEntry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
            child: Row(
              children: [
                Icon(
                  mealTypeIcon(type),
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(type.label, style: theme.textTheme.titleSmall),
                const Spacer(),
                if (entries.isNotEmpty)
                  Text(
                    '${formatKcal(subtotal.calories)} kcal',
                    style: theme.textTheme.bodyMedium,
                  ),
                IconButton(
                  onPressed: onAdd,
                  tooltip: '${type.label}に追加',
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
          ),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                'まだ記録がありません',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          for (final entry in entries)
            Dismissible(
              key: ValueKey(entry.id),
              direction: DismissDirection.endToStart,
              background: Container(
                color: theme.colorScheme.errorContainer,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                child: Icon(
                  Icons.delete_outline,
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
              onDismissed: (_) => onDeleteEntry(entry),
              child: EntryTile(entry: entry, onTap: () => onTapEntry(entry)),
            ),
          if (entries.isNotEmpty) const SizedBox(height: 4),
        ],
      ),
    );
  }
}

/// 記録1品の行。
class EntryTile extends StatelessWidget {
  const EntryTile({super.key, required this.entry, required this.onTap});

  final MealEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final food = entry.food;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      visualDensity: VisualDensity.compact,
      title: Row(
        children: [
          Flexible(
            child: Text(
              food.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (food.amount.isNotEmpty) ...[
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                food.amount,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
          if (entry.source == EntrySource.ai) ...[
            const SizedBox(width: 6),
            const AiBadge(),
          ],
        ],
      ),
      subtitle: MacroText(entry.nutrition),
      trailing: Text(
        '${formatKcal(entry.nutrition.calories)} kcal',
        style: theme.textTheme.titleSmall,
      ),
    );
  }
}

/// AIの推定値であることを示す小さな印。
class AiBadge extends StatelessWidget {
  const AiBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'AIによる推定値',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'AI',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: scheme.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}

/// 合計の行（AIの推定結果・追加シートで使う）。
class NutritionTotalRow extends StatelessWidget {
  const NutritionTotalRow({
    super.key,
    required this.label,
    required this.nutrition,
  });

  final String label;
  final Nutrition nutrition;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(label, style: theme.textTheme.titleSmall),
        const SizedBox(width: 12),
        Expanded(
          child: MacroText(nutrition, style: theme.textTheme.bodyMedium),
        ),
        Text(
          '${formatKcal(nutrition.calories)} kcal',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.seed,
          ),
        ),
      ],
    );
  }
}
