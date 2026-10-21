// プロフィールと目標。users/{uid}.profile に保存する。
//
// 値の範囲は docs/requirements.md 6章、セキュリティルール（firestore.rules の
// validProfile）と揃えている。ここを変えるときは3か所とも直すこと。

const kMinAge = 15;
const kMaxAge = 100;
const kMinHeightCm = 120.0;
const kMaxHeightCm = 220.0;
const kMinWeightKg = 30.0;
const kMaxWeightKg = 250.0;
const kMinCustomTargetKcal = 1000;
const kMaxCustomTargetKcal = 5000;
const kMinPfcRatio = 5;
const kMaxPfcRatio = 70;

enum Sex {
  male('男性'),
  female('女性');

  final String label;
  const Sex(this.label);
}

/// 運動頻度（活動レベル）と、基礎代謝量にかける活動係数。
enum ActivityLevel {
  sedentary('ほとんど運動しない', 'デスクワーク中心で、運動の習慣はない', 1.2),
  light('軽い運動', '週1〜3回、軽い運動をする', 1.375),
  moderate('適度な運動', '週3〜5回、運動をする', 1.55),
  active('活発な運動', '週6〜7回、しっかり運動をする', 1.725),
  veryActive('非常に活発', '毎日の激しい運動や肉体労働', 1.9);

  final String label;
  final String description;
  final double factor;
  const ActivityLevel(this.label, this.description, this.factor);
}

enum GoalType {
  lose('減量'),
  maintain('維持'),
  gain('増量');

  final String label;
  const GoalType(this.label);

  /// 選べるペース（kg/週）。維持は増減なし。
  List<double> get rateOptions => switch (this) {
    GoalType.lose => const [0.25, 0.5, 0.75],
    GoalType.maintain => const [0],
    GoalType.gain => const [0.25, 0.5],
  };

  /// 目標を切り替えたときのペースの初期値。
  double get defaultRate => switch (this) {
    GoalType.lose => 0.5,
    GoalType.maintain => 0,
    GoalType.gain => 0.25,
  };
}

/// ペースの呼び名（「ふつう（週0.5kg）」の「ふつう」）。
String paceLabel(double weeklyRateKg) {
  if (weeklyRateKg <= 0) return '';
  if (weeklyRateKg <= 0.25) return 'ゆっくり';
  if (weeklyRateKg <= 0.5) return 'ふつう';
  return 'しっかり';
}

/// PFCの比率（%）。合計100。
class PfcRatio {
  final int protein;
  final int fat;
  final int carbs;

  const PfcRatio(this.protein, this.fat, this.carbs);

  int get total => protein + fat + carbs;

  bool get isValid =>
      total == 100 &&
      [
        protein,
        fat,
        carbs,
      ].every((r) => r >= kMinPfcRatio && r <= kMaxPfcRatio);

  @override
  bool operator ==(Object other) =>
      other is PfcRatio &&
      other.protein == protein &&
      other.fat == fat &&
      other.carbs == carbs;

  @override
  int get hashCode => Object.hash(protein, fat, carbs);

  @override
  String toString() => 'P$protein:F$fat:C$carbs';
}

enum PfcPreset {
  balanced('バランス', '日本人の食事摂取基準の範囲。迷ったらこれ', PfcRatio(20, 25, 55)),
  highProtein('高たんぱく', '筋肉を落とさずに減量したい', PfcRatio(30, 25, 45)),
  lowFat('ローファット', '脂質を控えめにしたい', PfcRatio(25, 15, 60)),
  lowCarb('ローカーボ', '糖質を控えめにしたい', PfcRatio(30, 40, 30)),
  custom('カスタム', '比率を自分で決める', null);

  final String label;
  final String description;

  /// プリセットの比率。カスタムはnull（プロフィール側の値を使う）。
  final PfcRatio? ratio;
  const PfcPreset(this.label, this.description, this.ratio);
}

class UserProfile {
  final Sex sex;
  final int age;
  final double heightCm;

  /// 現在の体重。体重の記録を付けると最新の値がここへ反映される。
  final double weightKg;

  final ActivityLevel activityLevel;
  final GoalType goal;

  /// 週あたりの体重変化の大きさ（kg/週）。向きは [goal] で決まる。
  final double weeklyRateKg;

  final PfcPreset pfcPreset;
  final PfcRatio pfcRatio;
  final double? targetWeightKg;

  /// 目標摂取カロリーを手動で決めた場合の値（計算値より優先）。
  final int? customTargetKcal;

  const UserProfile({
    required this.sex,
    required this.age,
    required this.heightCm,
    required this.weightKg,
    required this.activityLevel,
    required this.goal,
    required this.weeklyRateKg,
    required this.pfcPreset,
    required this.pfcRatio,
    this.targetWeightKg,
    this.customTargetKcal,
  });

  UserProfile copyWith({
    Sex? sex,
    int? age,
    double? heightCm,
    double? weightKg,
    ActivityLevel? activityLevel,
    GoalType? goal,
    double? weeklyRateKg,
    PfcPreset? pfcPreset,
    PfcRatio? pfcRatio,
    double? Function()? targetWeightKg,
    int? Function()? customTargetKcal,
  }) => UserProfile(
    sex: sex ?? this.sex,
    age: age ?? this.age,
    heightCm: heightCm ?? this.heightCm,
    weightKg: weightKg ?? this.weightKg,
    activityLevel: activityLevel ?? this.activityLevel,
    goal: goal ?? this.goal,
    weeklyRateKg: weeklyRateKg ?? this.weeklyRateKg,
    pfcPreset: pfcPreset ?? this.pfcPreset,
    pfcRatio: pfcRatio ?? this.pfcRatio,
    targetWeightKg: targetWeightKg != null
        ? targetWeightKg()
        : this.targetWeightKg,
    customTargetKcal: customTargetKcal != null
        ? customTargetKcal()
        : this.customTargetKcal,
  );

