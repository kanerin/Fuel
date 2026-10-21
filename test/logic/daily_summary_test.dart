import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/logic/daily_summary.dart';
import 'package:fuel/models/meal_entry.dart';
import 'package:fuel/models/nutrition.dart';

import '../helpers/fixtures.dart';

void main() {
  group('DailySummary', () {
    test('食事区分ごとに、記録した順に分ける', () {
      final summary = DailySummary.of([
        entry(
          'b',
          mealType: MealType.lunch,
          createdAt: DateTime(2026, 10, 21, 13),
        ),
        entry(
          'a',
          mealType: MealType.lunch,
          createdAt: DateTime(2026, 10, 21, 12),
        ),
        entry('c', mealType: MealType.breakfast),
      ]);

      expect(summary.entriesFor(MealType.lunch).map((e) => e.id), ['a', 'b']);
      expect(summary.entriesFor(MealType.breakfast).map((e) => e.id), ['c']);
      expect(summary.entriesFor(MealType.dinner), isEmpty);
      expect(summary.isEmpty, isFalse);
    });

    test('1日の合計と区分ごとの小計を出す', () {
      final summary = DailySummary.of([
        entry('a', mealType: MealType.breakfast, kcal: 300, p: 10, f: 5, c: 50),
        entry('b', mealType: MealType.lunch, kcal: 600, p: 20, f: 20, c: 85),
        entry('c', mealType: MealType.lunch, kcal: 40, p: 3, f: 1, c: 5),
      ]);

      expect(
        summary.total,
        const Nutrition(calories: 940, protein: 33, fat: 26, carbs: 140),
      );
      expect(
        summary.totalFor(MealType.lunch),
        const Nutrition(calories: 640, protein: 23, fat: 21, carbs: 90),
      );
      expect(summary.totalFor(MealType.snack), Nutrition.zero);
    });

    test('記録が無ければ空', () {
      final summary = DailySummary.of(const []);

      expect(summary.isEmpty, isTrue);
      expect(summary.total, Nutrition.zero);
    });
  });

  group('progressOf', () {
    test('目標に対する割合（超過は1を超える）', () {
      expect(progressOf(500, 2000), 0.25);
      expect(progressOf(2500, 2000), 1.25);
    });

    test('目標が0なら0（0除算しない）', () {
      expect(progressOf(500, 0), 0);
    });
  });

  group('PfcShare', () {
    test('三大栄養素のエネルギー比で出す（kcalの値は使わない）', () {
      // P 25g=100kcal, F 0, C 25g=100kcal。kcalにアルコール分が入っていても無関係
      final share = PfcShare.of(
        const Nutrition(calories: 400, protein: 25, fat: 0, carbs: 25),
      )!;

      expect(share.protein, 50);
      expect(share.fat, 0);
      expect(share.carbs, 50);
    });

    test('脂質は1gあたり9kcalで数える', () {
      final share = PfcShare.of(
        const Nutrition(protein: 0, fat: 10, carbs: 22.5),
      )!;

      expect(share.fat, 50);
      expect(share.carbs, 50);
    });

    test('三大栄養素がすべて0なら比率を出せない', () {
      expect(PfcShare.of(const Nutrition(calories: 100)), isNull);
    });
  });

  group('summarizePeriod', () {
    const keys = ['2026-10-19', '2026-10-20', '2026-10-21'];

    test('期間内のすべての日を古い順に並べ、記録の無い日も0として含める', () {
      final period = summarizePeriod(keys, [
        entry('a', dateKey: '2026-10-21', kcal: 600),
        entry('b', dateKey: '2026-10-19', kcal: 400),
        entry('c', dateKey: '2026-10-19', kcal: 100),
      ]);

      expect(period.days.map((d) => d.dateKey), keys);
      expect(period.days.map((d) => d.total.calories), [500, 0, 600]);
      expect(period.days.map((d) => d.entryCount), [2, 0, 1]);
      expect(period.recordedDays, 2);
    });

    test('平均は記録のある日だけで割る（付け忘れた日で平均を下げない）', () {
      final period = summarizePeriod(keys, [
        entry('a', dateKey: '2026-10-21', kcal: 1800, p: 80, f: 50, c: 250),
        entry('b', dateKey: '2026-10-19', kcal: 2200, p: 100, f: 70, c: 290),
      ]);

      expect(
        period.average,
        const Nutrition(calories: 2000, protein: 90, fat: 60, carbs: 270),
      );
    });

    test('記録が1件も無ければ平均は無い', () {
      expect(summarizePeriod(keys, const []).average, isNull);
    });

    test('期間外の記録は無視する', () {
      final period = summarizePeriod(keys, [
        entry('a', dateKey: '2026-10-18', kcal: 999),
      ]);

      expect(period.recordedDays, 0);
    });

    test('目標以内に収まった日を数える', () {
      final period = summarizePeriod(keys, [
        entry('a', dateKey: '2026-10-19', kcal: 1900),
        entry('b', dateKey: '2026-10-20', kcal: 2100),
        entry('c', dateKey: '2026-10-21', kcal: 2000),
      ]);

      expect(period.daysWithinTarget(2000), 2);
    });
  });
}
