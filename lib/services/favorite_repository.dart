import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/food_item.dart';
import 'user_docs.dart';

class FavoriteRepository {
  FavoriteRepository(this._docs, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final UserDocs _docs;
  final DateTime Function() _clock;

  /// お気に入り（新しく登録した順）。
  Stream<List<FavoriteFood>> watchFavorites() => _docs.favorites
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) => [for (final doc in snap.docs) ?_fromDoc(doc)]);

  /// お気に入りに登録する。同じ名前・量のものは1件にまとめる（上書き）。
  Future<void> addFavorite(FoodItem food) {
    final normalized = normalizeFoodItem(food);
    return _docs.favorites.doc(favoriteIdFor(normalized)).set({
      ...normalized.toMap(),
      'createdAt': Timestamp.fromDate(_clock()),
    });
  }

  Future<void> deleteFavorite(String id) => _docs.favorites.doc(id).delete();

  /// 削除の「元に戻す」。同じID・登録日時で書き戻す（一覧の並び順も元に戻る）。
  Future<void> restoreFavorite(FavoriteFood favorite) =>
      _docs.favorites.doc(favorite.id).set({
        ...normalizeFoodItem(favorite.food).toMap(),
        'createdAt': Timestamp.fromDate(favorite.createdAt),
      });

  static FavoriteFood? _fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final food = FoodItem.fromMap(data);
    if (food.name.isEmpty) return null;
    final createdAt = data['createdAt'];
    return FavoriteFood(
      id: doc.id,
      food: food,
      createdAt: createdAt is Timestamp
          ? createdAt.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// お気に入りのドキュメントID。名前と量から決めるので、同じものを2回登録しても
/// 増えずに上書きになり、「お気に入り済みか」も名前と量だけで判定できる。
String favoriteIdFor(FoodItem food) => base64Url
    .encode(utf8.encode(normalizeFoodItem(food).identity))
    .replaceAll('=', '');
