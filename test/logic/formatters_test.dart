import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/logic/formatters.dart';

void main() {
  test('formatKcal: 整数に丸めて3桁区切り', () {
    expect(formatKcal(1234.6), '1,235');
    expect(formatKcal(0), '0');
  });

  test('formatGrams: 小数1桁まで、整数なら小数点を付けない', () {
    expect(formatGrams(12), '12');
    expect(formatGrams(12.34), '12.3');
    expect(formatGrams(12.96), '13');
  });

  test('formatWeight: 常に小数1桁', () {
    expect(formatWeight(68), '68.0');
    expect(formatWeight(68.25), '68.3');
  });

  test('formatSignedWeight: 増減に符号を付ける', () {
    expect(formatSignedWeight(0.4), '+0.4');
    expect(formatSignedWeight(-1.25), '-1.3');
    expect(formatSignedWeight(0.01), '±0.0');
  });

  group('parseNumberInput', () {
    test('半角・全角・カンマ区切りを読む', () {
      expect(parseNumberInput('123'), 123);
      expect(parseNumberInput('１２３．５'), 123.5);
      expect(parseNumberInput(' 1,234 '), 1234);
    });

    test('読めない入力はnull', () {
      expect(parseNumberInput(''), isNull);
      expect(parseNumberInput('   '), isNull);
      expect(parseNumberInput('abc'), isNull);
      expect(parseNumberInput('1.2.3'), isNull);
    });
  });
}
