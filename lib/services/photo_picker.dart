import 'package:image_picker/image_picker.dart';

import 'nutrition_estimator.dart';

enum PhotoSource { camera, gallery }

/// 食事の写真を選ぶ。画面のテストでは差し替える（端末のカメラを起動しないように）。
abstract class FoodPhotoPicker {
  /// 選んだ写真。キャンセルされたらnull。
  Future<EstimateImage?> pick(PhotoSource source);
}

class DeviceFoodPhotoPicker implements FoodPhotoPicker {
  DeviceFoodPhotoPicker({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<EstimateImage?> pick(PhotoSource source) async {
    final file = await _picker.pickImage(
      source: switch (source) {
        PhotoSource.camera => ImageSource.camera,
        PhotoSource.gallery => ImageSource.gallery,
      },
      // 端末側で縮小してから送る（通信量と推定時間を抑える）
      maxWidth: kEstimatePhotoMaxDimension,
      maxHeight: kEstimatePhotoMaxDimension,
      imageQuality: 80,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return EstimateImage(
      bytes: bytes,
      mimeType: file.mimeType ?? mimeTypeForFileName(file.name),
    );
  }
}

/// ファイル名の拡張子から画像の種類を推測する（Androidでは mimeType が
/// 取れないことがあるため）。分からなければJPEG扱い。
String mimeTypeForFileName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.heic')) return 'image/heic';
  if (lower.endsWith('.heif')) return 'image/heif';
  return 'image/jpeg';
}
