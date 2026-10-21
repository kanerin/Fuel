import 'package:flutter/material.dart';

import '../logic/date_keys.dart';
import '../logic/formatters.dart';
import '../models/nutrition.dart';
import '../models/user_profile.dart';
import '../services/app_services.dart';
import '../widgets/async_views.dart';
import '../widgets/targets_summary.dart';

/// プロフィールと目標の入力。
///
/// [initial] が null なら初回の入力（はじめに）、あれば設定画面からの編集。
/// 入力中はその場で消費カロリー・目標を計算し直して下に表示する。
class ProfileFormScreen extends StatefulWidget {
  const ProfileFormScreen({super.key, this.initial});

  final UserProfile? initial;

  @override
  State<ProfileFormScreen> createState() => _ProfileFormScreenState();
}

class _ProfileFormScreenState extends State<ProfileFormScreen> {
  final _formKey = GlobalKey<FormState>();
  Sex? _sex;
  ActivityLevel? _activity;
  late GoalType _goal;
  late double _rate;
  late PfcPreset _preset;
  late bool _useCustomKcal;

  /// 「はじめる」を押した後だけ、未選択の項目のエラーを出す
  bool _submitted = false;

  late final TextEditingController _age;
  late final TextEditingController _height;
  late final TextEditingController _weight;
  late final TextEditingController _targetWeight;
  late final TextEditingController _customKcal;
  late final TextEditingController _ratioP;
  late final TextEditingController _ratioF;
  late final TextEditingController _ratioC;

  bool get _isOnboarding => widget.initial == null;

