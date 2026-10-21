import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/models/food_item.dart';

import '../helpers/fixtures.dart';

void main() {
  group('validateFoodItem', () {
    test('有効な値ならnull', () {
      expect(
        validateFoodItem(food('牛丼', kcal: 600, p: 20, f: 20, c: 85)),
        isNull,
      );
    });

    test('名前は必須・60文字以内', () {
      expect(validateFoodItem(food('  ')), contains('名前'));
      expect(validateFoodItem(food('あ' * 61)), contains('名前'));
    });

    test('量は40文字以内', () {
      expect(validateFoodItem(food('牛丼', amount: 'あ' * 41)), contains('量'));
    });

    test('エネルギーは0〜5000kcal、PFCは0〜500g', () {
      expect(validateFoodItem(food('牛丼', kcal: 5001)), contains('エネルギー'));
      expect(validateFoodItem(food('牛丼', kcal: -1)), contains('エネルギー'));
      expect(validateFoodItem(food('牛丼', p: 501)), contains('P・F・C'));
      expect(validateFoodItem(food('牛丼', c: -0.1)), contains('P・F・C'));
    });
  });

  test('FoodItem.identity は名前と量の組（前後の空白は無視）', () {
    expect(
      food(' 牛丼 ', amount: '並盛').identity,
      food('牛丼', amount: '並盛 ').identity,
    );
    expect(
      food('牛丼', amount: '並盛').identity,
      isNot(food('牛丼', amount: '大盛').identity),
    );
  });
}
