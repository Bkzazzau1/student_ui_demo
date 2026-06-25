import 'dart:typed_data';

import 'package:camera/camera.dart';

import 'live_camera_frame_bus.dart';
import 'local_evidence_vault_service.dart';

class CameraEvidenceCaptureService {
  const CameraEvidenceCaptureService({
    this.vault = const LocalEvidenceVaultService(),
  });

  final LocalEvidenceVaultService vault;

  Future<Map<String, Object?>?> saveRecentCameraEvidence({
    required String studentId,
    required String examId,
    required String attemptId,
    required String eventType,
    required String reviewReason,
    CameraController? controller,
    LiveCameraFrameBus? frameBus,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    final jpegRecord = await _trySaveControllerJpeg(
      studentId: studentId,
      examId: examId,
      attemptId: attemptId,
      eventType: eventType,
      reviewReason: reviewReason,
      controller: controller,
      metadata: metadata,
    );
    if (jpegRecord != null) return jpegRecord;

    return _trySaveLatestFramePlane(
      studentId: studentId,
      examId: examId,
      attemptId: attemptId,
      eventType: eventType,
      reviewReason: reviewReason,
      frameBus: frameBus ?? LiveCameraFrameBus.instance,
      metadata: metadata,
    );
  }

  Future<Map<String, Object?>?> _trySaveControllerJpeg({
    required String studentId,
    required String examId,
    required String attemptId,
    required String eventType,
    required String reviewReason,
    required CameraController? controller,
    required Map<String, Object?> metadata,
  }) async {
    final camera = controller;
    if (camera == null || !camera.value.isInitialized) return null;
    if (camera.value.isTakingPicture || camera.value.isRecordingVideo) return null;
    if (camera.value.isStreamingImages) return null;

    try {
      final picture = await camera.takePicture();
      final bytes = await picture.readAsBytes();
      if (bytes.isEmpty) return null;
      final record = await vault.saveBytesEvidence(
        studentId: studentId,
        examId: examId,
        attemptId: attemptId,
        eventType: eventType,
        fileType: 'jpg',
        reviewReason: reviewReason,
        bytes: bytes,
        metadata: <String, Object?>{
          ...metadata,
          'source': 'camera_evidence_capture_service',
          'capture_mode': 'controller_jpeg_snapshot',
          'format': 'jpeg',
        },
      );
      return record.toJson();
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, Object?>?> _trySaveLatestFramePlane({
    required String studentId,
    required String examId,
    required String attemptId,
    required String eventType,
    required String reviewReason,
    required LiveCameraFrameBus frameBus,
    required Map<String, Object?> metadata,
  }) async {
    final frame = frameBus.latestFrame;
    if (frame == null || frame.image.planes.isEmpty) return null;
    final plane = frame.image.planes.first;
    final bytes = Uint8List.fromList(plane.bytes);
    if (bytes.isEmpty) return null;

    try {
      final record = await vault.saveBytesEvidence(
        studentId: studentId,
        examId: examId,
        attemptId: attemptId,
        eventType: eventType,
        fileType: 'yplane',
        reviewReason: reviewReason,
        bytes: bytes,
        metadata: <String, Object?>{
          ...metadata,
          ...frame.toMetadata(),
          'source': 'camera_evidence_capture_service',
          'capture_mode': 'latest_camera_frame_plane',
          'format': frame.formatGroup,
          'plane_index': 0,
          'plane_bytes_per_row': plane.bytesPerRow,
          'plane_bytes_per_pixel': plane.bytesPerPixel,
          'plane_count': frame.image.planes.length,
        },
      );
      return record.toJson();
    } catch (_) {
      return null;
    }
  }
}
