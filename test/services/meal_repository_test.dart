import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/models/meal_entry.dart';
import 'package:fuel/models/nutrition.dart';
import 'package:fuel/services/meal_repository.dart';

import '../helpers/fake_services.dart';
import '../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late MealRepository repo;

  setUp(() {
    env = TestEnv();
    repo = env.services.meals;
  });

  Future<List<MealEntry>> addAll(
    List<({String name, double kcal})> foods, {
    String dateKey = '2026-10-21',
    MealType mealType = MealType.lunch,
  }) async {
    final entries = repo.buildEntries(
      dateKey: dateKey,
      mealType: mealType,
      foods: [for (final f in foods) food(f.name, kcal: f.kcal)],
      source: EntrySource.ai,
    );
    await repo.saveEntries(entries);
    return entries;
  }

  group('buildEntries / saveEntries', () {
    test('渡した順に記録し、その日の一覧に記録した順で出る', () async {
      await addAll([(name: '牛丼', kcal: 650), (name: '味噌汁', kcal: 40)]);

      final day = await repo.watchDay('2026-10-21').first;
      expect(day.map((e) => e.food.name), ['牛丼', '味噌汁']);
      expect(day.every((e) => e.mealType == MealType.lunch), isTrue);
      expect(day.every((e) => e.source == EntrySource.ai), isTrue);
    });

    test('保存前に名前の空白を落とし、値を丸める', () async {
      final entries = repo.buildEntries(
        dateKey: '2026-10-21',
        mealType: MealType.snack,
        foods: [food('  プロテイン ', amount: ' 1杯 ', kcal: 120.4, p: 24.06)],
        source: EntrySource.manual,
      );
      await repo.saveEntries(entries);

      final saved = (await repo.watchDay('2026-10-21').first).single;
      expect(saved.food.name, 'プロテイン');
      expect(saved.food.amount, '1杯');
      expect(saved.nutrition, const Nutrition(calories: 120, protein: 24.1));
    });

    test('返した記録のIDで保存される（書き込みを待たずに「元に戻す」に使える）', () async {
      final entries = await addAll([(name: '牛丼', kcal: 650)]);

      final saved = (await repo.watchDay('2026-10-21').first).single;
      expect(saved.id, entries.single.id);
    });
  });

  group('watchDay / watchRange', () {
    test('watchDay はその日の記録だけ', () async {
      await addAll([(name: '昨日の夕食', kcal: 700)], dateKey: '2026-10-20');
      await addAll([(name: '今日の昼食', kcal: 650)]);

      final day = await repo.watchDay('2026-10-21').first;
      expect(day.map((e) => e.food.name), ['今日の昼食']);
    });

    test('watchRange は両端の日を含む', () async {
      for (final key in [
        '2026-10-14',
        '2026-10-15',
        '2026-10-21',
        '2026-10-22',
      ]) {
        await addAll([(name: key, kcal: 100)], dateKey: key);
      }

      final range = await repo.watchRange('2026-10-15', '2026-10-21').first;
      expect(range.map((e) => e.dateKey).toSet(), {'2026-10-15', '2026-10-21'});
    });
  });

  group('updateEntry / deleteEntry / restoreEntry', () {
    test('値と食事区分を更新できる', () async {
      final original = (await addAll([(name: '牛丼', kcal: 650)])).single;

      await repo.updateEntry(
        original.copyWith(
          mealType: MealType.dinner,
          food: original.food.copyWith(
            nutrition: original.nutrition.scaled(1.5),
          ),
        ),
      );

      final saved = (await repo.watchDay('2026-10-21').first).single;
      expect(saved.mealType, MealType.dinner);
      expect(saved.nutrition.calories, 975);
    });

    test('削除して、元に戻せる（同じIDで書き戻す）', () async {
      final original = (await addAll([(name: '牛丼', kcal: 650)])).single;

      await repo.deleteEntry(original);
      expect(await repo.watchDay('2026-10-21').first, isEmpty);

      await repo.restoreEntry(original);
      final restored = (await repo.watchDay('2026-10-21').first).single;
      expect(restored.id, original.id);
      expect(restored.food, original.food);
    });
  });

  group('recentFoods', () {
    test('新しい順に、同じ名前と量のものは1つにまとめる', () async {
      env.now = DateTime(2026, 10, 20, 8);
      await addAll([(name: 'おにぎり', kcal: 180)], dateKey: '2026-10-20');
      env.now = DateTime(2026, 10, 20, 12);
      await addAll([(name: 'サラダ', kcal: 80)], dateKey: '2026-10-20');
      env.now = DateTime(2026, 10, 21, 8);
      await addAll([(name: 'おにぎり', kcal: 180)]);

      final recent = await repo.recentFoods();
      expect(recent.map((f) => f.name), ['おにぎり', 'サラダ']);
    });

    test('件数の上限を守る', () async {
      for (var i = 0; i < 5; i++) {
        env.now = DateTime(2026, 10, 21, 8, i);
        await addAll([(name: '食品$i', kcal: 100)]);
      }

      final recent = await repo.recentFoods(limit: 3);
      expect(recent.map((f) => f.name), ['食品4', '食品3', '食品2']);
    });

    test('記録が無ければ空', () async {
      expect(await repo.recentFoods(), isEmpty);
    });
  });
}
