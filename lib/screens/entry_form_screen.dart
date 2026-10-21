import 'package:flutter/material.dart';

import '../models/food_item.dart';
import '../models/meal_entry.dart';
import '../models/nutrition.dart';
import '../services/app_services.dart';
import '../services/favorite_repository.dart';
import '../widgets/async_views.dart';
import '../widgets/food_form.dart';

/// 記録の手入力（新規）と編集。
class EntryFormScreen extends StatefulWidget {
  /// 手入力で新しく記録する。
  const EntryFormScreen.create({
    super.key,
    required String this.dateKey,
    required MealType this.mealType,
  }) : entry = null;

  /// 記録済みの1品を直す・削除する。
  const EntryFormScreen.edit({super.key, required MealEntry this.entry})
    : dateKey = null,
      mealType = null;

  final MealEntry? entry;
  final String? dateKey;
  final MealType? mealType;

  @override
  State<EntryFormScreen> createState() => _EntryFormScreenState();
}

class _EntryFormScreenState extends State<EntryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _form = FoodFormController(widget.entry?.food);
  late MealType _mealType = widget.entry?.mealType ?? widget.mealType!;
  bool _alsoFavorite = false;
  Stream<List<FavoriteFood>>? _favorites;

  bool get _isEdit => widget.entry != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isEdit) _favorites ??= AppScope.of(context).favorites.watchFavorites();
  }

  @override
  void dispose() {
    _form.dispose();
    super.dispose();
  }

  /// 入力欄の内容を検証して返す（エラーがあれば欄の下に出してnull）。
  FoodItem? _validFood() {
    if (!_formKey.currentState!.validate()) return null;
    final food = _form.tryBuild();
    if (food == null || validateFoodItem(food) != null) return null;
    return food;
  }

  void _save() {
    final food = _validFood();
    if (food == null) return;
    final services = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final entry = widget.entry;
    if (entry == null) {
      final entries = services.meals.buildEntries(
        dateKey: widget.dateKey!,
        mealType: _mealType,
        foods: [food],
        source: EntrySource.manual,
      );
      saveInBackground(
        messenger,
        services.meals.saveEntries(entries),
        failureMessage: '記録を保存できませんでした',
      );
      if (_alsoFavorite) {
        saveInBackground(
          messenger,
          services.favorites.addFavorite(food),
          failureMessage: 'お気に入りに登録できませんでした',
        );
      }
      messenger.showSnackBar(
        SnackBar(content: Text('${_mealType.label}に「${food.name}」を追加しました')),
      );
    } else {
      saveInBackground(
        messenger,
        services.meals.updateEntry(
          entry.copyWith(mealType: _mealType, food: food),
        ),
        failureMessage: '記録を保存できませんでした',
      );
      messenger.showSnackBar(const SnackBar(content: Text('保存しました')));
    }
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final entry = widget.entry!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('この記録を削除しますか？'),
        content: Text('「${entry.food.name}」'),
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
    if (ok != true || !mounted) return;
    final services = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    saveInBackground(
      messenger,
      services.meals.deleteEntry(entry),
      failureMessage: '削除できませんでした',
    );
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text('「${entry.food.name}」を削除しました'),
        action: SnackBarAction(
          label: '元に戻す',
          onPressed: () => saveInBackground(
            messenger,
            services.meals.restoreEntry(entry),
            failureMessage: '元に戻せませんでした',
          ),
        ),
      ),
    );
  }

  /// お気に入りの登録・解除。対象は入力欄の今の内容（名前と量でお気に入りを見分ける）。
  void _toggleFavorite({required bool isFavorite, required String id}) {
    final services = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (isFavorite) {
      saveInBackground(
        messenger,
        services.favorites.deleteFavorite(id),
        failureMessage: 'お気に入りから外せませんでした',
      );
      messenger.showSnackBar(const SnackBar(content: Text('お気に入りから外しました')));
      return;
    }
    final food = _validFood();
    if (food == null) return;
    saveInBackground(
      messenger,
      services.favorites.addFavorite(food),
      failureMessage: 'お気に入りに登録できませんでした',
    );
    messenger.showSnackBar(
      SnackBar(content: Text('「${food.name}」をお気に入りに登録しました')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '記録を編集' : '手入力で追加'),
        actions: [
          if (_isEdit) ...[
            StreamBuilder<List<FavoriteFood>>(
              stream: _favorites,
              builder: (context, snapshot) {
                // 読めない間（エラー含む）はボタンを出さない。お気に入りの状態が
                // 分からないまま押させると、登録と解除を取り違える
                final favorites = snapshot.data;
                if (favorites == null) return const SizedBox.shrink();
                return ListenableBuilder(
                  listenable: Listenable.merge([_form.name, _form.amount]),
                  builder: (context, _) {
                    final id = favoriteIdFor(
                      FoodItem(
                        name: _form.name.text,
                        amount: _form.amount.text,
                        nutrition: Nutrition.zero,
                      ),
                    );
                    final isFavorite = favorites.any((f) => f.id == id);
                    return IconButton(
                      onPressed: () =>
                          _toggleFavorite(isFavorite: isFavorite, id: id),
                      tooltip: isFavorite ? 'お気に入りから外す' : 'お気に入りに登録',
                      icon: Icon(isFavorite ? Icons.star : Icons.star_border),
                    );
                  },
                );
              },
            ),
            IconButton(
              onPressed: _delete,
              tooltip: '削除',
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ],
      ),
      body: Form(
        key: _formKey,
        // ListViewだと画面外の入力欄が作られず、Formの検証から漏れる（エラーが出ない）ため、
        // 入力欄はすべて常に作っておく
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FoodFormFields(controller: _form),
              const SizedBox(height: 20),
              Text('食事の区分', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<MealType>(
                showSelectedIcon: false,
                segments: [
                  for (final t in MealType.values)
                    ButtonSegment(value: t, label: Text(t.label)),
                ],
                selected: {_mealType},
                onSelectionChanged: (s) => setState(() => _mealType = s.first),
              ),
              if (!_isEdit)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _alsoFavorite,
                  onChanged: (v) => setState(() => _alsoFavorite = v ?? false),
                  title: const Text('お気に入りにも登録する'),
                ),
              if (_isEdit && widget.entry!.source == EntrySource.ai)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'この記録はAIの推定値です。栄養成分表示などで分かる場合は値を直してください。',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(_isEdit ? '保存する' : '追加する'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
