import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/services/favorite_repository.dart';

import '../helpers/fake_services.dart';
import '../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late FavoriteRepository repo;

  setUp(() {
    env = TestEnv();
    repo = env.services.favorites;
  });

  test('登録したものが新しい順に出る', () async {
    env.now = DateTime(2026, 10, 20);
    await repo.addFavorite(food('プロテイン', amount: '1杯', kcal: 120, p: 24));
    env.now = DateTime(2026, 10, 21);
    await repo.addFavorite(food('ゆで卵', amount: '1個', kcal: 76, p: 6.3));

    final favorites = await repo.watchFavorites().first;
    expect(favorites.map((f) => f.food.name), ['ゆで卵', 'プロテイン']);
    expect(favorites.last.food.nutrition.protein, 24);
  });

  test('同じ名前・量のものを2回登録しても1件のまま（上書き）', () async {
    await repo.addFavorite(food('プロテイン', amount: '1杯', kcal: 120));
    await repo.addFavorite(food(' プロテイン', amount: '1杯 ', kcal: 110));

    final favorites = await repo.watchFavorites().first;
    expect(favorites, hasLength(1));
    expect(favorites.single.food.nutrition.calories, 110);
  });

  test('量が違えば別のお気に入り', () async {
    await repo.addFavorite(food('ご飯', amount: '普通盛り', kcal: 234));
    await repo.addFavorite(food('ご飯', amount: '大盛り', kcal: 350));

    expect(await repo.watchFavorites().first, hasLength(2));
  });

  test('削除できる', () async {
    await repo.addFavorite(food('プロテイン', amount: '1杯', kcal: 120));
    final id = (await repo.watchFavorites().first).single.id;

    await repo.deleteFavorite(id);

    expect(await repo.watchFavorites().first, isEmpty);
  });

  test('favoriteIdFor はドキュメントIDに使える文字だけで、名前と量で決まる', () {
    final id = favoriteIdFor(food('鶏むね肉/皮なし', amount: '100g'));

    expect(id, isNot(contains('/')));
    expect(id, favoriteIdFor(food(' 鶏むね肉/皮なし ', amount: '100g')));
    expect(id, isNot(favoriteIdFor(food('鶏むね肉/皮なし', amount: '200g'))));
  });
}
