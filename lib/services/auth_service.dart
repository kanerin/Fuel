import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'firebase_bootstrap.dart';

/// ログイン中の利用者。Firebaseの型を画面へ持ち込まないための薄い写し
/// （画面のテストでFirebaseを初期化せずに済むようにする）。
class AppUser {
  final String uid;
  final String? displayName;
  final String? email;

  const AppUser({required this.uid, this.displayName, this.email});
}

abstract class AuthService {
  Stream<AppUser?> authStateChanges();

  AppUser? get currentUser;

  /// Googleでログインする。利用者がアカウント選択をキャンセルした場合はnull。
  Future<AppUser?> signInWithGoogle();

  Future<void> signOut();

  /// アカウントと全データを削除する（Cloud FunctionsのdeleteAccount）。取り消せない。
  Future<void> deleteAccount();
}

class FirebaseAuthService implements AuthService {
  FirebaseAuthService({
    FirebaseAuth? auth,
    GoogleSignIn? googleSignIn,
    FirebaseFunctions? functions,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _googleSignIn = googleSignIn ?? GoogleSignIn(scopes: const ['email']),
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: kFunctionsRegion);

  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;
  final FirebaseFunctions _functions;

  static AppUser? _toAppUser(User? user) => user == null
      ? null
      : AppUser(
          uid: user.uid,
          displayName: user.displayName,
          email: user.email,
        );

  @override
  Stream<AppUser?> authStateChanges() =>
      _auth.authStateChanges().map(_toAppUser);

  @override
  AppUser? get currentUser => _toAppUser(_auth.currentUser);

  @override
  Future<AppUser?> signInWithGoogle() async {
    final account = await _googleSignIn.signIn();
    if (account == null) return null;

    final googleAuth = await account.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
      accessToken: googleAuth.accessToken,
    );
    final result = await _auth.signInWithCredential(credential);
    return _toAppUser(result.user);
  }

  @override
  Future<void> signOut() async {
    // Google側のセッションも閉じる。閉じないと次回ログインでアカウント選択が
    // 出ず、前回のアカウントへ自動で入ってしまう（別アカウントに切り替えられない）。
    await _signOutGoogle();
    await _auth.signOut();
  }

  @override
  Future<void> deleteAccount() async {
    // 削除はサーバー側でまとめて行う（サブコレクションの再帰削除とAuthの
    // ユーザー削除。クライアントから1件ずつ消すと、途中で失敗したときに
    // 中途半端なデータが残る）。
    await _functions.httpsCallable('deleteAccount').call<Object?>();
    await _signOutGoogle(disconnect: true);
    await _auth.signOut();
  }

  // 結合テストの匿名ログインのように、Googleでログインしていない場合は
  // ここが例外を投げるが、ログアウト自体は続行させる。
  Future<void> _signOutGoogle({bool disconnect = false}) async {
    try {
      if (disconnect) {
        await _googleSignIn.disconnect();
      } else {
        await _googleSignIn.signOut();
      }
    } catch (e) {
      debugPrint('[Googleのサインアウトに失敗（続行します）] $e');
    }
  }
}
