import 'package:flutter/material.dart';

import '../logic/daily_summary.dart';
import '../logic/date_keys.dart';
import '../logic/energy_calculator.dart';
import '../logic/formatters.dart';
import '../models/meal_entry.dart';
import '../models/user_profile.dart';
import '../services/app_services.dart';
import '../theme/app_theme.dart';
import '../widgets/async_views.dart';
import '../widgets/calorie_bar_chart.dart';
import '../widgets/nutrition_summary_card.dart';

/// 履歴: 直近7日／30日の摂取カロリー・PFCのふりかえり。
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.profile,
    required this.onOpenDay,
  });

  final UserProfile profile;

  /// 日ごとの一覧をタップしたとき（その日の「きょう」画面を開く）。
  final ValueChanged<DateTime> onOpenDay;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  int _days = 7;
  String? _streamKey;
  Stream<List<MealEntry>>? _stream;

  Stream<List<MealEntry>> _entriesFor(String startKey, String endKey) {
    final key = '$startKey..$endKey';
    if (_streamKey != key || _stream == null) {
      _streamKey = key;
      _stream = AppScope.of(context).meals.watchRange(startKey, endKey);
    }
    return _stream!;
  }

  @override
  Widget build(BuildContext context) {
    final today = AppScope.of(context).today();
    final keys = lastNDateKeys(today, _days);
    final targets = calculateTargets(widget.profile);
    final stream = _entriesFor(keys.first, keys.last);

    return Scaffold(
      appBar: AppBar(title: const Text('履歴')),
      body: StreamBuilder<List<MealEntry>>(
        // 期間を切り替えたら作り直す（前の期間の集計が一瞬出ないように）
        key: ValueKey(_streamKey),
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorView(
              message: '履歴を読み込めませんでした',
              onRetry: () => setState(() => _stream = null),
            );
          }
          if (!snapshot.hasData) return const LoadingView();
          final period = summarizePeriod(keys, snapshot.data!);
          final theme = Theme.of(context);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 7, label: Text('7日')),
                  ButtonSegment(value: 30, label: Text('30日')),
                ],
                selected: {_days},
                onSelectionChanged: (s) => setState(() => _days = s.first),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('摂取カロリー', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 12),
                      CalorieBarChart(
                        days: period.days,
                        targetCalories: targets.calories,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        period.recordedDays == 0
                            ? 'この期間の記録はまだありません'
                            : '目標以内の日: ${period.daysWithinTarget(targets.calories)} / ${period.recordedDays}日'
                                  '（記録のある日）',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _AverageCard(
                period: period,
                targets: targets,
                ratio: widget.profile.pfcRatio,
              ),
              const SizedBox(height: 16),
              Text('日ごとの記録', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              for (final day in period.days.reversed)
                if (tryParseDateKey(day.dateKey) case final date?)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: () => widget.onOpenDay(date),
                    title: Text(relativeDayLabel(date, today)),
                    subtitle: day.hasRecords
                        ? MacroText(day.total)
                        : Text(
                            '記録なし',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                    trailing: day.hasRecords
                        ? Text(
                            '${formatKcal(day.total.calories)} kcal',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: day.total.calories > targets.calories
                                  ? AppColors.over
                                  : null,
                            ),
                          )
                        : const Icon(Icons.chevron_right),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _AverageCard extends StatelessWidget {
  const _AverageCard({
    required this.period,
    required this.targets,
    required this.ratio,
  });

  final PeriodSummary period;
  final NutritionTargets targets;
  final PfcRatio ratio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final average = period.average;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: average == null
            ? Text('記録を付けると、ここに1日あたりの平均が出ます', style: theme.textTheme.bodyMedium)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '1日あたりの平均（記録のある${period.recordedDays}日）',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  // 入りきらない（小さい画面・大きい文字）ときは目標を次の行へ送る
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    children: [
                      Text(
                        '${formatKcal(average.calories)} kcal',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '目標 ${formatKcal(targets.calories)} kcal',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  MacroBar(
                    label: 'たんぱく質',
                    short: 'P',
                    color: AppColors.protein,
                    consumed: average.protein,
                    target: targets.protein,
                  ),
                  const SizedBox(height: 10),
                  MacroBar(
                    label: '脂質',
                    short: 'F',
                    color: AppColors.fat,
                    consumed: average.fat,
                    target: targets.fat,
                  ),
                  const SizedBox(height: 10),
                  MacroBar(
                    label: '炭水化物',
                    short: 'C',
                    color: AppColors.carbs,
                    consumed: average.carbs,
                    target: targets.carbs,
                  ),
                  if (PfcShare.of(average) case final share?) ...[
                    const SizedBox(height: 16),
                    Text('PFCバランス', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    _ShareBar(
                      label: '実際',
                      protein: share.protein,
                      fat: share.fat,
                      carbs: share.carbs,
                    ),
                    const SizedBox(height: 6),
                    _ShareBar(
                      label: '目標',
                      protein: ratio.protein.toDouble(),
                      fat: ratio.fat.toDouble(),
                      carbs: ratio.carbs.toDouble(),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

/// PFCの比率を1本の帯で見せる。
class _ShareBar extends StatelessWidget {
  const _ShareBar({
    required this.label,
    required this.protein,
    required this.fat,
    required this.carbs,
  });

  final String label;
  final double protein;
  final double fat;
  final double carbs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget part(double percent, Color color, String short) => Expanded(
      flex: (percent * 10).round().clamp(1, 1000),
      child: Container(
        height: 22,
        color: color,
        alignment: Alignment.center,
        child: percent >= 12
            ? Text(
                '$short${percent.round()}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              )
            : null,
      ),
    );
    return Semantics(
      label:
          '$labelのPFC比率 たんぱく質${protein.round()}% 脂質${fat.round()}% 炭水化物${carbs.round()}%',
      container: true,
      excludeSemantics: true,
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Row(
                children: [
                  part(protein, AppColors.protein, 'P'),
                  part(fat, AppColors.fat, 'F'),
                  part(carbs, AppColors.carbs, 'C'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