  List<TextEditingController> get _controllers => [
    _age,
    _height,
    _weight,
    _targetWeight,
    _customKcal,
    _ratioP,
    _ratioF,
    _ratioC,
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    _sex = p?.sex;
    _activity = p?.activityLevel;
    _goal = p?.goal ?? GoalType.lose;
    _rate = p?.weeklyRateKg ?? _goal.defaultRate;
    _preset = p?.pfcPreset ?? PfcPreset.balanced;
    _useCustomKcal = p?.customTargetKcal != null;
    _age = TextEditingController(text: p == null ? '' : '${p.age}');
    _height = TextEditingController(
      text: p == null ? '' : numberToInput(p.heightCm),
    );
    _weight = TextEditingController(
      text: p == null ? '' : numberToInput(p.weightKg),
    );
    final target = p?.targetWeightKg;
    _targetWeight = TextEditingController(
      text: target == null ? '' : numberToInput(target),
    );
    _customKcal = TextEditingController(
      text: p?.customTargetKcal?.toString() ?? '',
    );
    final ratio = p?.pfcRatio ?? PfcPreset.balanced.ratio!;
    _ratioP = TextEditingController(text: '${ratio.protein}');
    _ratioF = TextEditingController(text: '${ratio.fat}');
    _ratioC = TextEditingController(text: '${ratio.carbs}');
    // 入力のたびに下の計算結果を更新する
    for (final c in _controllers) {
      c.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _refresh() => setState(() {});

  PfcRatio? get _ratio {
    if (_preset != PfcPreset.custom) return _preset.ratio;
    final p = _parseInt(_ratioP.text);
    final f = _parseInt(_ratioF.text);
    final c = _parseInt(_ratioC.text);
    if (p == null || f == null || c == null) return null;
    return PfcRatio(p, f, c);
  }

  /// 入力中の値から作ったプロフィール。未入力・範囲外があればnull。
  UserProfile? _draft() {
    final sex = _sex;
    final activity = _activity;
    final ratio = _ratio;
    final age = _parseInt(_age.text);
    final height = parseNumberInput(_height.text);
    final weight = parseNumberInput(_weight.text);
    final targetText = _targetWeight.text.trim();
    final target = targetText.isEmpty ? null : parseNumberInput(targetText);
    final custom = _useCustomKcal ? _parseInt(_customKcal.text) : null;
    if (sex == null ||
        activity == null ||
        ratio == null ||
        age == null ||
        height == null ||
        weight == null ||
        (targetText.isNotEmpty && target == null) ||
        (_useCustomKcal && custom == null)) {
      return null;
    }
    final profile = UserProfile(
      sex: sex,
      age: age,
      heightCm: roundTo1(height),
      weightKg: roundTo1(weight),
      activityLevel: activity,
      goal: _goal,
      weeklyRateKg: _goal == GoalType.maintain ? 0 : _rate,
      pfcPreset: _preset,
      pfcRatio: ratio,
      targetWeightKg: target == null ? null : roundTo1(target),
      customTargetKcal: custom,
    );
    return profile.validate() == null ? profile : null;
  }

  void _selectPreset(PfcPreset preset) {
    setState(() {
      _preset = preset;
      final ratio = preset.ratio;
      if (ratio != null) {
        // カスタムに切り替えたとき、直前のプリセットの比率から調整できるようにしておく
        _ratioP.text = '${ratio.protein}';
        _ratioF.text = '${ratio.fat}';
        _ratioC.text = '${ratio.carbs}';
      }
    });
  }

  void _save() {
    setState(() => _submitted = true);
    final formValid = _formKey.currentState!.validate();
    final profile = _draft();
    final messenger = ScaffoldMessenger.of(context);
    // 足りない・おかしい項目はボタンのすぐ上と各欄の下に出す（build参照）。
    // スナックバーにすると、すぐ下にある保存ボタンに被さって押せなくなる
    if (!formValid || profile == null) return;

    final services = AppScope.of(context);
    final initial = widget.initial;
    // 体重を変えたら、その日の体重の記録としても残す（体重グラフと食い違わないように）
    final weightChanged =
        initial == null || initial.weightKg != profile.weightKg;
    saveInBackground(
      messenger,
      services.profiles.saveProfile(
        profile,
        weightLogDateKey: weightChanged ? dateKeyOf(services.today()) : null,
      ),
      failureMessage: 'プロフィールを保存できませんでした',
    );
    // 初回は保存した時点でホームへ切り替わる（ProfileGateがプロフィールの変化を見ている）
    if (!_isOnboarding) {
      Navigator.of(context).pop();
      messenger.showSnackBar(const SnackBar(content: Text('保存しました')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draft = _draft();
    final ratio = _ratio;
    return Scaffold(
      appBar: AppBar(title: Text(_isOnboarding ? 'はじめに' : 'プロフィールと目標')),
      body: Form(
        key: _formKey,
        // ListViewだと画面外の入力欄が作られず、Formの検証から漏れる（エラーが出ない）ため、
        // 入力欄はすべて常に作っておく
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isOnboarding)
                Text(
                  'あなたに合った1日の消費カロリーと、目標のカロリー・PFCを計算します。'
                  'あとから設定画面でいつでも変更できます。',
                  style: theme.textTheme.bodyMedium,
                ),
              const _SectionTitle('からだのこと'),
              SegmentedButton<Sex>(
                segments: [
                  for (final s in Sex.values)
                    ButtonSegment(value: s, label: Text(s.label)),
                ],
                selected: {?_sex},
                emptySelectionAllowed: true,
                onSelectionChanged: (s) =>
                    setState(() => _sex = s.isEmpty ? null : s.first),
              ),
              if (_submitted && _sex == null) const _ErrorText('性別を選んでください'),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _NumberInput(
                      controller: _age,
                      label: '年齢',
                      suffix: '歳',
                      min: kMinAge.toDouble(),
                      max: kMaxAge.toDouble(),
                      integer: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _NumberInput(
                      controller: _height,
                      label: '身長',
                      suffix: 'cm',
                      min: kMinHeightCm,
                      max: kMaxHeightCm,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _NumberInput(
                      controller: _weight,
                      label: '体重',
                      suffix: 'kg',
                      min: kMinWeightKg,
                      max: kMaxWeightKg,
                    ),
                  ),
                ],
              ),
              const _SectionTitle('運動の頻度'),
              RadioGroup<ActivityLevel>(
                groupValue: _activity,
                onChanged: (v) => setState(() => _activity = v),
                child: Column(
                  children: [
                    for (final level in ActivityLevel.values)
                      RadioListTile<ActivityLevel>(
                        value: level,
                        contentPadding: EdgeInsets.zero,
                        title: Text(level.label),
                        subtitle: Text(level.description),
                      ),
                  ],
                ),
              ),
              if (_submitted && _activity == null)
                const _ErrorText('運動の頻度を選んでください'),
              const _SectionTitle('目標'),
              SegmentedButton<GoalType>(
                segments: [
                  for (final g in GoalType.values)
                    ButtonSegment(value: g, label: Text(g.label)),
                ],
                selected: {_goal},
                onSelectionChanged: (s) => setState(() {
                  _goal = s.first;
                  _rate = _goal.defaultRate;
                }),
              ),
              if (_goal != GoalType.maintain) ...[
                const SizedBox(height: 12),
                Text('ペース（1週間あたり）', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final r in _goal.rateOptions)
                      ChoiceChip(
                        label: Text('${paceLabel(r)} ${formatPace(r)}kg'),
                        selected: _rate == r,
                        onSelected: (_) => setState(() => _rate = r),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              _NumberInput(
                controller: _targetWeight,
                label: '目標体重（任意）',
                suffix: 'kg',
                min: kMinWeightKg,
                max: kMaxWeightKg,
                required: false,
              ),
              const _SectionTitle('PFCバランス'),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final preset in PfcPreset.values)
                    ChoiceChip(
                      label: Text(preset.label),
                      selected: _preset == preset,
                      onSelected: (_) => _selectPreset(preset),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                ratio == null
                    ? _preset.description
                    : '${_preset.description}（P${ratio.protein}% · F${ratio.fat}% · C${ratio.carbs}%）',
                style: theme.textTheme.bodySmall,
              ),
              if (_preset == PfcPreset.custom) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (label, controller) in [
                      ('たんぱく質', _ratioP),
                      ('脂質', _ratioF),
                      ('炭水化物', _ratioC),
                    ]) ...[
                      Expanded(
                        child: _NumberInput(
                          controller: controller,
                          label: label,
                          suffix: '%',
                          min: kMinPfcRatio.toDouble(),
                          max: kMaxPfcRatio.toDouble(),
                          integer: true,
                        ),
                      ),
                      if (label != '炭水化物') const SizedBox(width: 8),
                    ],
                  ],
                ),
                _RatioTotal(ratio: ratio),
              ],
              const _SectionTitle('目標カロリー'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('目標カロリーを自分で決める'),
                subtitle: const Text('オフなら、消費カロリーと目標のペースから計算します'),
                value: _useCustomKcal,
                onChanged: (v) => setState(() => _useCustomKcal = v),
              ),
              if (_useCustomKcal)
                _NumberInput(
                  controller: _customKcal,
                  label: '1日の目標',
                  suffix: 'kcal',
                  min: kMinCustomTargetKcal.toDouble(),
                  max: kMaxCustomTargetKcal.toDouble(),
                  integer: true,
                ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('1日の目安', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      if (draft == null)
                        Text(
                          'すべて入力すると、ここに計算結果が表示されます',
                          style: theme.textTheme.bodyMedium,
                        )
                      else
                        TargetsSummary(profile: draft),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (_submitted && draft == null)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: _ErrorText('入力内容を確認してください（赤字の項目）'),
                ),
              FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: Text(_isOnboarding ? 'はじめる' : '保存する'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

int? _parseInt(String text) {
  final value = parseNumberInput(text);
  if (value == null || value != value.roundToDouble()) return null;
  return value.toInt();
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
    ),
  );
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      ),
    );
  }
}

class _RatioTotal extends StatelessWidget {
  const _RatioTotal({required this.ratio});

