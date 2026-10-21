import 'package:flutter/material.dart';

import '../logic/daily_summary.dart';
import '../logic/date_keys.dart';
import '../logic/energy_calculator.dart';
import '../models/meal_entry.dart';
import '../models/user_profile.dart';
import '../services/app_services.dart';
import '../services/nutrition_estimator.dart';
import '../services/photo_picker.dart';
import '../widgets/async_views.dart';
import '../widgets/food_input_bar.dart';
import '../widgets/meal_section.dart';
import '../widgets/nutrition_summary_card.dart';
import 'entry_form_screen.dart';
import 'estimate_result_sheet.dart';
import 'quick_add_sheet.dart';

const kNoFoodFoundMessage = '食べ物を読み取れませんでした。書き方を変えてお試しください。';

/// きょう画面: 1日の摂取量と目標、食事区分ごとの記録、食べたものを書く欄。
class TodayScreen extends StatefulWidget {
  const TodayScreen({
    super.key,
    required this.profile,
    this.openDate,
    this.openRequest = 0,
  });

  final UserProfile profile;

  /// 履歴画面からの「この日を開いて」という依頼（[openRequest] が変わったときだけ従う）。
  final DateTime? openDate;
  final int openRequest;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> with WidgetsBindingObserver {
  DateTime? _date;

  /// 今日を表示しているか。日付が変わってからアプリに戻ったとき、
  /// 今日を見ていたなら新しい今日へ切り替える（昨日の画面のまま記録しないように）。
  bool _followToday = true;

  final _input = TextEditingController();
  EstimateImage? _image;
  bool _estimating = false;

  String? _streamKey;
  Stream<List<MealEntry>>? _stream;

  /// スワイプで削除した記録。Firestoreの反映を待たずに一覧から消す
  /// （Dismissibleは、消した行が次のフレームでも残っているとエラーになる）。
  final _hiddenIds = <String>{};

  AppServices get _services => AppScope.of(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _date ??= _services.today();
  }

  @override
  void didUpdateWidget(TodayScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final requested = widget.openDate;
    if (widget.openRequest != oldWidget.openRequest && requested != null) {
      _setDate(requested);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_followToday) return;
    final today = _services.today();
    if (!isSameDay(today, _date!)) setState(() => _date = today);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _input.dispose();
    super.dispose();
  }

  void _setDate(DateTime date) {
    setState(() {
      _date = dateOnly(date);
      _followToday = isSameDay(_date!, _services.today());
    });
  }

  Stream<List<MealEntry>> _entriesFor(String dateKey) {
    if (_streamKey != dateKey || _stream == null) {
      _streamKey = dateKey;
      _stream = _services.meals.watchDay(dateKey);
    }
    return _stream!;
  }

  Future<void> _pickDate() async {
    final today = _services.today();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date!,
      firstDate: DateTime(2000),
      lastDate: addDays(today, 365),
      helpText: '表示する日',
    );
    if (picked != null) _setDate(picked);
  }

