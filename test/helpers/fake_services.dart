import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fuel/models/food_item.dart';
import 'package:fuel/models/meal_entry.dart';
import 'package:fuel/models/nutrition.dart';
import 'package:fuel/models/user_profile.dart';
import 'package:fuel/models/weight_log.dart';
import 'package:fuel/services/app_services.dart';
import 'package:fuel/services/auth_service.dart';
import 'package:fuel/services/favorite_repository.dart';
import 'package:fuel/services/meal_repository.dart';
import 'package:fuel/services/nutrition_estimator.dart';
import 'package:fuel/services/photo_picker.dart';
import 'package:fuel/services/profile_repository.dart';
import 'package:fuel/services/user_docs.dart';
import 'package:fuel/services/weight_repository.dart';

// 画面・サービスのテスト用の差し替え一式。
// Firestoreは FakeFirebaseFirestore（インメモリ）を使い、リポジトリは本物を使う。
// クエリ・並び順・バッチの組み立てまで本物の経路を通したいため。

const testUid = 'u1';

/// テスト中の「現在時刻」。2026-10-21(水) 12:30。
final testNow = DateTime(2026, 10, 21, 12, 30);

class TestEnv {
  TestEnv({
    FakeFirebaseFirestore? firestore,
    FakeEstimator? estimator,
    FakePhotoPicker? photoPicker,
    FakeAuthService? auth,
    DateTime? now,
    this.mealsOverride,
    this.weightsOverride,
    this.favoritesOverride,
    this.profilesOverride,
  }) : firestore = firestore ?? FakeFirebaseFirestore(),
       estimator = estimator ?? FakeEstimator(),
       photoPicker = photoPicker ?? FakePhotoPicker(),
       auth = auth ?? FakeAuthService(user: testUser),
       now = now ?? testNow;

  final FakeFirebaseFirestore firestore;
  final FakeAuthService auth;
  final FakeEstimator estimator;
  final FakePhotoPicker photoPicker;
  DateTime now;

  /// 読み込みの失敗を再現したいときなどに、リポジトリを差し替える。
  final MealRepository Function(UserDocs docs)? mealsOverride;
  final WeightRepository Function(UserDocs docs)? weightsOverride;
  final FavoriteRepository Function(UserDocs docs)? favoritesOverride;
  final ProfileRepository Function(UserDocs docs)? profilesOverride;

  late final UserDocs docs = UserDocs(firestore: firestore, uid: () => testUid);

  late final AppServices services = AppServices(
    auth: auth,
    profiles: profilesOverride?.call(docs) ?? ProfileRepository(docs),
    meals: mealsOverride?.call(docs) ?? MealRepository(docs, clock: () => now),
    weights: weightsOverride?.call(docs) ?? WeightRepository(docs),
    favorites:
        favoritesOverride?.call(docs) ??
        FavoriteRepository(docs, clock: () => now),
    estimator: estimator,
    photoPicker: photoPicker,
    clock: () => now,
  );

  /// プロフィールを保存済みの状態にする。
  Future<void> seedProfile(UserProfile profile) =>
      docs.user.set({'profile': profile.toMap()});

  /// 食事の記録を直接入れる（画面を通さずに前提データを作る）。
  Future<void> seedEntry(MealEntry entry) =>
      docs.meals.doc(entry.id).set(entry.toMap());

  /// 保存されている食事の記録（記録した順）。
  Future<List<MealEntry>> savedEntries() async {
    final snap = await docs.meals.get();
    return snap.docs.map((d) => MealEntry.fromMap(d.id, d.data())).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }
}

const testUser = AppUser(
  uid: testUid,
  displayName: 'テスト',
  email: 'test@example.com',
);

/// 読み込みが必ず失敗するストリーム（権限エラーなど）。
Stream<T> failingStream<T>() => Stream<T>.error(Exception('PERMISSION_DENIED'));

class FailingMealRepository extends MealRepository {
  FailingMealRepository(super.docs);

