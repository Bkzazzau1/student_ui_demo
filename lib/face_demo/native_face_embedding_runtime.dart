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
  static const String preprocessingVersion =
      'sface-five-point-similarity-bgr-minus-127.5-div-128-v1';

  Future<bool> initialize() async {
    if (!Platform.isWindows) return false;
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
    if (!Platform.isWindows || templateJson.isEmpty) return false;
    final root = Platform.environment['LOCALAPPDATA'];
    if (root == null || root.isEmpty) return false;
    final directory = Directory(
      '$root${Platform.pathSeparator}KSLAS${Platform.pathSeparator}identity',
    );
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
    if (!Platform.isWindows) return null;
    final root = Platform.environment['LOCALAPPDATA'];
    if (root == null || root.isEmpty) return null;
    final identityKey = sha256.convert(studentId.codeUnits).toString();
    final path =
        '$root${Platform.pathSeparator}KSLAS${Platform.pathSeparator}'
        'identity${Platform.pathSeparator}$identityKey.dpapi';
    return _channel.invokeMethod<String>(
      'loadProtectedTemplate',
      <String, Object?>{
        'path': path,
        'entropy': '$modelId:$modelSha256:$studentId',
      },
    );
  }
}
