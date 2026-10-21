import 'package:intl/intl.dart';

// 日付は 'YYYY-MM-DD' の文字列キーで扱う（端末のローカル日付）。
// Timestampで持つと、深夜の記録が端末とサーバーのタイムゾーン差で
// 前後の日にずれる。「何日の食事か」は利用者の感覚の日付が正なので文字列にする。

/// 時刻を落とした日付（ローカル）。
DateTime dateOnly(DateTime time) => DateTime(time.year, time.month, time.day);

String dateKeyOf(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

final _dateKeyPattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// 'YYYY-MM-DD' を日付に戻す。形式が違えばnull。
DateTime? tryParseDateKey(String key) {
  final m = _dateKeyPattern.firstMatch(key);
  if (m == null) return null;
  final date = DateTime(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
  );
  // 2026-02-30 のような存在しない日付は DateTime が繰り上げてしまうので弾く
  return dateKeyOf(date) == key ? date : null;
}

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// [date] に [days] 日足した日付。
///
/// Duration(days: n) を足すと、夏時間のある地域では日付をまたぐ瞬間に
/// 1時間ずれて同じ日・前日になることがあるため、年月日で計算する。
DateTime addDays(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);

/// [end] を最終日とする [days] 日分の日付キー（古い順）。
List<String> lastNDateKeys(DateTime end, int days) => [
  for (var i = days - 1; i >= 0; i--) dateKeyOf(addDays(end, -i)),
];

/// 「10月21日(火)」
String formatDateJa(DateTime date) => DateFormat('M月d日(E)', 'ja').format(date);

/// 「10/21」
String formatDateShort(DateTime date) => DateFormat('M/d', 'ja').format(date);

/// 「2026年10月21日(火)」
String formatDateLong(DateTime date) =>
    DateFormat('y年M月d日(E)', 'ja').format(date);

/// 今日・昨日・明日はその呼び名、今年なら「10月21日(火)」、
/// それ以外は「2025年10月21日(火)」。
String relativeDayLabel(DateTime date, DateTime today) {
  if (isSameDay(date, today)) return '今日';
  if (isSameDay(date, addDays(today, -1))) return '昨日';
  if (isSameDay(date, addDays(today, 1))) return '明日';
  return date.year == today.year ? formatDateJa(date) : formatDateLong(date);
}
