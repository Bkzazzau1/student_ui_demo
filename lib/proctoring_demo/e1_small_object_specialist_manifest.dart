import 'dart:convert';

import 'package:flutter/services.dart';

import 'e1_object_taxonomy.dart';

class E1SmallObjectSpecialistManifest {
  const E1SmallObjectSpecialistManifest({
    required this.schemaVersion,
    required this.installed,
    required this.requiredCanonicalClasses,
    this.modelId,
    this.modelVersion,
    this.modelPath,
    this.precision = 'int8',
    this.backend = 'onnxRuntimeDirectML',
    this.inputWidth = 416,
    this.inputHeight = 416,
    this.confidenceThreshold = 0.45,
    this.iouThreshold = 0.45,
    this.classNames = const <String>[],
  });

  static const String defaultAssetPath =
      'assets/models/e1_small_object_specialist/manifest.json';
  static const String supportedSchemaVersion = '1.0';

  final String schemaVersion;
  final bool installed;
  final Set<String> requiredCanonicalClasses;
  final String? modelId;
  final String? modelVersion;
  final String? modelPath;
  final String precision;
  final String backend;
  final int inputWidth;
  final int inputHeight;
  final double confidenceThreshold;
  final double iouThreshold;
  final List<String> classNames;

  bool get isValid {
    if (schemaVersion != supportedSchemaVersion) return false;
    if (requiredCanonicalClasses.isEmpty) return false;
    if (!requiredCanonicalClasses.every(
      E1ObjectTaxonomyV1.specialistCanonicalIds.contains,
    )) {
      return false;
    }
    if (!installed) return true;

    if (modelId?.trim().isEmpty ?? true) return false;
    if (modelVersion?.trim().isEmpty ?? true) return false;
    if (modelPath?.trim().isEmpty ?? true) return false;
    if (inputWidth <= 0 || inputHeight <= 0) return false;
    if (!confidenceThreshold.isFinite ||
        confidenceThreshold < 0.0 ||
        confidenceThreshold > 1.0) {
      return false;
    }
    if (!iouThreshold.isFinite || iouThreshold < 0.0 || iouThreshold > 1.0) {
      return false;
    }
    if (classNames.isEmpty) return false;
    if (!classNames.every(E1ObjectTaxonomyV1.specialistCanonicalIds.contains)) {
      return false;
    }
    return classNames.toSet().containsAll(requiredCanonicalClasses);
  }

  bool get runtimeAvailable => installed && isValid;

  Map<String, Object?> toNativePolicy() {
    if (!runtimeAvailable) return const <String, Object?>{};
    return <String, Object?>{
      'backend': backend,
      'precision': precision,
      'model_path': modelPath,
      'model_id': modelId,
      'model_version': modelVersion,
      'class_names': classNames,
      'max_input_width': inputWidth,
      'max_input_height': inputHeight,
      'confidence_threshold': confidenceThreshold,
      'iou_threshold': iouThreshold,
    };
  }

  factory E1SmallObjectSpecialistManifest.fromJson(Map<String, Object?> json) {
    final required = _readStrings(json['required_canonical_classes']).toSet();
    final classes = _readStrings(json['class_names']);
    return E1SmallObjectSpecialistManifest(
      schemaVersion: '${json['manifest_schema_version'] ?? ''}'.trim(),
      installed: json['installed'] == true,
      requiredCanonicalClasses: required,
      modelId: _nullableString(json['model_id']),
      modelVersion: _nullableString(json['model_version']),
      modelPath: _nullableString(json['model_path']),
      precision: _nullableString(json['precision']) ?? 'int8',
      backend: _nullableString(json['backend']) ?? 'onnxRuntimeDirectML',
      inputWidth: _readInt(json['input_width']) ?? 416,
      inputHeight: _readInt(json['input_height']) ?? 416,
      confidenceThreshold: _readDouble(json['confidence_threshold']) ?? 0.45,
      iouThreshold: _readDouble(json['iou_threshold']) ?? 0.45,
      classNames: classes,
    );
  }

  static Future<E1SmallObjectSpecialistManifest?> load({
    String assetPath = defaultAssetPath,
  }) async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final manifest = E1SmallObjectSpecialistManifest.fromJson(
        Map<String, Object?>.from(decoded),
      );
      return manifest.isValid ? manifest : null;
    } catch (_) {
      return null;
    }
  }

  static List<String> _readStrings(Object? value) {
    if (value is! Iterable) return const <String>[];
    return value
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static String? _nullableString(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '');
  }

  static double? _readDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}
