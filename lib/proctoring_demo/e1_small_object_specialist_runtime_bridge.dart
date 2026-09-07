import 'package:flutter/services.dart';

import 'e1_small_object_specialist.dart';
import 'e1_small_object_specialist_manifest.dart';
import 'e1_small_object_specialist_runtime.dart';
import 'e1_specialist_frame.dart';
import 'monotonic_timebase.dart';

typedef E1SpecialistManifestLoader =
    Future<E1SmallObjectSpecialistManifest?> Function();
typedef E1SpecialistModelAssetChecker = Future<bool> Function(String modelPath);

Future<bool> _defaultModelAssetChecker(String modelPath) async {
  try {
    final data = await rootBundle.load(modelPath);
    return data.lengthInBytes > 0;
  } catch (_) {
    return false;
  }
}

/// Dedicated local/native runtime for the E1 small-object specialist.
///
/// The specialist uses a separate method channel/native ONNX session from the
/// base E1 YOLO detector, so loading a future specialist model cannot replace
/// or mutate the base detector session. Missing/uninstalled specialist assets
/// are represented as unavailable and therefore emit zero observations.
class E1SmallObjectSpecialistRuntimeBridge
    implements E1SmallObjectSpecialistRuntime {
  E1SmallObjectSpecialistRuntimeBridge({
    MethodChannel? channel,
    E1SpecialistManifestLoader? manifestLoader,
    E1SpecialistModelAssetChecker? modelAssetChecker,
    E1SpecialistRuntimeGuard guard = const E1SpecialistRuntimeGuard(),
  }) : _channel =
           channel ??
           const MethodChannel('kslas.e1_small_object_specialist_runtime'),
       _manifestLoader =
           manifestLoader ?? (() => E1SmallObjectSpecialistManifest.load()),
       _modelAssetChecker = modelAssetChecker ?? _defaultModelAssetChecker,
       _guard = guard;

  final MethodChannel _channel;
  final E1SpecialistManifestLoader _manifestLoader;
  final E1SpecialistModelAssetChecker _modelAssetChecker;
  final E1SpecialistRuntimeGuard _guard;

  bool _initialized = false;
  bool _available = false;
  E1SmallObjectSpecialistManifest? _manifest;

  bool get available => _available;
  E1SmallObjectSpecialistManifest? get manifest => _manifest;

  Future<bool> initialize() async {
    if (_initialized) return _available;
    _initialized = true;
    try {
      final manifest = await _manifestLoader();
      if (manifest == null || !manifest.runtimeAvailable) {
        _manifest = manifest;
        _available = false;
        return false;
      }
      _manifest = manifest;

      // Fail closed before native initialization unless the exact specialist
      // model declared by the manifest is present locally and non-empty. This
      // keeps the shared native engine's base-detector fallback unreachable
      // through the production specialist bridge.
      final modelPath = manifest.modelPath?.trim() ?? '';
      if (modelPath.isEmpty || !await _modelAssetChecker(modelPath)) {
        _available = false;
        return false;
      }

      final initialized = await _channel.invokeMethod<bool>(
        'initialize',
        manifest.toNativePolicy(),
      );
      _available = initialized == true;
      return _available;
    } on MissingPluginException {
      _available = false;
      return false;
    } catch (_) {
      _available = false;
      return false;
    }
  }

  @override
  Future<List<E1SmallObjectSpecialistObservation>> infer({
    required E1SmallObjectSpecialistRequest request,
    required E1SpecialistFrameInput frame,
  }) async {
    if (!_guard.canInfer(request: request, frame: frame)) {
      return const <E1SmallObjectSpecialistObservation>[];
    }
    if (!await initialize()) {
      return const <E1SmallObjectSpecialistObservation>[];
    }
    final manifest = _manifest;
    if (manifest == null || !manifest.runtimeAvailable) {
      return const <E1SmallObjectSpecialistObservation>[];
    }
    final requestedRoi = request.roiHint.roi;
    if (requestedRoi == null) {
      return const <E1SmallObjectSpecialistObservation>[];
    }

    try {
      final response = await _channel.invokeMapMethod<String, Object?>(
        'runFrame',
        <String, Object?>{
          ...frame.toPlatformMap(),
          'requested_targets': request.targets
              .map((target) => target.canonicalObjectId)
              .toList(growable: false),
          'reason': request.reason,
          'roi_hint': <String, Object?>{
            'strategy': request.roiHint.strategy,
            'anchor_canonical_object_id':
                request.roiHint.anchorCanonicalObjectId,
            'bounding_box': requestedRoi.toBoundingBox(),
          },
        },
      );
      if (response == null || response['available'] != true) {
        return const <E1SmallObjectSpecialistObservation>[];
      }

      final outputs = Map<String, Object?>.from(
        response['outputs'] as Map? ?? const <String, Object?>{},
      );
      final appliedRoi = E1NormalizedRoi.tryFrom(outputs['source_roi']);
      if (outputs['output_coordinate_space'] != 'normalized_roi' ||
          appliedRoi == null ||
          !_appliedRoiMatchesRequest(
            applied: appliedRoi,
            requested: requestedRoi,
            imageWidth: request.imageWidth,
            imageHeight: request.imageHeight,
          )) {
        return const <E1SmallObjectSpecialistObservation>[];
      }

      final inferenceTimestampNs = MonotonicTimebase.instance.nowNs;
      final requestedIds = request.targets
          .map((target) => target.canonicalObjectId)
          .toSet();
      final observations = <E1SmallObjectSpecialistObservation>[];
      final rawObjects = outputs['objects'];
      if (rawObjects is Iterable) {
        for (final rawObject in rawObjects) {
          if (rawObject is! Map) continue;
          final object = Map<Object?, Object?>.from(rawObject);
          final classId = _readInt(object['class_id']);
          if (classId == null ||
              classId < 0 ||
              classId >= manifest.classNames.length) {
            continue;
          }
          final canonicalId = manifest.classNames[classId];
          if (!requestedIds.contains(canonicalId)) continue;

          final confidence = _readDouble(object['confidence']);
          if (confidence == null ||
              confidence < manifest.confidenceThreshold ||
              confidence > 1.0) {
            continue;
          }
          final cropBox = _normalizedBoundingBox(object['box']);
          if (cropBox == null) continue;
          final boundingBox = _remapCropBoxToFrame(cropBox, appliedRoi);
          if (boundingBox == null) continue;

          final observation = E1SmallObjectSpecialistObservation(
            canonicalObjectId: canonicalId,
            confidence: confidence,
            boundingBox: boundingBox,
            modelId: manifest.modelId!,
            modelVersion: manifest.modelVersion!,
            sourceFrameId: request.sourceFrameId,
            captureTimestampNs: request.captureTimestampNs,
            inferenceTimestampNs: inferenceTimestampNs,
          );
          if (_matchesRequest(observation, request) && observation.isValid) {
            observations.add(observation);
          }
        }
      }
      return _guard.retainValidObservations(observations);
    } on MissingPluginException {
      _available = false;
      return const <E1SmallObjectSpecialistObservation>[];
    } catch (_) {
      return const <E1SmallObjectSpecialistObservation>[];
    }
  }

  bool _matchesRequest(
    E1SmallObjectSpecialistObservation observation,
    E1SmallObjectSpecialistRequest request,
  ) {
    return observation.sourceFrameId == request.sourceFrameId &&
        observation.captureTimestampNs == request.captureTimestampNs &&
        request.targets.any(
          (target) => target.canonicalObjectId == observation.canonicalObjectId,
        );
  }

  bool _appliedRoiMatchesRequest({
    required E1NormalizedRoi applied,
    required E1NormalizedRoi requested,
    required int imageWidth,
    required int imageHeight,
  }) {
    if (imageWidth <= 0 || imageHeight <= 0) return false;
    final xTolerance = 1.0 / imageWidth + 1e-6;
    final yTolerance = 1.0 / imageHeight + 1e-6;
    return (applied.x - requested.x).abs() <= xTolerance &&
        (applied.right - requested.right).abs() <= xTolerance &&
        (applied.y - requested.y).abs() <= yTolerance &&
        (applied.bottom - requested.bottom).abs() <= yTolerance;
  }

  Map<String, double>? _normalizedBoundingBox(Object? value) {
    if (value is! Map) return null;
    final box = Map<Object?, Object?>.from(value);

    final x = _readDouble(box['x']);
    final y = _readDouble(box['y']);
    final width = _readDouble(box['width']);
    final height = _readDouble(box['height']);
    if (x != null && y != null && width != null && height != null) {
      final roi = E1NormalizedRoi(x: x, y: y, width: width, height: height);
      return roi.isValid ? roi.toBoundingBox() : null;
    }

    final x1 = _readDouble(box['x1']);
    final y1 = _readDouble(box['y1']);
    final x2 = _readDouble(box['x2']);
    final y2 = _readDouble(box['y2']);
    if (x1 == null || y1 == null || x2 == null || y2 == null) return null;
    final roi = E1NormalizedRoi(x: x1, y: y1, width: x2 - x1, height: y2 - y1);
    return roi.isValid ? roi.toBoundingBox() : null;
  }

  Map<String, double>? _remapCropBoxToFrame(
    Map<String, double> cropBox,
    E1NormalizedRoi crop,
  ) {
    final local = E1NormalizedRoi.tryFrom(cropBox);
    if (local == null) return null;
    final full = E1NormalizedRoi(
      x: crop.x + local.x * crop.width,
      y: crop.y + local.y * crop.height,
      width: local.width * crop.width,
      height: local.height * crop.height,
    );
    return full.isValid ? full.toBoundingBox() : null;
  }

  int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '');
  }

  double? _readDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}
