import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Cloud Functionsのリージョン。functions/src/index.ts の setGlobalOptions と揃えること。
const kFunctionsRegion = 'asia-northeast1';

// ── 結合テスト(integration_test)用: Firebaseをローカルエミュレータへ向ける ──
//
// 通常のビルド（テスター配布・本番・開発中のflutter run）では
// USE_FIREBASE_EMULATOR が未定義なので false になり、この仕組みは完全に無効。
//
// 結合テスト時のみこう渡してエミュレータに繋ぐ:
//   flutter test integration_test --dart-define=USE_FIREBASE_EMULATOR=true
const bool useFirebaseEmulator = bool.fromEnvironment('USE_FIREBASE_EMULATOR');

// Androidエミュレータから見たホストマシンのアドレスは 10.0.2.2 固定。
// 実機から動かす場合は --dart-define=FIREBASE_EMULATOR_HOST=<PCのIP> で上書きする。
const String firebaseEmulatorHost = String.fromEnvironment(
  'FIREBASE_EMULATOR_HOST',
  defaultValue: '10.0.2.2',
);

// firebase.json の emulators 設定と一致させること
const int _authEmulatorPort = 9099;
const int _firestoreEmulatorPort = 8080;
const int _functionsEmulatorPort = 5001;

bool _initialized = false;

/// Firebaseを初期化する（結合テスト時はエミュレータへ繋ぐ）。
///
/// オプションを渡さずに初期化しているのは、Androidでは
/// android/app/google-services.json から生成された設定を読めるため。
/// Dart側に firebase_options.dart を置かずに済むので、CIの解析・テストは
/// Firebaseの秘密情報なしで実行できる。
///
/// エミュレータへの接続は、Firestoreを一度でも使ったあとに呼ぶと例外になるため、
/// main() とテストの両方から呼ばれても1回だけ行う。
Future<void> initializeFirebase() async {
  if (_initialized) return;
  _initialized = true;

  await Firebase.initializeApp();
  if (!useFirebaseEmulator) return;

  await FirebaseAuth.instance.useAuthEmulator(
    firebaseEmulatorHost,
    _authEmulatorPort,
  );
  FirebaseFirestore.instance.useFirestoreEmulator(
    firebaseEmulatorHost,
    _firestoreEmulatorPort,
  );
  FirebaseFunctions.instanceFor(
    region: kFunctionsRegion,
  ).useFunctionsEmulator(firebaseEmulatorHost, _functionsEmulatorPort);
}
