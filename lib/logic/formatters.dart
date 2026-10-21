import 'package:intl/intl.dart';

final _kcalFormat = NumberFormat('#,##0', 'ja');

/// 「1,234」（kcalは整数で表示する）
String formatKcal(num kcal) => _kcalFormat.format(kcal.round());

/// 「12.5」「20」（gは小数1桁まで。整数になるときは小数点を付けない）
String formatGrams(num grams) {
  final rounded = (grams * 10).round() / 10;
  if (rounded == rounded.roundToDouble()) return rounded.toInt().toString();
  return rounded.toStringAsFixed(1);
}

/// 「68.2」（体重は常に小数1桁）
String formatWeight(num kg) => ((kg * 10).round() / 10).toStringAsFixed(1);

/// 「+0.4」「-1.2」「±0.0」（前回比など）
String formatSignedWeight(num kg) {
  final rounded = (kg * 10).round() / 10;
  if (rounded == 0) return '±0.0';
  return '${rounded > 0 ? '+' : ''}${rounded.toStringAsFixed(1)}';
}

/// 入力欄の文字列を数値として読む。全角数字・カンマ・前後の空白も受け付ける。
/// 読めなければnull。
double? parseNumberInput(String text) {
  final normalized = text
      .trim()
      .replaceAllMapped(
        RegExp('[０-９]'),
        (m) => String.fromCharCode(m.group(0)!.codeUnitAt(0) - 0xFEE0),
      )
      .replaceAll('．', '.')
      .replaceAll(',', '')
      .replaceAll('，', '');
  if (normalized.isEmpty) return null;
  final value = double.tryParse(normalized);
  if (value == null || !value.isFinite) return null;
  return value;
}

/// 入力欄に初期表示する文字列（不要な「.0」を付けない）。
String numberToInput(num value) => formatGrams(value);
