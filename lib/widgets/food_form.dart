import 'package:flutter/material.dart';

import '../logic/formatters.dart';
import '../models/food_item.dart';
import '../models/nutrition.dart';

/// 食べ物1品の入力欄（名前・量・kcal・PFC）の状態。
///
/// 手入力での追加・記録の編集・AIの推定値の修正で同じ入力欄を使う。
class FoodFormController {
  FoodFormController([FoodItem? initial])
    : name = TextEditingController(text: initial?.name ?? ''),
      amount = TextEditingController(text: initial?.amount ?? ''),
      calories = TextEditingController(
        text: _initialNumber(initial?.nutrition.calories),
      ),
      protein = TextEditingController(
        text: _initialNumber(initial?.nutrition.protein),
      ),
      fat = TextEditingController(text: _initialNumber(initial?.nutrition.fat)),
      carbs = TextEditingController(
        text: _initialNumber(initial?.nutrition.carbs),
      );

  final TextEditingController name;
  final TextEditingController amount;
  final TextEditingController calories;
  final TextEditingController protein;
  final TextEditingController fat;
  final TextEditingController carbs;

  static String _initialNumber(double? value) =>
      value == null ? '' : numberToInput(value);

  /// P・F・Cは空欄なら0として扱う（栄養成分表示にkcalしか書いていない食品もある）。
  static double? _readMacro(TextEditingController c) =>
      c.text.trim().isEmpty ? 0 : parseNumberInput(c.text);

  /// 入力欄の値から作った1品。数値として読めない欄があればnull。
  FoodItem? tryBuild() {
    final kcal = parseNumberInput(calories.text);
    final p = _readMacro(protein);
    final f = _readMacro(fat);
    final c = _readMacro(carbs);
    if (kcal == null || p == null || f == null || c == null) return null;
    return FoodItem(
      name: name.text.trim(),
      amount: amount.text.trim(),
      nutrition: Nutrition(calories: kcal, protein: p, fat: f, carbs: c),
    );
  }

  /// 量を [factor] 倍する（「大盛りだった」「半分残した」）。読めない欄はそのまま。
  void scale(double factor) {
    for (final c in [calories, protein, fat, carbs]) {
      final value = parseNumberInput(c.text);
      if (value == null) continue;
      final scaled = c == calories
          ? (value * factor).roundToDouble()
          : roundTo1(value * factor);
      c.text = numberToInput(scaled);
    }
  }

  /// P×4＋F×9＋C×4 をkcalの欄に入れる。
  void fillCaloriesFromMacros() {
    final p = _readMacro(protein) ?? 0;
    final f = _readMacro(fat) ?? 0;
    final c = _readMacro(carbs) ?? 0;
    final kcal = Nutrition(protein: p, fat: f, carbs: c).caloriesFromMacros;
    calories.text = numberToInput(kcal.roundToDouble());
  }

  void dispose() {
    for (final c in [name, amount, calories, protein, fat, carbs]) {
      c.dispose();
    }
  }
}

/// [FoodFormController] の入力欄。[Form] の中に置くこと（検証は Form の validate で行う）。
class FoodFormFields extends StatelessWidget {
  const FoodFormFields({super.key, required this.controller});

  final FoodFormController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: controller.name,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: '名前',
            hintText: '例: 豚の生姜焼き',
          ),
          validator: (v) {
            final text = (v ?? '').trim();
            if (text.isEmpty) return '名前を入力してください';
            if (text.length > kMaxFoodNameLength) {
              return '$kMaxFoodNameLength文字以内にしてください';
            }
            return null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: controller.amount,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: '量（任意）',
            hintText: '例: 1人前、200g',
          ),
          validator: (v) => (v ?? '').trim().length > kMaxFoodAmountLength
              ? '$kMaxFoodAmountLength文字以内にしてください'
              : null,
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _NumberField(
                controller: controller.calories,
                label: 'エネルギー',
                suffix: 'kcal',
                max: kMaxCaloriesPerItem,
                required: true,
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: TextButton.icon(
                onPressed: controller.fillCaloriesFromMacros,
                icon: const Icon(Icons.calculate_outlined, size: 18),
                label: const Text('PFCから計算'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _NumberField(
                controller: controller.protein,
                label: 'たんぱく質',
                suffix: 'g',
                max: kMaxMacroGramsPerItem,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _NumberField(
                controller: controller.fat,
                label: '脂質',
                suffix: 'g',
                max: kMaxMacroGramsPerItem,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _NumberField(
                controller: controller.carbs,
                label: '炭水化物',
                suffix: 'g',
                max: kMaxMacroGramsPerItem,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('量を調整', style: theme.textTheme.bodyMedium),
            for (final factor in const [0.5, 1.5, 2.0])
              ActionChip(
                label: Text('×${formatGrams(factor)}'),
                tooltip: '値を${formatGrams(factor)}倍にする',
                onPressed: () => controller.scale(factor),
              ),
          ],
        ),
      ],
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.suffix,
    required this.max,
    this.required = false,
  });

  final TextEditingController controller;
  final String label;
  final String suffix;
  final double max;
  final bool required;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    textInputAction: TextInputAction.next,
    decoration: InputDecoration(labelText: label, suffixText: suffix),
    validator: (v) {
      final text = (v ?? '').trim();
      if (text.isEmpty) return required ? '入力してください' : null;
      final value = parseNumberInput(text);
      if (value == null) return '数値で入力';
      if (value < 0 || value > max) return '0〜${max.toInt()}';
      return null;
    },
  );
}
