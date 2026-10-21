import 'package:flutter/material.dart';

import '../logic/date_keys.dart';
import '../logic/energy_calculator.dart';
import '../logic/formatters.dart';
import '../models/user_profile.dart';
import '../models/weight_log.dart';
import '../services/app_services.dart';
import '../widgets/async_views.dart';
import '../widgets/weight_line_chart.dart';

/// 体重: 最新の値・BMI・目標までの差、推移のグラフ、記録の一覧。
class WeightScreen extends StatefulWidget {
  const WeightScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<WeightScreen> createState() => _WeightScreenState();
}

class _WeightScreenState extends State<WeightScreen> {
  Stream<List<WeightLog>>? _logs;

  /// グラフの期間（日）。0はすべて。
  int _range = 30;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _logs ??= AppScope.of(context).weights.watchLogs();
  }

  Future<void> _openEditor(List<WeightLog> logs, {WeightLog? existing}) async {
    final services = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final today = services.today();
    final result = await showDialog<WeightLog>(
      context: context,
      builder: (_) => WeightDialog(
        initialDate: existing == null
            ? today
            : tryParseDateKey(existing.dateKey) ?? today,
        today: today,
        // 未記録の日の初期値は直近の体重（毎日の入力は前日との差が小さいので、直すだけで済む）
        fallbackKg: logs.isNotEmpty
            ? logs.first.weightKg
            : widget.profile.weightKg,
        existing: {for (final l in logs) l.dateKey: l.weightKg},
      ),
    );
    if (result == null) return;
    saveInBackground(
      messenger,
      services.weights.saveLog(result.dateKey, result.weightKg, current: logs),
      failureMessage: '体重を保存できませんでした',
    );
    final date = tryParseDateKey(result.dateKey);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '${date == null ? '' : relativeDayLabel(date, today)}の体重（${formatWeight(result.weightKg)}kg）を記録しました',
          ),
        ),
      );
  }

  Future<void> _delete(List<WeightLog> logs, WeightLog log) async {
    final services = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final date = tryParseDateKey(log.dateKey);
    final label = date == null
        ? log.dateKey
        : relativeDayLabel(date, services.today());
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$labelの記録を削除しますか？'),
        content: Text('${formatWeight(log.weightKg)} kg'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除する'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    saveInBackground(
      messenger,
      services.weights.deleteLog(log.dateKey, current: logs),
      failureMessage: '削除できませんでした',
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<WeightLog>>(
      stream: _logs,
      builder: (context, snapshot) {
        final logs = snapshot.data;
        return Scaffold(
          appBar: AppBar(title: const Text('体重')),
          floatingActionButton: logs == null
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _openEditor(logs),
                  icon: const Icon(Icons.add),
                  label: const Text('記録する'),
                ),
          body: snapshot.hasError
              ? ErrorView(
                  message: '体重の記録を読み込めませんでした',
                  onRetry: () => setState(
                    () => _logs = AppScope.of(context).weights.watchLogs(),
                  ),
                )
              : logs == null
              ? const LoadingView()
              : _buildBody(context, logs),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, List<WeightLog> logs) {
    final theme = Theme.of(context);
    final today = AppScope.of(context).today();
    final profile = widget.profile;
    final oldest = logs.isEmpty ? null : tryParseDateKey(logs.last.dateKey);
    final start = _range == 0
        ? (oldest ?? today)
        : addDays(today, -(_range - 1));
    final startKey = dateKeyOf(start);
    final inRange = logs
        .where((l) => l.dateKey.compareTo(startKey) >= 0)
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      children: [
        _SummaryCard(logs: logs, profile: profile),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('推移', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 30, label: Text('30日')),
                    ButtonSegment(value: 90, label: Text('90日')),
                    ButtonSegment(value: 0, label: Text('すべて')),
                  ],
                  selected: {_range},
                  onSelectionChanged: (s) => setState(() => _range = s.first),
                ),
                const SizedBox(height: 16),
                if (inRange.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'この期間の記録はありません。\n右下の「記録する」から体重を記録すると、推移がグラフで見られます。',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  )
                else
                  WeightLineChart(
                    logs: inRange,
                    start: start,
                    end: today,
                    targetKg: profile.targetWeightKg,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('記録', style: theme.textTheme.titleMedium),
        if (logs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('まだ記録がありません', style: theme.textTheme.bodyMedium),
          ),
        for (var i = 0; i < logs.length; i++)
          _LogTile(
            log: logs[i],
            previous: i + 1 < logs.length ? logs[i + 1] : null,
            today: today,
            onTap: () => _openEditor(logs, existing: logs[i]),
            onDelete: () => _delete(logs, logs[i]),
          ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.logs, required this.profile});

  final List<WeightLog> logs;
  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final current = logs.isNotEmpty ? logs.first.weightKg : profile.weightKg;
    final change = logs.length >= 2
        ? logs[0].weightKg - logs[1].weightKg
        : null;
    final bmi = bodyMassIndex(weightKg: current, heightCm: profile.heightCm);
    final target = profile.targetWeightKg;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _Stat(
                label: '現在',
                value: '${formatWeight(current)} kg',
                caption: change == null
                    ? null
                    : '前回比 ${formatSignedWeight(change)}',
              ),
            ),
            Expanded(
              child: _Stat(
                label: 'BMI',
                value: formatWeight(bmi),
                caption: bmiCategory(bmi),
              ),
            ),
            if (target != null)
              Expanded(
                child: _Stat(
                  label: '目標 ${formatWeight(target)}kg',
                  value: (target - current).abs() < 0.05
                      ? '達成'
                      : '${formatSignedWeight(target - current)} kg',
                  caption: (target - current).abs() < 0.05
                      ? 'おめでとうございます'
                      : 'まであと',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.caption});

  final String label;
  final String value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (caption != null)
          Text(
            caption!,
            style: theme.textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({
    required this.log,
    required this.previous,
    required this.today,
    required this.onTap,
    required this.onDelete,
  });

  final WeightLog log;
  final WeightLog? previous;
  final DateTime today;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final date = tryParseDateKey(log.dateKey);
    final prev = previous;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      title: Text(date == null ? log.dateKey : relativeDayLabel(date, today)),
      subtitle: prev == null
          ? null
          : Text('前回比 ${formatSignedWeight(log.weightKg - prev.weightKg)} kg'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${formatWeight(log.weightKg)} kg',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          IconButton(
            onPressed: onDelete,
            tooltip: '削除',
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

/// 体重の入力ダイアログ。記録する日付と体重を返す。
class WeightDialog extends StatefulWidget {
  const WeightDialog({
    super.key,
    required this.initialDate,
    required this.today,
    required this.fallbackKg,
    required this.existing,
  });

  final DateTime initialDate;
  final DateTime today;

  /// 未記録の日を選んだときの初期値
  final double fallbackKg;

  /// 記録済みの日付 → 体重（その日を選んだら記録済みの値を出す）
  final Map<String, double> existing;

  @override
  State<WeightDialog> createState() => _WeightDialogState();
}

class _WeightDialogState extends State<WeightDialog> {
  late DateTime _date = widget.initialDate;
  late final _kg = TextEditingController(
    text: formatWeight(_initialKgFor(_date)),
  );
  String? _error;

  double _initialKgFor(DateTime date) =>
      widget.existing[dateKeyOf(date)] ?? widget.fallbackKg;

  @override
  void dispose() {
    _kg.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      // 未来の体重は記録できない（「現在の体重」が狂うため）
      lastDate: widget.today,
      helpText: '記録する日',
    );
    if (picked == null) return;
    setState(() {
      _date = picked;
      _kg.text = formatWeight(_initialKgFor(picked));
    });
  }

  void _submit() {
    final kg = parseNumberInput(_kg.text);
    if (kg == null || kg < kMinWeightKg || kg > kMaxWeightKg) {
      setState(
        () => _error =
            '${kMinWeightKg.toInt()}〜${kMaxWeightKg.toInt()}kgで入力してください',
      );
      return;
    }
    Navigator.of(
      context,
    ).pop(WeightLog(dateKey: dateKeyOf(_date), weightKg: kg));
  }

  @override
  Widget build(BuildContext context) {
    final recorded = widget.existing.containsKey(dateKeyOf(_date));
    return AlertDialog(
      title: const Text('体重を記録'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
            label: Text(formatDateLong(_date)),
          ),
          if (recorded)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'この日は記録済みです。上書きします',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _kg,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: '体重',
              suffixText: 'kg',
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(onPressed: _submit, child: const Text('記録する')),
      ],
    );
  }
}
