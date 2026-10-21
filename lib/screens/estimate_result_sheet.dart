import 'package:flutter/material.dart';

import '../logic/formatters.dart';
import '../models/food_item.dart';
import '../models/meal_entry.dart';
import '../models/nutrition.dart';
import '../services/app_services.dart';
import '../services/nutrition_estimator.dart';
import '../widgets/async_views.dart';
import '../widgets/meal_section.dart';
import '../widgets/nutrition_summary_card.dart';
import 'food_edit_screen.dart';

/// AIの推定結果を見せ、選んだ品を記録に追加するボトムシート。
/// 追加したらtrueを返す。
Future<bool?> showEstimateResultSheet(
  BuildContext context, {
  required NutritionEstimate estimate,
  required String dateKey,
  required String dateLabel,
  required MealType initialMealType,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => EstimateResultSheet(
    estimate: estimate,
    dateKey: dateKey,
    dateLabel: dateLabel,
    initialMealType: initialMealType,
  ),
);

class EstimateResultSheet extends StatefulWidget {
  const EstimateResultSheet({
    super.key,
    required this.estimate,
    required this.dateKey,
    required this.dateLabel,
    required this.initialMealType,
  });

  final NutritionEstimate estimate;
  final String dateKey;
  final String dateLabel;
  final MealType initialMealType;

  @override
  State<EstimateResultSheet> createState() => _EstimateResultSheetState();
}

class _EstimateResultSheetState extends State<EstimateResultSheet> {
  late final List<FoodItem> _items = [...widget.estimate.items];
  late final List<bool> _checked = List.filled(_items.length, true);
  late MealType _mealType = widget.initialMealType;

  List<FoodItem> get _selected => [
    for (var i = 0; i < _items.length; i++)
      if (_checked[i]) _items[i],
  ];

  Future<void> _edit(int index) async {
    final edited = await Navigator.of(context).push<FoodItem>(
      MaterialPageRoute(builder: (_) => FoodEditScreen(initial: _items[index])),
    );
    if (edited != null && mounted) {
      setState(() {
        _items[index] = edited;
        _checked[index] = true;
      });
    }
  }

  void _add() {
    final foods = _selected;
    if (foods.isEmpty) return;
    final services = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final entries = services.meals.buildEntries(
      dateKey: widget.dateKey,
      mealType: _mealType,
      foods: foods,
      source: EntrySource.ai,
    );
    saveInBackground(
      messenger,
      services.meals.saveEntries(entries),
      failureMessage: '記録を保存できませんでした',
    );
    Navigator.of(context).pop(true);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${_mealType.label}に${entries.length}品を追加しました'),
          action: SnackBarAction(
            label: '元に戻す',
            onPressed: () {
              for (final e in entries) {
                saveInBackground(
                  messenger,
                  services.meals.deleteEntry(e),
                  failureMessage: '元に戻せませんでした',
                );
              }
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selected;
    final total = selected.fold(Nutrition.zero, (sum, f) => sum + f.nutrition);
    final note = widget.estimate.note;
    final remaining = widget.estimate.remainingToday;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('AIの推定結果', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            '${widget.dateLabel}の記録に追加します',
            style: theme.textTheme.bodySmall,
          ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(note, style: theme.textTheme.bodySmall)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _items.length,
              itemBuilder: (context, i) {
                final item = _items[i];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () => setState(() => _checked[i] = !_checked[i]),
                  leading: Checkbox(
                    value: _checked[i],
                    onChanged: (v) => setState(() => _checked[i] = v ?? false),
                  ),
                  title: Text(
                    item.amount.isEmpty
                        ? item.name
                        : '${item.name}（${item.amount}）',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: MacroText(item.nutrition),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${formatKcal(item.nutrition.calories)} kcal',
                        style: theme.textTheme.titleSmall,
                      ),
                      IconButton(
                        onPressed: () => _edit(i),
                        tooltip: '「${item.name}」の値を直す',
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const Divider(),
          NutritionTotalRow(label: '合計', nutrition: total),
          const SizedBox(height: 12),
          SegmentedButton<MealType>(
            showSelectedIcon: false,
            segments: [
              for (final t in MealType.values)
                ButtonSegment(value: t, label: Text(t.label)),
            ],
            selected: {_mealType},
            onSelectionChanged: (s) => setState(() => _mealType = s.first),
          ),
          const SizedBox(height: 8),
          Text(
            'AIによる推定値です。実際の値とは異なることがあります。'
            '${remaining != null ? '（今日のAI推定の残り $remaining回）' : ''}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('キャンセル'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: selected.isEmpty ? null : _add,
                icon: const Icon(Icons.add),
                label: Text(
                  selected.isEmpty ? '追加する' : '${selected.length}品を追加',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
