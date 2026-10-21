import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/models/meal_entry.dart';
import 'package:fuel/models/nutrition.dart';

import '../helpers/fixtures.dart';

void main() {
  group('MealType.suggestFor', () {
    MealType at(int hour, [int minute = 0]) =>
        MealType.suggestFor(DateTime(2026, 10, 21, hour, minute));

    test('時間帯ごとの初期値', () {
      expect(at(5), MealType.breakfast);
      expect(at(10, 59), MealType.breakfast);
      expect(at(11), MealType.lunch);
      expect(at(14, 59), MealType.lunch);
      expect(at(15), MealType.snack);
      expect(at(16, 59), MealType.snack);
      expect(at(17), MealType.dinner);
      expect(at(21, 59), MealType.dinner);
      expect(at(22), MealType.snack);
      expect(at(4, 59), MealType.snack);
    });
  });

  test('MealType.fromName: 不明な値は間食に倒す', () {
    expect(MealType.fromName('dinner'), MealType.dinner);
    expect(MealType.fromName('brunch'), MealType.snack);
    expect(MealType.fromName(null), MealType.snack);
  });

  group('MealEntry', () {
    test('toMap はFirestoreの形（日付キー・平らなPFC・Timestamp）', () {
      final map = entry(
        'e1',
        createdAt: DateTime(2026, 10, 21, 12, 30),
      ).toMap();

      expect(map, {
        'date': '2026-10-21',
        'mealType': 'lunch',
        'name': '牛丼',
        'amount': '並盛',
        'calories': 600.0,
        'protein': 20.0,
        'fat': 20.0,
        'carbs': 85.0,
        'source': 'ai',
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 21, 12, 30)),
      });
    });

    test('fromMap で往復できる', () {
      final original = entry('e1', createdAt: DateTime(2026, 10, 21, 12, 30));
      final restored = MealEntry.fromMap('e1', original.toMap());

      expect(restored.id, 'e1');
      expect(restored.dateKey, original.dateKey);
      expect(restored.mealType, original.mealType);
      expect(restored.food, original.food);
      expect(restored.source, original.source);
      expect(restored.createdAt, original.createdAt);
    });

    test('壊れたドキュメントでも例外にせず読める範囲で読む', () {
      final restored = MealEntry.fromMap('x', {
        'name': ' おにぎり ',
        'calories': 'abc',
      });

      expect(restored.food.name, 'おにぎり');
      expect(restored.nutrition, Nutrition.zero);
      expect(restored.source, EntrySource.manual);
    });
  });
}
