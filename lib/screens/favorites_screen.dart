import 'package:flutter/material.dart';

import '../logic/formatters.dart';
import '../models/food_item.dart';
import '../services/app_services.dart';
import '../widgets/async_views.dart';
import '../widgets/nutrition_summary_card.dart';
import 'food_edit_screen.dart';

/// お気に入りの食品の管理（一覧・登録・削除）。
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  Stream<List<FavoriteFood>>? _favorites;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _favorites ??= AppScope.of(context).favorites.watchFavorites();
  }

  Future<void> _add() async {
    final services = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final food = await Navigator.of(context).push<FoodItem>(
      MaterialPageRoute(
        builder: (_) => const FoodEditScreen(title: 'お気に入りを登録'),
      ),
    );
    if (food == null) return;
    saveInBackground(
      messenger,
      services.favorites.addFavorite(food),
      failureMessage: 'お気に入りに登録できませんでした',
    );
    messenger.showSnackBar(SnackBar(content: Text('「${food.name}」を登録しました')));
  }

  void _delete(FavoriteFood favorite) {
    final services = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    saveInBackground(
      messenger,
      services.favorites.deleteFavorite(favorite.id),
      failureMessage: '削除できませんでした',
    );
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('「${favorite.food.name}」をお気に入りから外しました'),
          action: SnackBarAction(
            label: '元に戻す',
            onPressed: () => saveInBackground(
              messenger,
              services.favorites.restoreFavorite(favorite),
              failureMessage: '元に戻せませんでした',
            ),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('お気に入りの食品')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('登録する'),
      ),
      body: StreamBuilder<List<FavoriteFood>>(
        stream: _favorites,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const ErrorView(message: 'お気に入りを読み込めませんでした');
          }
          final favorites = snapshot.data;
          if (favorites == null) return const LoadingView();
          if (favorites.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'よく食べるものを登録しておくと、食事区分の「＋」から1タップで記録できます。\n'
                  '記録を編集する画面の ☆ からも登録できます。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: favorites.length,
            itemBuilder: (context, i) {
              final favorite = favorites[i];
              final food = favorite.food;
              return ListTile(
                title: Text(
                  food.amount.isEmpty
                      ? food.name
                      : '${food.name}（${food.amount}）',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: MacroText(food.nutrition),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${formatKcal(food.nutrition.calories)} kcal',
                      style: theme.textTheme.titleSmall,
                    ),
                    IconButton(
                      onPressed: () => _delete(favorite),
                      tooltip: '「${food.name}」をお気に入りから外す',
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