  Future<void> _estimate() async {
    final text = _input.text.trim();
    final image = _image;
    if (_estimating || (text.isEmpty && image == null)) return;
    FocusScope.of(context).unfocus();
    final services = _services;
    final messenger = ScaffoldMessenger.of(context);
    final date = _date!;
    setState(() => _estimating = true);

    NutritionEstimate estimate;
    try {
      estimate = await services.estimator.estimate(text: text, image: image);
    } catch (e) {
      if (!mounted) return;
      setState(() => _estimating = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is NutritionEstimateException
                ? e.message
                : kEstimateFailedMessage,
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _estimating = false);

    if (estimate.items.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            estimate.note.isNotEmpty ? estimate.note : kNoFoodFoundMessage,
          ),
        ),
      );
      return;
    }

    final added = await showEstimateResultSheet(
      context,
      estimate: estimate,
      dateKey: dateKeyOf(date),
      dateLabel: _titleFor(date, services.today()),
      initialMealType: MealType.suggestFor(services.now()),
    );
    // 追加したら入力欄を空にする。キャンセルなら書いた文章を残し、言い直せるようにする
    if (added == true && mounted) {
      _input.clear();
      setState(() => _image = null);
    }
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<PhotoSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('カメラで撮る'),
              onTap: () => Navigator.pop(context, PhotoSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('アルバムから選ぶ'),
              onTap: () => Navigator.pop(context, PhotoSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final image = await _services.photoPicker.pick(source);
      if (image != null && mounted) setState(() => _image = image);
    } catch (e) {
      debugPrint('[写真の読み込みに失敗] $e');
      messenger.showSnackBar(const SnackBar(content: Text('写真を読み込めませんでした')));
    }
  }

  void _delete(MealEntry entry) {
    final services = _services;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _hiddenIds.add(entry.id));
    saveInBackground(
      messenger,
      services.meals.deleteEntry(entry),
      failureMessage: '削除できませんでした',
    );
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('「${entry.food.name}」を削除しました'),
          action: SnackBarAction(
            label: '元に戻す',
            onPressed: () {
              if (mounted) setState(() => _hiddenIds.remove(entry.id));
              saveInBackground(
                messenger,
                services.meals.restoreEntry(entry),
                failureMessage: '元に戻せませんでした',
              );
            },
          ),
        ),
      );
  }

  void _edit(MealEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EntryFormScreen.edit(entry: entry),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = _services;
    final today = services.today();
    final date = _date!;
    final dateKey = dateKeyOf(date);
    final targets = calculateTargets(widget.profile);
    final isToday = isSameDay(date, today);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          onPressed: () => _setDate(addDays(date, -1)),
          tooltip: '前の日',
          icon: const Icon(Icons.chevron_left),
        ),
        title: TextButton.icon(
          onPressed: _pickDate,
          icon: const Icon(Icons.calendar_today_outlined, size: 18),
          label: Text(
            _titleFor(date, today),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        actions: [
          if (!isToday)
            TextButton(
              onPressed: () => _setDate(today),
              child: const Text('今日へ'),
            ),
          IconButton(
            onPressed: () => _setDate(addDays(date, 1)),
            tooltip: '次の日',
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      body: StreamBuilder<List<MealEntry>>(
        // 日付ごとに作り直す（前の日の記録が新しい日付の下に一瞬出ないように）
        key: ValueKey(dateKey),
        stream: _entriesFor(dateKey),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorView(
              message: '記録を読み込めませんでした',
              onRetry: () => setState(() => _stream = null),
            );
          }
          if (!snapshot.hasData) return const LoadingView();
          final entries = snapshot.data!
              .where((e) => !_hiddenIds.contains(e.id))
              .toList();
          final summary = DailySummary.of(entries);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              NutritionSummaryCard(consumed: summary.total, targets: targets),
              const SizedBox(height: 12),
              if (summary.isEmpty) ...[
                const _HintCard(),
                const SizedBox(height: 12),
              ],
              for (final type in MealType.values) ...[
                MealSection(
                  type: type,
                  entries: summary.entriesFor(type),
                  subtotal: summary.totalFor(type),
                  onAdd: () => showQuickAddSheet(
                    context,
                    dateKey: dateKey,
                    mealType: type,
                  ),
                  onTapEntry: _edit,
                  onDeleteEntry: _delete,
                ),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
      bottomNavigationBar: FoodInputBar(
        controller: _input,
        image: _image,
        busy: _estimating,
        onSubmit: _estimate,
        onPickPhoto: _pickPhoto,
        onRemovePhoto: () => setState(() => _image = null),
      ),
    );
  }
}

/// 「今日 10月21日(水)」「10月19日(月)」
String _titleFor(DateTime date, DateTime today) {
  final label = relativeDayLabel(date, today);
  return const ['今日', '昨日', '明日'].contains(label)
      ? '$label ${formatDateJa(date)}'
      : label;
}

class _HintCard extends StatelessWidget {
  const _HintCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.auto_awesome,
              color: theme.colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '下の欄に食べたものを書くと、AIがカロリーとPFCを計算します。\n'
                '例:「トースト1枚とゆで卵」「ラーメン大盛り」「コンビニのサラダチキン」',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
