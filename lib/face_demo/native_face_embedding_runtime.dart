import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

class FaceEmbeddingSample {
  const FaceEmbeddingSample({
    required this.modelId,
    required this.embedding,
    required this.productionEnforcement,
  });

  final String modelId;
  final List<double> embedding;
  final bool productionEnforcement;
}

class NativeFaceEmbeddingRuntime {
  static const MethodChannel _channel = MethodChannel('kslas.face_embedding');
  static const String modelId = 'kslas-sface-2021dec-v1';
  static const String modelAssetPath =
      'assets/models/face_embedding_sface/face_recognition_sface_2021dec.onnx';
  static const String modelSha256 =
      '0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79';

  /// Describes exactly how a face is turned into the 112x112 model input.
  /// Official templates record this value and are only matched against
  /// probes produced the same way, so it must change whenever alignment or
  /// pixel normalization changes.
  static const String preprocessingVersion = 'sface-5pt-ls-bilinear-rgb255-v2';

  /// Platforms with a native SFace + protected-storage implementation:
  /// Windows (C++), Android (Kotlin) and iOS/iPadOS (Swift, checked on the
  /// iOS simulator in CI by `integration_test/native_runtime_parity_test.dart`).
  static bool get _supportedPlatform =>
      Platform.isWindows || Platform.isAndroid || Platform.isIOS;

  Future<bool> initialize() async {
    if (!_supportedPlatform) return false;
    final model = await rootBundle.load(modelAssetPath);
    final bytes = model.buffer.asUint8List();
    if (sha256.convert(bytes).toString() != modelSha256) {
      throw StateError('Face embedding model integrity check failed');
    }
    final directory = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}kslas_face_embedding',
    );
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}face_embedding.onnx',
    );
    await file.writeAsBytes(bytes, flush: true);
    return await _channel.invokeMethod<bool>('initialize', <String, Object?>{
          'model_path': file.path,
        }) ??
        false;
  }

  Future<Map<String, Object?>> health() async {
    final value = await _channel.invokeMapMethod<String, Object?>('health');
    return value ?? const <String, Object?>{'ready': false};
  }

  Future<FaceEmbeddingSample?> embedAlignedRgb(Uint8List rgbBytes) async {
    if (rgbBytes.length != 112 * 112 * 3) {
      throw ArgumentError.value(
        rgbBytes.length,
        'rgbBytes',
        'Expected an aligned 112x112 RGB image',
      );
    }
    final value = await _channel.invokeMapMethod<String, Object?>(
      'embedAlignedRgb',
      <String, Object?>{'rgb_bytes': rgbBytes},
    );
    if (value == null || value['embedding'] is! List) return null;
    return FaceEmbeddingSample(
      modelId: value['model_id']?.toString() ?? '',
      embedding: (value['embedding']! as List)
          .map((element) => (element as num).toDouble())
          .toList(growable: false),
      productionEnforcement: value['production_enforcement'] == true,
    );
  }

  /// Encrypts [value] to [path] with the platform's protected storage
  /// (Windows DPAPI, Android Keystore AES-GCM, iOS Keychain-held AES-GCM key).
  /// [entropy] binds the value to
  /// its purpose and location; the same entropy is needed to read it back.
  Future<bool> storeProtectedString({
    required String path,
    required String value,
    required String entropy,
  }) async {
    if (!_supportedPlatform || value.isEmpty || entropy.isEmpty) return false;
    return await _channel.invokeMethod<bool>(
          'storeProtectedTemplate',
          <String, Object?>{
            'path': path,
            'template_json': value,
            'entropy': entropy,
          },
        ) ??
        false;
  }

  Future<String?> loadProtectedString({
    required String path,
    required String entropy,
  }) async {
    if (!_supportedPlatform || entropy.isEmpty) return null;
    return _channel.invokeMethod<String>(
      'loadProtectedTemplate',
      <String, Object?>{'path': path, 'entropy': entropy},
    );
  }
}