  @override
  Stream<List<MealEntry>> watchDay(String dateKey) => failingStream();

  @override
  Stream<List<MealEntry>> watchRange(String startKey, String endKey) =>
      failingStream();

  @override
  Future<List<FoodItem>> recentFoods({int limit = 20}) =>
      Future.error(Exception('PERMISSION_DENIED'));
}

class FailingWeightRepository extends WeightRepository {
  FailingWeightRepository(super.docs);

  @override
  Stream<List<WeightLog>> watchLogs({int limit = 400}) => failingStream();
}

class FailingFavoriteRepository extends FavoriteRepository {
  FailingFavoriteRepository(super.docs);

  @override
  Stream<List<FavoriteFood>> watchFavorites() => failingStream();
}

class FailingProfileRepository extends ProfileRepository {
  FailingProfileRepository(super.docs);

  @override
  Stream<UserProfile?> watchProfile() => failingStream();

  @override
  Stream<AiUsage> watchAiUsage(String todayKey) => failingStream();
}

class FakeAuthService implements AuthService {
  FakeAuthService({this._user});

  AppUser? _user;
  final _controller = StreamController<AppUser?>.broadcast();
  int signInCalls = 0;
  int signOutCalls = 0;
  int deleteCalls = 0;

  /// signInWithGoogle の結果を差し替える（nullならキャンセル扱い）。
  Future<AppUser?> Function() onSignIn = () async => const AppUser(
    uid: testUid,
    displayName: 'テスト',
    email: 'test@example.com',
  );

  Future<void> Function() onDelete = () async {};

  @override
  AppUser? get currentUser => _user;

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield _user;
    yield* _controller.stream;
  }

  void emit(AppUser? user) {
    _user = user;
    _controller.add(user);
  }

  @override
  Future<AppUser?> signInWithGoogle() async {
    signInCalls++;
    final user = await onSignIn();
    if (user != null) emit(user);
    return user;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    emit(null);
  }

  @override
  Future<void> deleteAccount() async {
    deleteCalls++;
    await onDelete();
    emit(null);
  }
}

/// 呼ばれた内容を記録し、決めておいた結果を返すAI。
class FakeEstimator implements NutritionEstimator {
  FakeEstimator({this.result, this.error});

  NutritionEstimate? result;
  Object? error;

  /// 応答を手動で返したいとき（ローディング表示の検証など）に使う。
  Completer<NutritionEstimate>? pending;

  final calls = <({String text, EstimateImage? image})>[];

  @override
  Future<NutritionEstimate> estimate({
    String text = '',
    EstimateImage? image,
  }) async {
    calls.add((text: text, image: image));
    final p = pending;
    if (p != null) return p.future;
    final e = error;
    if (e != null) throw e;
    return result ?? const NutritionEstimate(items: []);
  }
}

class FakePhotoPicker implements FoodPhotoPicker {
  FakePhotoPicker({this.image});

  EstimateImage? image;
  final sources = <PhotoSource>[];

  @override
  Future<EstimateImage?> pick(PhotoSource source) async {
    sources.add(source);
    return image;
  }
}

/// FirebaseFunctionsException はコンストラクタが @protected なので、
/// テストからはサブクラス経由で作る。
class FakeFunctionsException extends FirebaseFunctionsException {
  FakeFunctionsException(String code, {super.message = 'テスト用', super.details})
    : super(code: code);
}

/// AIの推定結果のサンプル（牛丼並盛と味噌汁）。
const sampleEstimate = NutritionEstimate(
  items: [
    FoodItem(
      name: '牛丼',
      amount: '並盛',
      nutrition: Nutrition(calories: 650, protein: 22, fat: 22, carbs: 90),
    ),
    FoodItem(
      name: '味噌汁',
      amount: '1杯',
      nutrition: Nutrition(calories: 40, protein: 3, fat: 1.5, carbs: 4),
    ),
  ],
  note: '並盛1杯として推定しました',
  remainingToday: 48,
);