  final PfcRatio? ratio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = ratio?.total;
    final ok = total == 100;
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4),
      child: Text(
        total == null
            ? '合計 -%（100%にしてください）'
            : ok
            ? '合計 100%'
            : '合計 $total%（100%にしてください）',
        style: theme.textTheme.bodySmall?.copyWith(
          color: ok ? theme.colorScheme.primary : theme.colorScheme.error,
        ),
      ),
    );
  }
}

class _NumberInput extends StatelessWidget {
  const _NumberInput({
    required this.controller,
    required this.label,
    required this.suffix,
    required this.min,
    required this.max,
    this.integer = false,
    this.required = true,
  });

  final TextEditingController controller;
  final String label;
  final String suffix;
  final double min;
  final double max;
  final bool integer;
  final bool required;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: TextInputType.numberWithOptions(decimal: !integer),
    textInputAction: TextInputAction.next,
    decoration: InputDecoration(labelText: label, suffixText: suffix),
    validator: (v) {
      final text = (v ?? '').trim();
      if (text.isEmpty) return required ? '入力してください' : null;
      final value = parseNumberInput(text);
      if (value == null || (integer && value != value.roundToDouble())) {
        return integer ? '整数で入力' : '数値で入力';
      }
      if (value < min || value > max) {
        return '${formatGrams(min)}〜${formatGrams(max)}';
      }
      return null;
    },
  );
}
