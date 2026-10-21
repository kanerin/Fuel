import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';

import '../models/food_item.dart';
import 'firebase_bootstrap.dart';

// AIによるPFC推定（Cloud Functions の estimateNutrition を呼ぶ）。
//
// プロンプトはサーバー側で組み立てる。クライアントから任意のプロンプトを
// 送れる作りにすると、関数が「誰でも使えるGeminiの中継」になってしまうため、
// ここから送るのは「食べたものの説明」と「写真」だけ。

/// AIへ送る文章の上限（functions/src/nutrition_logic.ts の MAX_TEXT_LENGTH と揃える）。
const kMaxEstimateTextLength = 500;

/// 推定結果として受け取る品目数の上限（同 MAX_ITEMS）。
const kMaxEstimateItems = 20;

/// 写真の長辺の上限（px）。大きいまま送ると通信量と推定時間が増えるだけで、
/// 料理の見分けには1280pxあれば足りる。
const kEstimatePhotoMaxDimension = 1280.0;

/// 写真（推定の入力）。
class EstimateImage {
  final Uint8List bytes;
  final String mimeType;

  const EstimateImage({required this.bytes, required this.mimeType});
}

/// AIの推定結果。
class NutritionEstimate {
  /// 品目ごとの推定値。食べ物が見つからなければ空。
  final List<FoodItem> items;

  /// 推定の前提（「量の指定が無いため1人前として推定」など）。無ければ空文字。
  final String note;

  /// 今日の残り回数（サーバーが返した場合）。
  final int? remainingToday;

  const NutritionEstimate({
    required this.items,
    this.note = '',
    this.remainingToday,
  });
}

/// 推定に失敗したときの例外。[message] はそのまま画面に出せる文言。
class NutritionEstimateException implements Exception {
  final String message;

  const NutritionEstimateException(this.message);

  @override
  String toString() => 'NutritionEstimateException: $message';
}

abstract class NutritionEstimator {
  /// [text]（食べたものの説明）と [image]（食事の写真）の少なくとも一方から推定する。
  /// 失敗したら [NutritionEstimateException]。
  Future<NutritionEstimate> estimate({String text = '', EstimateImage? image});
}

const kEstimateEmptyInputMessage = '食べたものを入力するか、写真を選んでください';
const kEstimateTooLongMessage = '$kMaxEstimateTextLength文字以内で入力してください';
const kEstimateUnreadableMessage = 'AIの応答を読み取れませんでした。もう一度お試しください。';
const kEstimateDailyLimitMessage =
    '今日のAI推定の回数を使い切りました。明日またお試しいただくか、手入力・お気に入りから記録してください。';
const kEstimateBusyMessage = 'AIが混み合っています。しばらく時間をおいてからお試しください。';
const kEstimateNetworkMessage = '通信に失敗しました。電波の良いところでもう一度お試しください。';
const kEstimateSignInMessage = 'ログインの有効期限が切れました。ログインし直してください。';
const kEstimateNotReadyMessage =
    'AI推定が現在ご利用いただけません（サーバーの設定が完了していません）。手入力・お気に入りから記録できます。';
const kEstimateNotDeployedMessage = 'AI推定の機能がまだサーバーに用意されていません。復旧までお待ちください。';
const kEstimateFailedMessage = 'AIの推定に失敗しました。書き方を変えるか、しばらくしてからお試しください。';

class CloudNutritionEstimator implements NutritionEstimator {
  /// 本番はCloud Functionsを呼ぶ。テストでは [invoke] で応答を差し込む。
  CloudNutritionEstimator({
    Future<Object?> Function(Map<String, Object?> data)? invoke,
  }) : _invoke = invoke ?? _callFunction;

  final Future<Object?> Function(Map<String, Object?> data) _invoke;

