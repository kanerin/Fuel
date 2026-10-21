import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/models/nutrition.dart';
import 'package:fuel/services/nutrition_estimator.dart';

import '../helpers/fake_services.dart';

// CloudNutritionEstimator は実際のCloud Functions呼び出しを invoke に
// 差し込めるので、ネットワークにもエミュレータにも触れずに
// 「何を送るか」「応答をどう読むか」「失敗をどう伝えるか」を検証する。
void main() {
  group('送る内容', () {
    test('文章は前後の空白を落として送る', () async {
      Map<String, Object?>? sent;
      final estimator = CloudNutritionEstimator(
        invoke: (data) async {
          sent = data;
          return {'items': <Object?>[]};
        },
      );

      await estimator.estimate(text: '  牛丼並盛と味噌汁\n');

      expect(sent, {'text': '牛丼並盛と味噌汁'});
    });

    test('写真はbase64で、種類と一緒に送る', () async {
      Map<String, Object?>? sent;
      final estimator = CloudNutritionEstimator(
        invoke: (data) async {
          sent = data;
          return {'items': <Object?>[]};
        },
      );

      await estimator.estimate(
        image: EstimateImage(
          bytes: Uint8List.fromList([1, 2, 3]),
          mimeType: 'image/jpeg',
        ),
      );

      expect(sent, {
        'text': '',
        'image': {
          'mimeType': 'image/jpeg',
          'data': base64Encode([1, 2, 3]),
        },
      });
    });

    test('文章も写真も無ければ、呼び出さずに入力を促す', () async {
      var called = false;
      final estimator = CloudNutritionEstimator(
        invoke: (_) async {
          called = true;
          return null;
        },
      );

      await expectLater(
        estimator.estimate(text: '   '),
        throwsA(
          isA<NutritionEstimateException>().having(
            (e) => e.message,
            'message',
            kEstimateEmptyInputMessage,
          ),
        ),
      );
      expect(called, isFalse);
    });

    test('長すぎる文章は呼び出さずに弾く', () async {
      final estimator = CloudNutritionEstimator(invoke: (_) async => null);

      await expectLater(
        estimator.estimate(text: 'あ' * (kMaxEstimateTextLength + 1)),
        throwsA(isA<NutritionEstimateException>()),
      );
    });
  });

  group('parseEstimateResponse', () {
    test('品目ごとの推定値・前提・残り回数を読む', () {
      final estimate = parseEstimateResponse({
        'items': [
          {
            'name': '牛丼',
            'amount': '並盛',
            'calories': 650,
            'protein': 22,
            'fat': 22,
            'carbs': 90,
          },
          {
            'name': '味噌汁',
            'amount': '1杯',
            'calories': 40,
            'protein': 3,
            'fat': 1.5,
            'carbs': 4,
          },
        ],
        'note': ' 並盛1杯として推定しました ',
        'remaining': 48,
      })!;

      expect(estimate.items.map((f) => f.name), ['牛丼', '味噌汁']);
      expect(
        estimate.items.first.nutrition,
        const Nutrition(calories: 650, protein: 22, fat: 22, carbs: 90),
      );
      expect(estimate.note, '並盛1杯として推定しました');
      expect(estimate.remainingToday, 48);
    });

    test('プラットフォームチャネル由来の Map<Object?, Object?> でも読める', () {
      final raw = <Object?, Object?>{
        'items': <Object?>[
          <Object?, Object?>{
            'name': 'おにぎり',
            'amount': '1個',
            'calories': 180,
            'protein': 3,
            'fat': 0.5,
            'carbs': 40,
          },
        ],
      };

      expect(parseEstimateResponse(raw)!.items.single.name, 'おにぎり');
    });

    test('名前の無い品・オブジェクトでない要素は捨て、範囲外の値は範囲に収めて丸める', () {
      final estimate = parseEstimateResponse({
        'items': [
          {'name': '', 'calories': 100},
          'ラーメン',
          {
            'name': 'ピザ1枚まるごと',
            'calories': 9999.6,
            'protein': -5,
            'fat': 80.04,
            'carbs': 'x',
          },
        ],
      })!;

      expect(estimate.items.single.name, 'ピザ1枚まるごと');
      expect(
        estimate.items.single.nutrition,
        const Nutrition(calories: 5000, protein: 0, fat: 80, carbs: 0),
      );
    });

    test('品目数は上限まで', () {
      final estimate = parseEstimateResponse({
        'items': [
          for (var i = 0; i < kMaxEstimateItems + 5; i++)
            {'name': '品$i', 'calories': 10},
        ],
      })!;

      expect(estimate.items, hasLength(kMaxEstimateItems));
    });

    test('食べ物が見つからなかった（空配列）はそのまま空の結果', () {
      final estimate = parseEstimateResponse({
        'items': <Object?>[],
        'note': '食べ物の説明が見つかりませんでした',
      })!;

      expect(estimate.items, isEmpty);
      expect(estimate.note, contains('見つかりません'));
    });

    test('形が違えばnull（記録を作らない）', () {
      expect(parseEstimateResponse(null), isNull);
      expect(parseEstimateResponse('牛丼 650kcal'), isNull);
      expect(parseEstimateResponse({'items': '牛丼'}), isNull);
    });
  });

  test('読めない応答は「読み取れませんでした」として失敗させる', () async {
    final estimator = CloudNutritionEstimator(invoke: (_) async => 'not json');

    await expectLater(
      estimator.estimate(text: '牛丼'),
      throwsA(
        isA<NutritionEstimateException>().having(
          (e) => e.message,
          'message',
          kEstimateUnreadableMessage,
        ),
      ),
    );
  });

  group('describeEstimateFailure', () {
    test('1日の上限に達した（details.reason=daily_limit）', () {
      expect(
        describeEstimateFailure(
          FakeFunctionsException(
            'resource-exhausted',
            details: {'reason': 'daily_limit'},
          ),
        ),
        kEstimateDailyLimitMessage,
      );
    });

    test('Gemini側のクォータ切れは「混み合っている」（明日まで使えないわけではない）', () {
      expect(
        describeEstimateFailure(FakeFunctionsException('resource-exhausted')),
        kEstimateBusyMessage,
      );
    });

    test('入力の不備はサーバーの文言をそのまま見せる', () {
      expect(
        describeEstimateFailure(
          FakeFunctionsException('invalid-argument', message: '写真が大きすぎます'),
        ),
        '写真が大きすぎます',
      );
    });

    test('code ごとの文言', () {
      expect(
        describeEstimateFailure(FakeFunctionsException('unauthenticated')),
        kEstimateSignInMessage,
      );
      expect(
        describeEstimateFailure(FakeFunctionsException('failed-precondition')),
        kEstimateNotReadyMessage,
      );
      expect(
        describeEstimateFailure(FakeFunctionsException('unavailable')),
        kEstimateNetworkMessage,
      );
      expect(
        describeEstimateFailure(FakeFunctionsException('deadline-exceeded')),
        kEstimateNetworkMessage,
      );
      expect(
        describeEstimateFailure(FakeFunctionsException('not-found')),
        kEstimateNotDeployedMessage,
      );
      expect(
        describeEstimateFailure(FakeFunctionsException('internal')),
        kEstimateFailedMessage,
      );
    });

    test('Functions以外の例外は文字列から通信の失敗を見分ける', () {
      expect(
        describeEstimateFailure(const SocketException('Failed host lookup')),
        kEstimateNetworkMessage,
      );
      expect(describeEstimateFailure(StateError('?')), kEstimateFailedMessage);
    });

    test('呼び出しの失敗は NutritionEstimateException に包んで投げる', () async {
      final estimator = CloudNutritionEstimator(
        invoke: (_) async => throw FakeFunctionsException('unavailable'),
      );

      await expectLater(
        estimator.estimate(text: '牛丼'),
        throwsA(
          isA<NutritionEstimateException>().having(
            (e) => e.message,
            'message',
            kEstimateNetworkMessage,
          ),
        ),
      );
    });
  });
}
