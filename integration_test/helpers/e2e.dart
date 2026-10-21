// ── 結合テスト共通の下ごしらえ ──────────────────────────────────────
//
// 本物のFirebase SDK（認証・Firestore・Cloud Functions）を使うが、接続先は
// ローカルのFirebaseエミュレータ（プロジェクトID demo-fuel）。本番には触れない。
// アプリはGoogleログインを使うがCIでは自動化できないので、匿名ログインで
// 利用者を作り、必要ならプロフィールを入れて「ログイン済み」の状態を作る。
//
// 単体・ウィジェットテスト（test/）では通れない経路だけを確かめる:
// main()の初期化、google-services.json からのFirebaseの初期化、実際の
// セキュリティルールを通した読み書き、Cloud Functions の呼び出し、実機のレイアウト。
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/app.dart';
import 'package:fuel/models/user_profile.dart';
import 'package:fuel/services/app_services.dart';
import 'package:fuel/services/firebase_bootstrap.dart';
import 'package:intl/date_symbol_data_local.dart';

/// 男性・35歳・170cm・70kg・適度な運動・週0.5kgの減量・バランス（目標1,950kcal）。
const e2eProfile = UserProfile(
  sex: Sex.male,
  age: 35,
  heightCm: 170,
  weightKg: 70,
  activityLevel: ActivityLevel.moderate,
  goal: GoalType.lose,
  weeklyRateKg: 0.5,
  pfcPreset: PfcPreset.balanced,
  pfcRatio: PfcRatio(20, 25, 55),
  targetWeightKg: 65,
);

/// Firebaseを初期化してエミュレータへ繋ぐ。setUpAllから1回だけ呼ぶ。
Future<void> initE2E() async {
  if (!useFirebaseEmulator) {
    // 本番のFirebaseに向けたまま結合テストを流すと実データを壊すため止める
    throw StateError(
      '結合テストは --dart-define=USE_FIREBASE_EMULATOR=true 付きで実行してください。'
      '本番のFirebaseへ接続した状態では実行できません。',
    );
  }
  await initializeFirebase();
  await initializeDateFormatting('ja');
}

/// 新しい匿名ユーザーでログインし直す（テストごとに別の利用者にして、
/// データを踏み合わないようにする）。uidを返す。
///
/// 前のテストのアプリを先に片付けてからログアウトする。画面が購読したまま
/// ログアウトすると、その購読が権限エラーになって「既に終わったテストの失敗」として
/// 計上されることがある（aimaruで実際に起きたフレーク）。
Future<String> signInAsNewUser(
  WidgetTester tester, {
  UserProfile? profile,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await FirebaseAuth.instance.signOut();
  final cred = await FirebaseAuth.instance.signInAnonymously();
  final uid = cred.user!.uid;
  if (profile != null) {
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'profile': profile.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
  return uid;
}

/// アプリ本体を、本番と同じサービス（AppServices.firebase）で起動する。
Future<void> pumpFuelApp(WidgetTester tester) async {
  await tester.pumpWidget(FuelApp(services: AppServices.firebase()));
  await settle(tester);
}

/// 画面が落ち着くまで待つ。
///
/// 読み込み中のインジケータが回り続けているとpumpAndSettleはタイムアウトで
/// 例外を投げるので、失敗扱いにせず一定回数pumpして先へ進める
/// （実際の待ち合わせはpumpUntilで行う）。
Future<void> settle(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  try {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      timeout,
    );
  } on FlutterError {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}

/// 条件を満たすまで繰り返しpumpする（Firestoreへの書き込み→画面への反映のように
/// 完了までの時間が読めない待ち合わせに使う）。
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 30),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 200));
  }
  fail(
    '${timeout.inSeconds}秒以内に条件を満たしませんでした${reason != null ? ': $reason' : ''}',
  );
}

/// Firestoreへ問い合わせて確認する版。
Future<void> pumpUntilAsync(
  WidgetTester tester,
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 30),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) return;
    await tester.pump(const Duration(milliseconds: 200));
  }
  fail(
    '${timeout.inSeconds}秒以内に条件を満たしませんでした${reason != null ? ': $reason' : ''}',
  );
}

/// labelTextで入力欄を特定する（画面はテスト用のKeyを持たない方針）。
Finder textFieldWithLabel(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
  description: 'labelTextが「$label」のTextField',
);

/// hintTextで入力欄を特定する。
Finder textFieldWithHint(String hintPrefix) => find.byWidgetPredicate(
  (w) =>
      w is TextField && (w.decoration?.hintText ?? '').startsWith(hintPrefix),
  description: 'hintTextが「$hintPrefix」で始まるTextField',
);

/// スクロールして画面内に出してから押す。
Future<void> scrollAndTap(WidgetTester tester, Finder finder) async {
  await settle(tester);
  await tester.ensureVisible(finder);
  await settle(tester);
  await tester.tap(finder);
  await settle(tester);
}

/// レイアウトのはみ出し（RenderFlex overflowなど）が起きていないことを確認する。
void expectNoLayoutOverflow(WidgetTester tester, {String? context}) {
  final exception = tester.takeException();
  if (exception == null) return;
  fail(
    'レイアウトのはみ出し/描画エラーが発生しました${context != null ? '（$context）' : ''}: $exception',
  );
}

/// 今日の日付キー（端末のローカル日付）。
String todayKey() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}
