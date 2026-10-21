import 'package:flutter/material.dart';

import '../models/food_item.dart';
import '../widgets/food_form.dart';

/// 食べ物1品の値を直して返す画面（保存はしない）。
///
/// AIの推定値を記録する前に直すときと、お気に入りを手入力で登録するときに使う。
class FoodEditScreen extends StatefulWidget {
  const FoodEditScreen({super.key, this.initial, this.title = '値を直す'});

  final FoodItem? initial;
  final String title;

  @override
  State<FoodEditScreen> createState() => _FoodEditScreenState();
}

class _FoodEditScreenState extends State<FoodEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _form = FoodFormController(widget.initial);

  @override
  void dispose() {
    _form.dispose();
    super.dispose();
  }

  void _done() {
    if (!_formKey.currentState!.validate()) return;
    final food = _form.tryBuild();
    if (food == null || validateFoodItem(food) != null) return;
    Navigator.of(context).pop(food);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Form(
        key: _formKey,
        // ListViewだと画面外の入力欄が作られず、Formの検証から漏れる（エラーが出ない）ため、
        // 入力欄はすべて常に作っておく
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FoodFormFields(controller: _form),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _done,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('この内容にする'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