  static Future<Object?> _callFunction(Map<String, Object?> data) async {
    final callable = FirebaseFunctions.instanceFor(region: kFunctionsRegion)
        .httpsCallable(
          'estimateNutrition',
          // Geminiの応答（特に写真）は数秒〜十数秒かかることがある
          options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
        );
    // call<Map<String, dynamic>> にすると、プラットフォームチャネルから届く
    // Map<Object?, Object?> の暗黙のキャストで落ちることがあるため、受け取ってから読む
    final result = await callable.call<Object?>(data);
    return result.data;
  }

  @override
  Future<NutritionEstimate> estimate({
    String text = '',
    EstimateImage? image,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && image == null) {
      throw const NutritionEstimateException(kEstimateEmptyInputMessage);
    }
    if (trimmed.length > kMaxEstimateTextLength) {
      throw const NutritionEstimateException(kEstimateTooLongMessage);
    }

    final Object? data;
    try {
      data = await _invoke({
        'text': trimmed,
        if (image != null)
          'image': {
            'mimeType': image.mimeType,
            'data': base64Encode(image.bytes),
          },
      });
    } catch (e) {
      throw NutritionEstimateException(describeEstimateFailure(e));
    }

    final estimate = parseEstimateResponse(data);
    if (estimate == null) {
      throw const NutritionEstimateException(kEstimateUnreadableMessage);
    }
    return estimate;
  }
}

/// estimateNutrition の応答を読む。形が違えばnull（記録は作らない）。
///
/// サーバー側でも検証・正規化しているが、古い関数がデプロイされたまま等で
/// 形がずれても壊れた記録を作らないよう、ここでも1品ずつ確かめる。
NutritionEstimate? parseEstimateResponse(Object? data) {
  if (data is! Map) return null;
  final items = data['items'];
  if (items is! List) return null;

  final foods = <FoodItem>[];
  for (final raw in items) {
    if (foods.length >= kMaxEstimateItems) break;
    if (raw is! Map) continue;
    final Map<String, dynamic> map;
    try {
      map = Map<String, dynamic>.from(raw);
    } catch (_) {
      continue;
    }
    final name = map['name'];
    if (name is! String || name.trim().isEmpty) continue;
    foods.add(normalizeFoodItem(FoodItem.fromMap(map)));
  }

  final note = data['note'];
  final remaining = data['remaining'];
  return NutritionEstimate(
    items: foods,
    note: note is String ? note.trim() : '',
    remainingToday: remaining is num ? remaining.toInt() : null,
  );
}

/// 推定の呼び出しが失敗した理由を、利用者が次に取れる行動へ翻訳する。
///
/// サーバー（functions/src/index.ts の estimateNutrition）が投げる
/// HttpsError の code と対応させている。
String describeEstimateFailure(Object error) {
  if (error is FirebaseFunctionsException) {
    switch (error.code) {
      case 'resource-exhausted':
        // 1日の上限（利用者側の都合）とGeminiのクォータ切れ（サーバー側の都合）を
        // 同じ文言にすると、利用者には「明日まで使えない」のか「少し待てば
        // 使える」のかが分からないため、details.reason で分ける。
        final details = error.details;
        if (details is Map && details['reason'] == 'daily_limit') {
          return kEstimateDailyLimitMessage;
        }
        return kEstimateBusyMessage;
      case 'unauthenticated':
        return kEstimateSignInMessage;
      case 'invalid-argument':
        final message = error.message;
        return message != null && message.isNotEmpty
            ? message
            : kEstimateFailedMessage;
      case 'failed-precondition':
        return kEstimateNotReadyMessage;
      case 'unavailable':
      case 'deadline-exceeded':
        return kEstimateNetworkMessage;
      // 関数そのものに到達できない（本番へデプロイされていない等）。
      // 「通信エラー」と一括りにすると一時的な不調と区別できなくなる。
      case 'not-found':
      case 'unimplemented':
        return kEstimateNotDeployedMessage;
    }
    return kEstimateFailedMessage;
  }

  final s = error.toString().toLowerCase();
  if (s.contains('socket') ||
      s.contains('timeout') ||
      s.contains('timed out') ||
      s.contains('network') ||
      s.contains('connection')) {
    return kEstimateNetworkMessage;
  }
  return kEstimateFailedMessage;
}
