import 'dart:typed_data';

import 'e1_small_object_specialist.dart';

class E1SpecialistFramePlane {
  const E1SpecialistFramePlane({
    required this.bytes,
    required this.bytesPerRow,
    required this.bytesPerPixel,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int bytesPerRow;
  final int bytesPerPixel;
  final int width;
  final int height;

  bool get isValid =>
      bytes.isNotEmpty &&
      bytesPerRow > 0 &&
      bytesPerPixel > 0 &&
      width > 0 &&
      height > 0;

  Map<String, Object?> toPlatformMap() => <String, Object?>{
    'bytes': bytes,
    'bytes_per_row': bytesPerRow,
    'bytes_per_pixel': bytesPerPixel,
    'width': width,
    'height': height,
  };
}

/// Platform-neutral local frame envelope for E1 specialist inference.
///
/// It can represent the camera plugin's native image planes or one packed RGB
/// plane. The frame carries the same provenance as the base E1 inference so a
/// specialist result can never be detached from its source observation.
class E1SpecialistFrameInput {
  const E1SpecialistFrameInput({
    required this.format,
    required this.width,
    required this.height,
    required this.sourceFrameId,
    required this.captureTimestampNs,
    required this.planes,
  });

  final String format;
  final int width;
  final int height;
  final int? sourceFrameId;
  final int captureTimestampNs;
  final List<E1SpecialistFramePlane> planes;

  bool get isValid =>
      format.trim().isNotEmpty &&
      width > 0 &&
      height > 0 &&
      captureTimestampNs >= 0 &&
      planes.isNotEmpty &&
      planes.every((plane) => plane.isValid);

  bool matchesRequest(E1SmallObjectSpecialistRequest request) {
    if (!isValid || !request.isValid) return false;
    return width == request.imageWidth &&
        height == request.imageHeight &&
        sourceFrameId == request.sourceFrameId &&
        captureTimestampNs == request.captureTimestampNs;
  }

  Map<String, Object?> toPlatformMap() => <String, Object?>{
    'format': format,
    'width': width,
    'height': height,
    'source_frame_id': sourceFrameId,
    'capture_timestamp_ns': captureTimestampNs,
    'planes': planes.map((plane) => plane.toPlatformMap()).toList(growable: false),
  };
}
