import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

import '../logic/date_keys.dart';
import 'auth_service.dart';
import 'favorite_repository.dart';
import 'meal_repository.dart';
import 'nutrition_estimator.dart';
import 'photo_picker.dart';
import 'profile_repository.dart';
import 'user_docs.dart';
import 'weight_repository.dart';

/// 画面が使うサービス一式。
///
/// 画面はFirebaseを直接触らず、[AppScope] からこれを受け取って使う。
/// テストでは、FakeFirebaseFirestoreを使ったリポジトリや差し替えたAIを
/// 詰めたものを渡すことで、Firebaseを初期化せずに画面を検証できる。
class AppServices {
  AppServices({
    required this.auth,
    required this.profiles,
    required this.meals,
    required this.weights,
    required this.favorites,
    required this.estimator,
    required this.photoPicker,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// 本番用（Firebase初期化後に作ること）。
  factory AppServices.firebase() {
    final docs = UserDocs(uid: () => FirebaseAuth.instance.currentUser!.uid);
    return AppServices(
      auth: FirebaseAuthService(),
      profiles: ProfileRepository(docs),
      meals: MealRepository(docs),
      weights: WeightRepository(docs),
      favorites: FavoriteRepository(docs),
      estimator: CloudNutritionEstimator(),
      photoPicker: DeviceFoodPhotoPicker(),
    );
  }

  final AuthService auth;
  final ProfileRepository profiles;
  final MealRepository meals;
  final WeightRepository weights;
  final FavoriteRepository favorites;
  final NutritionEstimator estimator;
  final FoodPhotoPicker photoPicker;
  final DateTime Function() _clock;

  /// 現在時刻（テストでは固定できる）。
  DateTime now() => _clock();

  /// 今日の日付（時刻なし）。
  DateTime today() => dateOnly(_clock());
}

/// [AppServices] をウィジェットツリーへ配る。
///
/// MaterialAppより上に置くこと。Navigatorでpushした画面はMaterialAppの
/// 子になるので、それより下に置くとpush先から見つからない。
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope が見つかりません（MaterialAppより上に置くこと）');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}
