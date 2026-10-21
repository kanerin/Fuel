import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/models/meal_entry.dart';
import 'package:fuel/screens/entry_form_screen.dart';
import 'package:fuel/screens/today_screen.dart';
import 'package:fuel/services/meal_repository.dart';
import 'package:fuel/services/nutrition_estimator.dart';
import 'package:fuel/services/photo_picker.dart';

import '../helpers/fake_services.dart';
import '../helpers/fixtures.dart';
import '../helpers/pump.dart';

/// 1日分の記録のストリームを手で流せるリポジトリ（ローディング表示の検証用）。
class _ControlledMealRepository extends MealRepository {
  _ControlledMealRepository(super.docs);

  final controller = StreamController<List<MealEntry>>();

  @override
  Stream<List<MealEntry>> watchDay(String dateKey) => controller.stream;
}

void main() {
  setUpAll(setUpScreenTests);

  Future<TestEnv> setUpEnv({
    FakeEstimator? estimator,
    FakePhotoPicker? photoPicker,
  }) async {
    final env = TestEnv(estimator: estimator, photoPicker: photoPicker);
    await env.seedProfile(sampleProfile);
    return env;
  }

  Future<void> pumpToday(WidgetTester tester, TestEnv env) =>
      pumpApp(tester, env, const TodayScreen(profile: sampleProfile));

  /// 入力欄に書いて送信する。enterText はフレームを進めないので、送信ボタンが
  /// 押せる状態に描き直されるのを待ってから押す。
  Future<void> submit(
    WidgetTester tester,
    String text, {
    bool settle = true,
  }) async {
    await tester.enterText(textFieldWithHint('食べたものを入力'), text);
    await tester.pump();
    await tester.tap(find.byTooltip('AIでPFCを推定'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  group('読み込みの3状態', () {
    testWidgets('データが来る前はローディング表示', (tester) async {
      late _ControlledMealRepository repo;
      final env = TestEnv(
        mealsOverride: (docs) => repo = _ControlledMealRepository(docs),
      );
      await pumpToday(tester, env);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      repo.controller.add(const []);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // 4つの食事区分のカード（画面外のカードはListViewがまだ作らない）
      expect(find.text('まだ記録がありません'), findsWidgets);
    });

    testWidgets('読み込みに失敗したら、無限ローディングではなくエラー表示にする', (tester) async {
      final env = TestEnv(mealsOverride: FailingMealRepository.new);
      await pumpToday(tester, env);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('記録を読み込めませんでした'), findsOneWidget);
      expect(find.text('再読み込み'), findsOneWidget);
    });

    testWidgets('記録が無ければ0kcalと、入力のヒントを出す', (tester) async {
      final env = await setUpEnv();
      await pumpToday(tester, env);

      expect(find.text('0 kcal'), findsOneWidget);
      expect(find.text('1,950 kcal'), findsNWidgets(2)); // 目標と「あと」
      expect(find.textContaining('下の欄に食べたものを書くと'), findsOneWidget);
    });
  });

  testWidgets('記録を食事区分ごとに表示し、合計・目標・残りを出す', (tester) async {
    final env = await setUpEnv();
    await env.seedEntry(
      entry(
        'a',
        mealType: MealType.breakfast,
        name: 'トースト',
        amount: '1枚',
        kcal: 250,
        p: 8,
        f: 4,
        c: 45,
      ),
    );
    await env.seedEntry(
      entry(
        'b',
        mealType: MealType.lunch,
        name: '牛丼',
        amount: '並盛',
        kcal: 650,
        p: 22,
        f: 22,
        c: 90,
      ),
    );
    await env.seedEntry(
      entry('c', dateKey: '2026-10-20', name: '昨日のカレー', kcal: 800),
    );
    await pumpToday(tester, env);

    expect(find.text('トースト'), findsOneWidget);
    expect(find.text('牛丼'), findsOneWidget);
    expect(find.text('昨日のカレー'), findsNothing, reason: '別の日の記録は出さない');
    expect(find.text('900 kcal'), findsOneWidget); // 食べた
    expect(find.text('1,050 kcal'), findsOneWidget); // あと 1950 - 900
    expect(find.text('46%'), findsOneWidget); // 900 / 1950
    expect(find.text('30 / 98 g'), findsOneWidget); // たんぱく質
    expect(find.text('AI'), findsNWidgets(2), reason: 'AIの推定値には印を付ける');
  });

  testWidgets('目標を超えたら「超過」と表示する', (tester) async {
    final env = await setUpEnv();
    await env.seedEntry(entry('a', kcal: 2100));
    await pumpToday(tester, env);

    expect(find.text('超過'), findsOneWidget);
    expect(find.text('150 kcal'), findsOneWidget);
  });

  group('AIで推定して追加する', () {
    testWidgets('入力 → 推定 → 結果を確かめて追加すると、その日の記録に保存される', (tester) async {
      final estimator = FakeEstimator(result: sampleEstimate);
      final env = await setUpEnv(estimator: estimator);
      await pumpToday(tester, env);

      await submit(tester, '牛丼並盛と味噌汁');

      expect(estimator.calls.single.text, '牛丼並盛と味噌汁');
      expect(find.text('AIの推定結果'), findsOneWidget);
      expect(find.text('牛丼（並盛）'), findsOneWidget);
      expect(find.text('味噌汁（1杯）'), findsOneWidget);
      expect(find.text('並盛1杯として推定しました'), findsOneWidget);
      expect(find.text('690 kcal'), findsOneWidget); // 合計

      await tester.tap(find.text('2品を追加'));
      await tester.pumpAndSettle();

      expect(find.text('昼食に2品を追加しました'), findsOneWidget);
      final saved = await env.savedEntries();
      expect(saved.map((e) => e.food.name), ['牛丼', '味噌汁']);
      // 12:30に追加したので、食事区分の初期値は昼食
      expect(saved.every((e) => e.mealType == MealType.lunch), isTrue);
      expect(saved.every((e) => e.source == EntrySource.ai), isTrue);
      expect(saved.every((e) => e.dateKey == '2026-10-21'), isTrue);
      // 画面にも反映され、入力欄は空になる
      expect(find.text('牛丼'), findsOneWidget);
      expect(find.text('牛丼並盛と味噌汁'), findsNothing);
    });

    testWidgets('チェックを外した品は追加しない・食事区分を変えられる', (tester) async {
      final env = await setUpEnv(
        estimator: FakeEstimator(result: sampleEstimate),
      );
      await pumpToday(tester, env);

      await submit(tester, '牛丼並盛と味噌汁');

      await tester.tap(find.text('味噌汁（1杯）'));
      await tester.tap(find.text('夕食').last);
      await tester.pumpAndSettle();
      expect(find.text('650 kcal'), findsWidgets);

      await tester.tap(find.text('1品を追加'));
      await tester.pumpAndSettle();

      final saved = await env.savedEntries();
      expect(saved.single.food.name, '牛丼');
      expect(saved.single.mealType, MealType.dinner);
    });

    testWidgets('推定中はローディングを出し、二重に送信できない', (tester) async {
      final estimator = FakeEstimator()..pending = Completer();
      final env = await setUpEnv(estimator: estimator);
      await pumpToday(tester, env);

      await submit(tester, '牛丼', settle: false);

      expect(find.byTooltip('AIでPFCを推定'), findsNothing);
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(estimator.calls, hasLength(1));

      estimator.pending!.complete(sampleEstimate);
      await tester.pumpAndSettle();
      expect(find.text('AIの推定結果'), findsOneWidget);
    });

    testWidgets('推定に失敗したら理由を表示し、書いた文章は残す', (tester) async {
      final env = await setUpEnv(
        estimator: FakeEstimator(
          error: const NutritionEstimateException(kEstimateDailyLimitMessage),
        ),
      );
      await pumpToday(tester, env);

      await submit(tester, '牛丼');

      expect(find.text(kEstimateDailyLimitMessage), findsOneWidget);
      expect(find.text('牛丼'), findsOneWidget, reason: '入力は残して、言い直せるようにする');
      expect(await env.savedEntries(), isEmpty);
    });

    testWidgets('想定外の例外でも、ローディングのまま固まらない', (tester) async {
      final env = await setUpEnv(
        estimator: FakeEstimator(error: StateError('?')),
      );
      await pumpToday(tester, env);

      await submit(tester, '牛丼');

      expect(find.text(kEstimateFailedMessage), findsOneWidget);
      expect(find.byTooltip('AIでPFCを推定'), findsOneWidget);
    });

    testWidgets('食べ物が見つからなければ記録せず、AIの説明を表示する', (tester) async {
      final env = await setUpEnv(
        estimator: FakeEstimator(
          result: const NutritionEstimate(items: [], note: '食べ物の説明が見つかりませんでした'),
        ),
      );
      await pumpToday(tester, env);

      await submit(tester, 'こんにちは');

      expect(find.text('食べ物の説明が見つかりませんでした'), findsOneWidget);
      expect(find.text('AIの推定結果'), findsNothing);
    });

    testWidgets('結果をキャンセルしたら記録せず、文章を残す', (tester) async {
      final env = await setUpEnv(
        estimator: FakeEstimator(result: sampleEstimate),
      );
      await pumpToday(tester, env);

      await submit(tester, '牛丼並盛と味噌汁');
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();

      expect(await env.savedEntries(), isEmpty);
      expect(find.text('牛丼並盛と味噌汁'), findsOneWidget);
    });

    testWidgets('入力が空なら送信ボタンを押せない', (tester) async {
      final env = await setUpEnv();
      await pumpToday(tester, env);

      final button = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.auto_awesome),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('写真を添えて推定できる（文章なしでも送れる）', (tester) async {
      final estimator = FakeEstimator(result: sampleEstimate);
      final picker = FakePhotoPicker(
        image: EstimateImage(
          bytes: Uint8List.fromList(tinyPng),
          mimeType: 'image/png',
        ),
      );
      final env = await setUpEnv(estimator: estimator, photoPicker: picker);
      await pumpToday(tester, env);

      await tester.tap(find.byTooltip('写真から推定'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('アルバムから選ぶ'));
      await tester.pumpAndSettle();

      expect(picker.sources, [PhotoSource.gallery]);
      expect(find.text('写真を添えて推定します'), findsOneWidget);

      await tester.tap(find.byTooltip('AIでPFCを推定'));
      await tester.pumpAndSettle();

      expect(estimator.calls.single.image?.mimeType, 'image/png');
      expect(find.text('AIの推定結果'), findsOneWidget);
    });
  });

  group('日付の切り替え', () {
    testWidgets('前の日へ移動すると、その日の記録を出す。「今日へ」で戻れる', (tester) async {
      final env = await setUpEnv();
      await env.seedEntry(entry('a', name: '今日の牛丼'));
      await env.seedEntry(entry('b', dateKey: '2026-10-20', name: '昨日のカレー'));
      await pumpToday(tester, env);

      expect(find.text('今日 10月21日(水)'), findsOneWidget);
      expect(find.text('今日へ'), findsNothing);

      await tester.tap(find.byTooltip('前の日'));
      await tester.pumpAndSettle();

      expect(find.text('昨日 10月20日(火)'), findsOneWidget);
      expect(find.text('昨日のカレー'), findsOneWidget);
      expect(find.text('今日の牛丼'), findsNothing);

      await tester.tap(find.text('今日へ'));
      await tester.pumpAndSettle();
      expect(find.text('今日の牛丼'), findsOneWidget);
    });

    testWidgets('昨日を表示中にAIで追加すると、昨日の記録になる', (tester) async {
      final env = await setUpEnv(
        estimator: FakeEstimator(result: sampleEstimate),
      );
      await pumpToday(tester, env);

      await tester.tap(find.byTooltip('前の日'));
      await tester.pumpAndSettle();
      await submit(tester, '牛丼並盛と味噌汁');
      expect(find.text('昨日 10月20日(火)の記録に追加します'), findsOneWidget);
      await tester.tap(find.text('2品を追加'));
      await tester.pumpAndSettle();

      final saved = await env.savedEntries();
      expect(saved.every((e) => e.dateKey == '2026-10-20'), isTrue);
    });
  });

  testWidgets('スワイプで削除し、「元に戻す」で戻せる', (tester) async {
    final env = await setUpEnv();
    await env.seedEntry(entry('a', name: '牛丼', kcal: 650));
    await pumpToday(tester, env);

    await tester.drag(find.text('牛丼'), const Offset(-600, 0));
    await tester.pumpAndSettle();

    expect(find.text('「牛丼」を削除しました'), findsOneWidget);
    expect(await env.savedEntries(), isEmpty);

    await tester.tap(find.text('元に戻す'));
    await tester.pumpAndSettle();

    expect((await env.savedEntries()).single.id, 'a');
    expect(find.text('牛丼'), findsOneWidget);
  });

  testWidgets('記録をタップすると編集画面が開く', (tester) async {
    final env = await setUpEnv();
    await env.seedEntry(entry('a', name: '牛丼'));
    await pumpToday(tester, env);

    await tester.tap(find.text('牛丼'));
    await tester.pumpAndSettle();

    expect(find.byType(EntryFormScreen), findsOneWidget);
    expect(find.text('記録を編集'), findsOneWidget);
  });

  testWidgets('食事区分の＋から、その区分への追加シートが開く', (tester) async {
    final env = await setUpEnv();
    await pumpToday(tester, env);

    // スマートフォンの大きさでは夕食のカードは画面の下のほうにある
    await tester.ensureVisible(find.byTooltip('夕食に追加'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('夕食に追加'));
    await tester.pumpAndSettle();

    expect(find.text('夕食に追加'), findsOneWidget);
    expect(find.text('お気に入り'), findsOneWidget);
  });

  testWidgets('大きな文字サイズでもレイアウトが崩れない', (tester) async {
    final env = await setUpEnv();
    await env.seedEntry(
      entry('a', name: 'とても長い名前のコンビニのサラダチキンとブロッコリーのサラダ', amount: '1パック（約200g）'),
    );
    await pumpApp(
      tester,
      env,
      const TodayScreen(profile: sampleProfile),
      textScale: 1.3,
    );

    expect(tester.takeException(), isNull);
  });
}
