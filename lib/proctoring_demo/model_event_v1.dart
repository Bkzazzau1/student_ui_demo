class ModelEventValidityIntervalV1 {
  const ModelEventValidityIntervalV1({
    required this.startTimestampNs,
    this.endTimestampNs,
  });

  final int startTimestampNs;
  final int? endTimestampNs;

  void validate() {
    if (startTimestampNs < 0) {
      throw const FormatException(
        'validity_interval.start_timestamp_ns must be non-negative',
      );
    }
    final end = endTimestampNs;
    if (end != null && end < startTimestampNs) {
      throw const FormatException(
        'validity_interval.end_timestamp_ns must be >= start_timestamp_ns',
      );
    }
  }

  Map<String, Object?> toJson() {
    validate();
    return <String, Object?>{
      'start_timestamp_ns': startTimestampNs,
      'end_timestamp_ns': endTimestampNs,
    };
  }
}

class ModelEventGeometryV1 {
  const ModelEventGeometryV1({
    this.coordinateSpace,
    this.boundingBox,
    this.keypoints = const <Map<String, Object?>>[],
    this.vector,
    this.regionId,
  });

  final String? coordinateSpace;
  final Map<String, Object?>? boundingBox;
  final List<Map<String, Object?>> keypoints;
  final List<double>? vector;
  final String? regionId;

  Map<String, Object?> toJson() => <String, Object?>{
    'coordinate_space': coordinateSpace,
    'bounding_box': boundingBox,
    'keypoints': keypoints,
    'vector': vector,
    'region_id': regionId,
  };
}

/// Thin Dart transport representation of the frozen Stage 3 ModelEventV1.
///
/// Dart does not own temporal memory, fusion, or risk. The production memory
/// owner is Rust. This class only prevents the Flutter integration layer from
/// degrading or renaming the language-neutral event contract while events move
/// between capture/model runtimes and the native core.
class ModelEventV1Payload {
  const ModelEventV1Payload({
    this.schemaVersion = schemaVersionV1,
    required this.sessionId,
    required this.eventId,
    required this.sourceFrameId,
    required this.captureTimestampNs,
    required this.inferenceTimestampNs,
    required this.modelId,
    required this.modelVersion,
    required this.trackId,
    required this.classId,
    required this.confidence,
    required this.quality,
    required this.geometry,
    required this.validityInterval,
    this.metadata = const <String, Object?>{},
  });

  static const String schemaVersionV1 = '1.0';

  final String schemaVersion;
  final String sessionId;
  final String eventId;
  final int? sourceFrameId;
  final int captureTimestampNs;
  final int inferenceTimestampNs;
  final String modelId;
  final String modelVersion;
  final String? trackId;
  final String classId;
  final double? confidence;
  final double? quality;
  final ModelEventGeometryV1? geometry;
  final ModelEventValidityIntervalV1 validityInterval;
  final Map<String, Object?> metadata;

  void validate() {
    if (schemaVersion != schemaVersionV1) {
      throw const FormatException('schema_version must be 1.0');
    }
    _requireText(sessionId, 'session_id');
    _requireText(eventId, 'event_id');
    _requireText(modelId, 'model_id');
    _requireText(modelVersion, 'model_version');
    _requireText(classId, 'class_id');
    if (trackId != null) _requireText(trackId!, 'track_id');
    if (sourceFrameId != null && sourceFrameId! < 0) {
      throw const FormatException('source_frame_id must be non-negative');
    }
    if (captureTimestampNs < 0) {
      throw const FormatException('capture_timestamp_ns must be non-negative');
    }
    if (inferenceTimestampNs < captureTimestampNs) {
      throw const FormatException(
        'inference_timestamp_ns must be >= capture_timestamp_ns',
      );
    }
    _validateUnitInterval(confidence, 'confidence');
    _validateUnitInterval(quality, 'quality');
    validityInterval.validate();
  }

  Map<String, Object?> toJson() {
    validate();
    return <String, Object?>{
      'schema_version': schemaVersion,
      'session_id': sessionId,
      'event_id': eventId,
      'source_frame_id': sourceFrameId,
      'capture_timestamp_ns': captureTimestampNs,
      'inference_timestamp_ns': inferenceTimestampNs,
      'model_id': modelId,
      'model_version': modelVersion,
      'track_id': trackId,
      'class_id': classId,
      'confidence': confidence,
      'quality': quality,
      'geometry': geometry?.toJson(),
      'validity_interval': validityInterval.toJson(),
      'metadata': metadata,
    };
  }
}

void _requireText(String value, String field) {
  if (value.trim().isEmpty) {
    throw FormatException('$field must be a non-empty string');
  }
}

void _validateUnitInterval(double? value, String field) {
  if (value == null) return;
  if (!value.isFinite || value < 0.0 || value > 1.0) {
    throw FormatException('$field must be between 0 and 1');
  }
}
