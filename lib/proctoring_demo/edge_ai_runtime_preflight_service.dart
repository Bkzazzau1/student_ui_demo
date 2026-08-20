import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import '../face_demo/native_face_embedding_runtime.dart';
import '../rust/frb_generated.dart';
import 'native_face_landmarker_runtime.dart';
import 'python_edge_ai_service.dart';
import 'yolo_runtime_health_check.dart';

class EdgeAiComponentStatus {
  const EdgeAiComponentStatus({
    required this.name,
    required this.ready,
    required this.detail,
  });

  final String name;
  final bool ready;
  final String detail;
}

class EdgeAiRuntimePreflightResult {
  const EdgeAiRuntimePreflightResult({
    required this.components,
    required this.checkedAt,
  });

  final List<EdgeAiComponentStatus> components;
  final DateTime checkedAt;

  bool get ready =>
      components.isNotEmpty && components.every((item) => item.ready);
  List<String> get blockingReasons => components
      .where((item) => !item.ready)
      .map((item) => '${item.name}: ${item.detail}')
      .toList(growable: false);
}

typedef EdgeAiPreflightRunner = Future<EdgeAiRuntimePreflightResult> Function();

class EdgeAiRuntimePreflightService {
  EdgeAiRuntimePreflightService({
    NativeFaceLandmarkerRuntime? landmarker,
    NativeFaceEmbeddingRuntime? embedding,
    YoloRuntimeHealthCheck? yolo,
  }) : _landmarker = landmarker ?? NativeFaceLandmarkerRuntime(),
       _embedding = embedding ?? NativeFaceEmbeddingRuntime(),
       _yolo = yolo ?? YoloRuntimeHealthCheck();

  final NativeFaceLandmarkerRuntime _landmarker;
  final NativeFaceEmbeddingRuntime _embedding;
  final YoloRuntimeHealthCheck _yolo;

  static const Map<String, String> _criticalAssets = <String, String>{
    'assets/models/face_landmarker_windows/face_landmarks.onnx':
        '404c737f67469726a4b9cddcd5a3f2d05aab65c73e63496c823f53c60de8e269',
    NativeFaceEmbeddingRuntime.modelAssetPath:
        NativeFaceEmbeddingRuntime.modelSha256,
    'assets/models/yolo_exam_review/yolo_exam_review.int8.onnx':
        '61e0858902aca5b96ec9c37384817ffaada40246900021a129830e791be20b70',
  };

  Future<EdgeAiRuntimePreflightResult> run() async {
    final components = <EdgeAiComponentStatus>[];
    components.add(await _checkAssets());
    components.add(await _checkRust());
    if (Platform.isWindows) {
      components.add(await _checkLandmarker());
      components.add(await _checkEmbedding());
      components.add(await _checkYolo());
      components.add(await _checkPython());
    } else {
      components.add(
        const EdgeAiComponentStatus(
          name: 'Windows edge runtime',
          ready: false,
          detail: 'Strict supervised exams currently require Windows.',
        ),
      );
    }
    return EdgeAiRuntimePreflightResult(
      components: List.unmodifiable(components),
      checkedAt: DateTime.now().toUtc(),
    );
  }

  Future<EdgeAiComponentStatus> _checkAssets() async {
    try {
      for (final entry in _criticalAssets.entries) {
        final data = await rootBundle.load(entry.key);
        final actual = sha256.convert(data.buffer.asUint8List()).toString();
        if (actual != entry.value) {
          return EdgeAiComponentStatus(
            name: 'AI model integrity',
            ready: false,
            detail: 'Checksum mismatch for ${entry.key}.',
          );
        }
      }
      return const EdgeAiComponentStatus(
        name: 'AI model integrity',
        ready: true,
        detail: 'Critical ONNX model checksums are valid.',
      );
    } catch (error) {
      return EdgeAiComponentStatus(
        name: 'AI model integrity',
        ready: false,
        detail: error.toString(),
      );
    }
  }

  Future<EdgeAiComponentStatus> _checkRust() async {
    try {
      await BrainCoreApi.init();
      return const EdgeAiComponentStatus(
        name: 'Rust security core',
        ready: true,
        detail: 'Native policy and encrypted evidence core loaded.',
      );
    } catch (error) {
      return EdgeAiComponentStatus(
        name: 'Rust security core',
        ready: false,
        detail: error.toString(),
      );
    }
  }

  Future<EdgeAiComponentStatus> _checkLandmarker() async {
    final ready = await _landmarker.initialize();
    return EdgeAiComponentStatus(
      name: 'Face and iris landmarks',
      ready: ready,
      detail: ready
          ? '478-point ONNX runtime loaded.'
          : 'Landmark runtime failed to initialize.',
    );
  }

  Future<EdgeAiComponentStatus> _checkEmbedding() async {
    try {
      final initialized = await _embedding.initialize();
      final health = await _embedding.health();
      final ready = initialized && health['ready'] == true;
      return EdgeAiComponentStatus(
        name: 'Face embedding',
        ready: ready,
        detail: ready
            ? 'SFace ONNX runtime loaded.'
            : (health['error']?.toString() ?? 'Embedding runtime failed.'),
      );
    } catch (error) {
      return EdgeAiComponentStatus(
        name: 'Face embedding',
        ready: false,
        detail: error.toString(),
      );
    }
  }

  Future<EdgeAiComponentStatus> _checkYolo() async {
    final health = await _yolo.check();
    return EdgeAiComponentStatus(
      name: 'Object intelligence',
      ready: health.ready,
      detail: health.message,
    );
  }

  Future<EdgeAiComponentStatus> _checkPython() async {
    final service = PythonEdgeAiService(workingDirectory: _workingDirectory());
    try {
      await service.start();
      return const EdgeAiComponentStatus(
        name: 'Python temporal AI',
        ready: true,
        detail: 'Local normalized-signal fusion runtime is responsive.',
      );
    } catch (error) {
      return EdgeAiComponentStatus(
        name: 'Python temporal AI',
        ready: false,
        detail: error.toString(),
      );
    } finally {
      await service.dispose();
    }
  }

  String _workingDirectory() {
    final candidates = <Directory>[Directory.current];
    var directory = File(Platform.resolvedExecutable).parent;
    for (var depth = 0; depth < 7; depth++) {
      candidates.add(directory);
      directory = directory.parent;
    }
    for (final candidate in candidates) {
      if (Directory(
        '${candidate.path}${Platform.pathSeparator}ai_runtime',
      ).existsSync()) {
        return candidate.path;
      }
    }
    return Directory.current.path;
  }
}
