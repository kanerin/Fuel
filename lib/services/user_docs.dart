import 'package:cloud_firestore/cloud_firestore.dart';

/// ログイン中の利用者のFirestoreのパス（docs/requirements.md 7章・firestore.rules と揃える）。
///
/// uidは呼び出しのたびに読む（ログアウト→別アカウントでログインしても
/// 古いuidを掴んだままにならないように）。テストでは固定のuidを渡す。
class UserDocs {
  UserDocs({FirebaseFirestore? firestore, required this._uid})
    : db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore db;
  final String Function() _uid;

  String get uid => _uid();

  DocumentReference<Map<String, dynamic>> get user =>
      db.collection('users').doc(uid);

  CollectionReference<Map<String, dynamic>> get meals =>
      user.collection('meals');

  CollectionReference<Map<String, dynamic>> get weights =>
      user.collection('weights');

  CollectionReference<Map<String, dynamic>> get favorites =>
      user.collection('favorites');

  /// AI推定の回数制限。Cloud Functionsだけが書き、本人は読むだけ。
  DocumentReference<Map<String, dynamic>> get aiUsage =>
      db.collection('aiUsage').doc(uid);
}
