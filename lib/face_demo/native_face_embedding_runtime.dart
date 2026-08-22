import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

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
  static const String preprocessingVersion =
      'sface-five-point-similarity-bgr-minus-127.5-div-128-v1';

  /// Platforms with a real native SFace + protected-storage implementation.
  /// iOS/macOS scaffolding exists in source but is unverified (no Xcode/Mac
  /// available to build or test it), so it is deliberately not enabled here
  /// yet: enabling it before it is verified would risk a native channel
  /// call throwing instead of failing safely, exactly the "AI unavailable"
  /// path this runtime otherwise handles cleanly.
  static bool get _supportedPlatform => Platform.isWindows || Platform.isAndroid;

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

  Future<bool> storeProtectedTemplate({
    required String studentId,
    required String templateJson,
  }) async {
    if (!_supportedPlatform || templateJson.isEmpty) return false;
    final directory = await _identityDirectory();
    if (directory == null) return false;
    await directory.create(recursive: true);
    final identityKey = sha256.convert(studentId.codeUnits).toString();
    final path = '${directory.path}${Platform.pathSeparator}$identityKey.dpapi';
    return await _channel
            .invokeMethod<bool>('storeProtectedTemplate', <String, Object?>{
              'path': path,
              'template_json': templateJson,
              'entropy': '$modelId:$modelSha256:$studentId',
            }) ??
        false;
  }

  Future<String?> loadProtectedTemplate({required String studentId}) async {
    if (!_supportedPlatform) return null;
    final directory = await _identityDirectory();
    if (directory == null) return null;
    final identityKey = sha256.convert(studentId.codeUnits).toString();
    final path = '${directory.path}${Platform.pathSeparator}$identityKey.dpapi';
    return _channel.invokeMethod<String>(
      'loadProtectedTemplate',
      <String, Object?>{
        'path': path,
        'entropy': '$modelId:$modelSha256:$studentId',
      },
    );
  }

  Future<bool> clearProtectedTemplate({required String studentId}) async {
    if (!_supportedPlatform) return false;
    final directory = await _identityDirectory();
    if (directory == null) return false;
    final identityKey = sha256.convert(studentId.codeUnits).toString();
    final file = File(
      '${directory.path}${Platform.pathSeparator}$identityKey.dpapi',
    );
    if (!await file.exists()) return true;
    await file.delete();
    return !await file.exists();
  }

  /// Resolves the per-platform private directory the protected template
  /// lives in. Windows keeps its existing `%LOCALAPPDATA%\KSLAS\identity`
  /// path unchanged; Android uses the app's private, sandboxed support
  /// directory (nothing else on the device can read this without root).
  Future<Directory?> _identityDirectory() async {
    if (Platform.isWindows) {
      final root = Platform.environment['LOCALAPPDATA'];
      if (root == null || root.isEmpty) return null;
      return Directory(
        '$root${Platform.pathSeparator}KSLAS${Platform.pathSeparator}identity',
      );
    }
    if (Platform.isAndroid) {
      final support = await getApplicationSupportDirectory();
      return Directory(
        '${support.path}${Platform.pathSeparator}identity',
      );
    }
    return null;
  }
}
