import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/models/nutrition.dart';
import 'package:fuel/widgets/food_form.dart';

import '../helpers/fixtures.dart';

void main() {
  group('FoodFormController', () {
    test('初期値を入力欄の文字列にする（不要な「.0」を付けない）', () {
      final c = FoodFormController(
        food('牛丼', amount: '並盛', kcal: 650, p: 22.5, f: 22, c: 90),
      );

      expect(c.name.text, '牛丼');
      expect(c.calories.text, '650');
      expect(c.protein.text, '22.5');
      c.dispose();
    });

    test('tryBuild: 入力欄から1品を作る。P・F・Cの空欄は0', () {
      final c = FoodFormController()
        ..name.text = ' おにぎり '
        ..calories.text = '180';

      expect(c.tryBuild(), food('おにぎり', kcal: 180));
      c.dispose();
    });

    test('tryBuild: 数値として読めない欄があればnull', () {
      final c = FoodFormController()
        ..name.text = 'おにぎり'
        ..calories.text = '';
      expect(c.tryBuild(), isNull);

      c.calories.text = '180';
      c.fat.text = '少し';
      expect(c.tryBuild(), isNull);
      c.dispose();
    });

    test('scale: kcalは整数、gは小数1桁で倍にする', () {
      final c = FoodFormController(
        food('牛丼', kcal: 651, p: 22.3, f: 21.9, c: 90),
      )..scale(1.5);

      expect(c.calories.text, '977'); // 976.5
      expect(c.protein.text, '33.5'); // 33.45
      expect(c.fat.text, '32.9'); // 32.85
      expect(c.carbs.text, '135');
      c.dispose();
    });

    test('fillCaloriesFromMacros: P×4＋F×9＋C×4 をkcalに入れる', () {
      final c = FoodFormController()
        ..protein.text = '20'
        ..fat.text = '10'
        ..carbs.text = '50';

      c.fillCaloriesFromMacros();

      expect(c.calories.text, '370');
      expect(
        c.tryBuild()!.nutrition,
        const Nutrition(calories: 370, protein: 20, fat: 10, carbs: 50),
      );
      c.dispose();
    });
  });
}
