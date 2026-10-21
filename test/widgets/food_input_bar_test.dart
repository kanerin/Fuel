import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/services/nutrition_estimator.dart';
import 'package:fuel/widgets/food_input_bar.dart';

import '../helpers/fake_services.dart';
import '../helpers/pump.dart';

void main() {
  setUpAll(setUpScreenTests);

  final photo = EstimateImage(
    bytes: Uint8List.fromList(tinyPng),
    mimeType: 'image/png',
  );

  Future<({TextEditingController controller, List<String> calls})> pumpBar(
    WidgetTester tester, {
    EstimateImage? image,
    bool busy = false,
  }) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final calls = <String>[];
    await pumpApp(
      tester,
      TestEnv(),
      Scaffold(
        bottomNavigationBar: FoodInputBar(
          controller: controller,
          image: image,
          busy: busy,
          onSubmit: () => calls.add('submit'),
          onPickPhoto: () => calls.add('photo'),
          onRemovePhoto: () => calls.add('remove'),
        ),
      ),
    );
    return (controller: controller, calls: calls);
  }

  IconButton sendButton(WidgetTester tester) => tester.widget<IconButton>(
    find.ancestor(
      of: find.byIcon(Icons.auto_awesome),
      matching: find.byType(IconButton),
    ),
  );

  testWidgets('文章も写真も無ければ送信できず、書くと送信できる', (tester) async {
    final bar = await pumpBar(tester);
    expect(sendButton(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField), '  ');
    await tester.pump();
    expect(sendButton(tester).onPressed, isNull, reason: '空白だけでは送れない');

    await tester.enterText(find.byType(TextField), '牛丼');
    await tester.pump();
    await tester.tap(find.byTooltip('AIでPFCを推定'));
    expect(bar.calls, ['submit']);
  });

  testWidgets('キーボードの送信キーでも送れる', (tester) async {
    final bar = await pumpBar(tester);

    await tester.enterText(find.byType(TextField), '牛丼');
    await tester.testTextInput.receiveAction(TextInputAction.send);

    expect(bar.calls, ['submit']);
  });

  testWidgets('写真があれば文章なしでも送信でき、写真を外せる', (tester) async {
    final bar = await pumpBar(tester, image: photo);

    expect(find.text('写真を添えて推定します'), findsOneWidget);
    expect(sendButton(tester).onPressed, isNotNull);

    await tester.tap(find.byTooltip('写真を外す'));
    expect(bar.calls, ['remove']);
  });

  testWidgets('推定中は入力・送信・写真の追加を止め、ローディングを出す', (tester) async {
    await pumpBar(tester, image: photo, busy: true);

    expect(find.byIcon(Icons.auto_awesome), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    final camera = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.photo_camera_outlined),
        matching: find.byType(IconButton),
      ),
    );
    expect(camera.onPressed, isNull);
  });

  testWidgets('文章は上限の文字数で打ち止めにする', (tester) async {
    final bar = await pumpBar(tester);

    await tester.enterText(
      find.byType(TextField),
      'あ' * (kMaxEstimateTextLength + 20),
    );

    expect(bar.controller.text.length, kMaxEstimateTextLength);
  });
}
