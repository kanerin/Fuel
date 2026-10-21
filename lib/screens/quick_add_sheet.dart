import 'package:flutter/material.dart';

import '../logic/formatters.dart';
import '../models/food_item.dart';
import '../models/meal_entry.dart';
import '../services/app_services.dart';
import '../widgets/async_views.dart';
import '../widgets/nutrition_summary_card.dart';
import 'entry_form_screen.dart';

/// 食事区分の「＋」から開く追加シート（お気に入り・最近食べたもの・手入力）。
///
/// お気に入りと最近食べたものは1タップで記録でき、AIを呼ばないので
/// 1日の推定回数を消費しない。
Future<void> showQuickAddSheet(
  BuildContext context, {
  required String dateKey,
  required MealType mealType,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => QuickAddSheet(dateKey: dateKey, mealType: mealType),
);

class QuickAddSheet extends StatefulWidget {
  const QuickAddSheet({
    super.key,
    required this.dateKey,
    required this.mealType,
  });

  final String dateKey;
  final MealType mealType;

  @override
  State<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<QuickAddSheet> {
  Stream<List<FavoriteFood>>? _favorites;
  Future<List<FoodItem>>? _recent;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    _favorites ??= services.favorites.watchFavorites();
    // 「最近食べたもの」タブを開くまでFutureBuilderは購読しないので、その前に
    // 失敗すると拾い手のない例外になる。ignoreで処理済みにしておく（あとから
    // 購読したFutureBuilderにはエラーがそのまま届き、エラー表示になる）
    _recent ??= services.meals.recentFoods()..ignore();
  }

  void _add(FoodItem food, EntrySource source) {
    final services = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final entries = services.meals.buildEntries(
      dateKey: widget.dateKey,
      mealType: widget.mealType,
      foods: [food],
      source: source,
    );
    saveInBackground(
      messenger,
      services.meals.saveEntries(entries),
      failureMessage: '記録を保存できませんでした',
    );
    Navigator.of(context).pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${widget.mealType.label}に「${food.name}」を追加しました'),
          action: SnackBarAction(
            label: '元に戻す',
            onPressed: () => saveInBackground(
              messenger,
              services.meals.deleteEntry(entries.single),
              failureMessage: '元に戻せませんでした',
            ),
          ),
        ),
      );
  }

  void _openManual() {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => EntryFormScreen.create(
          dateKey: widget.dateKey,
          mealType: widget.mealType,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: DefaultTabController(
        length: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${widget.mealType.label}に追加',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _openManual,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('手入力'),
                  ),
                ],
              ),
            ),
            const TabBar(
              tabs: [
                Tab(text: 'お気に入り'),
                Tab(text: '最近食べたもの'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  StreamBuilder<List<FavoriteFood>>(
                    stream: _favorites,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const ErrorView(message: 'お気に入りを読み込めませんでした');
                      }
                      final favorites = snapshot.data;
                      if (favorites == null) return const LoadingView();
                      if (favorites.isEmpty) {
                        return const _Empty(
                          '記録を編集する画面の ☆ から、よく食べるものをお気に入りに登録できます',
                        );
                      }
                      return _FoodList(
                        foods: [for (final f in favorites) f.food],
                        onTap: (food) => _add(food, EntrySource.favorite),
                      );
                    },
                  ),
                  FutureBuilder<List<FoodItem>>(
                    future: _recent,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const ErrorView(message: '最近食べたものを読み込めませんでした');
                      }
                      final recent = snapshot.data;
                      if (recent == null) return const LoadingView();
                      if (recent.isEmpty) return const _Empty('まだ記録がありません');
                      return _FoodList(
                        foods: recent,
                        onTap: (food) => _add(food, EntrySource.recent),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FoodList extends StatelessWidget {
  const _FoodList({required this.foods, required this.onTap});

  final List<FoodItem> foods;
  final ValueChanged<FoodItem> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.builder(
      itemCount: foods.length,
      itemBuilder: (context, i) {
        final food = foods[i];
        return ListTile(
          onTap: () => onTap(food),
          title: Text(
            food.amount.isEmpty ? food.name : '${food.name}（${food.amount}）',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: MacroText(food.nutrition),
          trailing: Text(
            '${formatKcal(food.nutrition.calories)} kcal',
            style: theme.textTheme.titleSmall,
          ),
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    ),
  );
}