  /// 範囲外の値が無いかを検証し、問題があれば理由を返す（問題なければnull）。
  String? validate() {
    if (age < kMinAge || age > kMaxAge) {
      return '年齢は$kMinAge〜$kMaxAge歳で入力してください';
    }
    if (heightCm < kMinHeightCm || heightCm > kMaxHeightCm) {
      return '身長は${kMinHeightCm.toInt()}〜${kMaxHeightCm.toInt()}cmで入力してください';
    }
    if (weightKg < kMinWeightKg || weightKg > kMaxWeightKg) {
      return '体重は${kMinWeightKg.toInt()}〜${kMaxWeightKg.toInt()}kgで入力してください';
    }
    final target = targetWeightKg;
    if (target != null && (target < kMinWeightKg || target > kMaxWeightKg)) {
      return '目標体重は${kMinWeightKg.toInt()}〜${kMaxWeightKg.toInt()}kgで入力してください';
    }
    if (!goal.rateOptions.contains(weeklyRateKg)) {
      return 'ペースを選び直してください';
    }
    if (!pfcRatio.isValid) {
      return 'PFCの比率は各$kMinPfcRatio〜$kMaxPfcRatio%、合計100%にしてください';
    }
    final custom = customTargetKcal;
    if (custom != null &&
        (custom < kMinCustomTargetKcal || custom > kMaxCustomTargetKcal)) {
      return '目標カロリーは$kMinCustomTargetKcal〜${kMaxCustomTargetKcal}kcalで入力してください';
    }
    return null;
  }

  Map<String, dynamic> toMap() => {
    'sex': sex.name,
    'age': age,
    'heightCm': heightCm,
    'weightKg': weightKg,
    'activityLevel': activityLevel.name,
    'goal': goal.name,
    'weeklyRateKg': weeklyRateKg,
    'pfcPreset': pfcPreset.name,
    'proteinRatio': pfcRatio.protein,
    'fatRatio': pfcRatio.fat,
    'carbsRatio': pfcRatio.carbs,
    'targetWeightKg': targetWeightKg,
    'customTargetKcal': customTargetKcal,
  };

  /// 保存済みのプロフィールを読む。
  ///
  /// 未入力（フィールド自体が無い）や、必須項目が欠けている・範囲外の
  /// 場合はnullを返し、呼び出し側でプロフィール入力（オンボーディング）へ
  /// 誘導させる。中途半端な値で消費カロリーを計算して誤った目標を
  /// 出すよりも、入力し直してもらうほうが安全。
  static UserProfile? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final sex = _enumByName(Sex.values, map['sex']);
    final activity = _enumByName(ActivityLevel.values, map['activityLevel']);
    final goal = _enumByName(GoalType.values, map['goal']);
    final preset = _enumByName(PfcPreset.values, map['pfcPreset']);
    final age = map['age'];
    final height = map['heightCm'];
    final weight = map['weightKg'];
    final rate = map['weeklyRateKg'];
    final p = map['proteinRatio'];
    final f = map['fatRatio'];
    final c = map['carbsRatio'];
    if (sex == null ||
        activity == null ||
        goal == null ||
        preset == null ||
        age is! num ||
        height is! num ||
        weight is! num ||
        rate is! num ||
        p is! num ||
        f is! num ||
        c is! num) {
      return null;
    }
    final target = map['targetWeightKg'];
    final custom = map['customTargetKcal'];
    final profile = UserProfile(
      sex: sex,
      age: age.toInt(),
      heightCm: height.toDouble(),
      weightKg: weight.toDouble(),
      activityLevel: activity,
      goal: goal,
      weeklyRateKg: rate.toDouble(),
      pfcPreset: preset,
      pfcRatio: PfcRatio(p.toInt(), f.toInt(), c.toInt()),
      targetWeightKg: target is num ? target.toDouble() : null,
      customTargetKcal: custom is num ? custom.toInt() : null,
    );
    return profile.validate() == null ? profile : null;
  }

  @override
  bool operator ==(Object other) =>
      other is UserProfile &&
      other.sex == sex &&
      other.age == age &&
      other.heightCm == heightCm &&
      other.weightKg == weightKg &&
      other.activityLevel == activityLevel &&
      other.goal == goal &&
      other.weeklyRateKg == weeklyRateKg &&
      other.pfcPreset == pfcPreset &&
      other.pfcRatio == pfcRatio &&
      other.targetWeightKg == targetWeightKg &&
      other.customTargetKcal == customTargetKcal;

  @override
  int get hashCode => Object.hash(
    sex,
    age,
    heightCm,
    weightKg,
    activityLevel,
    goal,
    weeklyRateKg,
    pfcPreset,
    pfcRatio,
    targetWeightKg,
    customTargetKcal,
  );
}

T? _enumByName<T extends Enum>(List<T> values, Object? name) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}
