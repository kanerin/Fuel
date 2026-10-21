import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/logic/date_keys.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ja');
  });

  group('dateKeyOf / tryParseDateKey', () {
    test('YYYY-MM-DD（ゼロ埋め）', () {
      expect(dateKeyOf(DateTime(2026, 1, 5, 23, 59)), '2026-01-05');
    });

    test('往復できる', () {
      expect(tryParseDateKey('2026-10-21'), DateTime(2026, 10, 21));
    });

    test('形式が違う・存在しない日付はnull', () {
      expect(tryParseDateKey('2026/10/21'), isNull);
      expect(tryParseDateKey('2026-2-1'), isNull);
      expect(tryParseDateKey('2026-02-30'), isNull);
      expect(tryParseDateKey(''), isNull);
    });
  });

  group('addDays', () {
    test('月・年をまたいで日付を進める・戻す', () {
      expect(addDays(DateTime(2026, 3, 1), -1), DateTime(2026, 2, 28));
      expect(addDays(DateTime(2026, 12, 31), 1), DateTime(2027, 1, 1));
    });

    test('時刻は落とす', () {
      expect(
        addDays(DateTime(2026, 10, 21, 18, 30), 0),
        DateTime(2026, 10, 21),
      );
    });
  });

  test('lastNDateKeys: 最終日を含むN日分を古い順に', () {
    expect(lastNDateKeys(DateTime(2026, 11, 1), 3), [
      '2026-10-30',
      '2026-10-31',
      '2026-11-01',
    ]);
  });

  group('relativeDayLabel', () {
    final today = DateTime(2026, 10, 21, 9);

    test('今日・昨日・明日', () {
      expect(relativeDayLabel(DateTime(2026, 10, 21, 23), today), '今日');
      expect(relativeDayLabel(DateTime(2026, 10, 20), today), '昨日');
      expect(relativeDayLabel(DateTime(2026, 10, 22), today), '明日');
    });

    test('今年なら月日と曜日、去年以前は年も付ける', () {
      expect(relativeDayLabel(DateTime(2026, 10, 1), today), '10月1日(木)');
      expect(relativeDayLabel(DateTime(2025, 12, 31), today), '2025年12月31日(水)');
    });
  });

  test('isSameDay は時刻を無視する', () {
    expect(
      isSameDay(DateTime(2026, 10, 21, 0), DateTime(2026, 10, 21, 23, 59)),
      isTrue,
    );
    expect(isSameDay(DateTime(2026, 10, 21), DateTime(2026, 10, 22)), isFalse);
  });
}
