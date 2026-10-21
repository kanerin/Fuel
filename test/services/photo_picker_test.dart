import 'package:flutter_test/flutter_test.dart';
import 'package:fuel/services/photo_picker.dart';

void main() {
  test('mimeTypeForFileName: 拡張子から画像の種類を推測する（大文字も可）', () {
    expect(mimeTypeForFileName('IMG_0001.PNG'), 'image/png');
    expect(mimeTypeForFileName('food.webp'), 'image/webp');
    expect(mimeTypeForFileName('photo.heic'), 'image/heic');
    expect(mimeTypeForFileName('photo.heif'), 'image/heif');
  });

  test('mimeTypeForFileName: 分からなければJPEG扱い', () {
    expect(mimeTypeForFileName('photo.jpg'), 'image/jpeg');
    expect(mimeTypeForFileName('photo'), 'image/jpeg');
  });
}
