import 'dart:convert';

import 'package:flutter/services.dart';

import 'optimized_vision_runtime_policy.dart';

class YoloExamReviewManifest {
  const YoloExamReviewManifest({
    required this.modelName,
    required this.modelFamily,
    required this.modelPathInt8,
    required this.modelPathFp16,
    required this.modelPathFp32,
    required this.inputWidth,
    required this.inputHeight,
    required this.inputChannels,
    required this.outputLayout,
    required this.confidenceThreshold,
    required this.iouThreshold,
    required this.targetFps,
    required this.classNames,
  });

  static const String defaultAssetPath =
      'assets/models/yolo_exam_review/manifest.json';

  final String modelName;
  final String modelFamily;
  final String modelPathInt8;
  final String modelPathFp16;
  final String modelPathFp32;
  final int inputWidth;
  final int inputHeight;
  final int inputChannels;
  final String outputLayout;
  final double confidenceThreshold;
  final double iouThreshold;
  final int targetFps;
  final List<String> classNames;

  factory YoloExamReviewManifest.fromJson(Map<String, Object?> json) {
    return YoloExamReviewManifest(
      modelName: json['model_name']?.toString() ?? 'K-SLAS Exam Review YOLO',
      modelFamily: json['model_family']?.toString() ?? 'yolo',
      modelPathInt8: json['model_path_int8']?.toString() ?? '',
      modelPathFp16: json['model_path_fp16']?.toString() ?? '',
      modelPathFp32: json['model_path_fp32']?.toString() ?? '',
      inputWidth: _int(json['input_width'], 416),
      inputHeight: _int(json['input_height'], 416),
      inputChannels: _int(json['input_channels'], 3),
      outputLayout: json['output_layout']?.toString() ?? 'channels_first_yolov8',
      confidenceThreshold: _double(json['confidence_threshold'], 0.45),
      iouThreshold: _double(json['iou_threshold'], 0.45),
      targetFps: _int(json['target_fps'], 1),
      classNames: _stringList(json['class_names']),
    );
  }

  static Future<YoloExamReviewManifest?> load({
    String assetPath = defaultAssetPath,
  }) async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      final decoded = jsonDecode(raw) as Map;
      final manifest = YoloExamReviewManifest.fromJson(
        Map<String, Object?>.from(decoded),
      );
      if (!manifest.isUsable) return null;
      return manifest;
    } catch (_) {
      return null;
    }
  }

  bool get isUsable =>
      modelFamily.trim().toLowerCase() == 'yolo' &&
      selectedModelPath(const OptimizedVisionRuntimePolicy(
        backend: VisionRuntimeBackend.onnxRuntimeCpu,
        precision: VisionModelPrecision.int8,
        targetUtilization: 0.15,
        maxInputWidth: 416,
        maxInputHeight: 416,
        targetFps: 1,
        batchSize: 1,
      )).trim().isNotEmpty &&
      inputWidth > 0 &&
      inputHeight > 0 &&
      inputChannels > 0 &&
      classNames.isNotEmpty;

  String selectedModelPath(OptimizedVisionRuntimePolicy policy) {
    switch (policy.precision) {
      case VisionModelPrecision.int8:
        return modelPathInt8.isNotEmpty ? modelPathInt8 : modelPathFp32;
      case VisionModelPrecision.fp16:
        return modelPathFp16.isNotEmpty ? modelPathFp16 : modelPathFp32;
      case VisionModelPrecision.fp32Fallback:
        return modelPathFp32.isNotEmpty ? modelPathFp32 : modelPathInt8;
    }
  }

  Map<String, Object?> toPolicyJson(OptimizedVisionRuntimePolicy policy) {
    return <String, Object?>{
      'model_family': modelFamily,
      'model_name': modelName,
      'model_path': selectedModelPath(policy),
      'onnx_path': selectedModelPath(policy),
      'input_width': inputWidth,
      'input_height': inputHeight,
      'input_channels': inputChannels,
      'max_input_width': inputWidth,
      'max_input_height': inputHeight,
      'output_layout': outputLayout,
      'confidence_threshold': confidenceThreshold,
      'iou_threshold': iouThreshold,
      'target_fps': targetFps,
      'num_classes': classNames.length,
      'class_names': classNames,
      'requires_real_model': true,
    };
  }
}

int _int(Object? value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

double _double(Object? value, double fallback) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

List<String> _stringList(Object? value) {
  if (value is! Iterable) return const <String>[];
  return value
      .map((item) => item?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
