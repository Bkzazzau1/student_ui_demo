import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// How to turn a streamed camera frame into an upright, unmirrored image,
/// the same geometry as a still photo from `takePicture`.
///
/// - **Android** (CameraX): stream frames are in sensor orientation and not
///   mirrored, so they are rotated clockwise by `sensorOrientation`.
/// - **iOS/iPadOS** (camera_avfoundation): stream frames already follow the
///   device orientation (the plugin reports a fixed `sensorOrientation` of 90
///   that does not apply to them), and front-camera frames are mirrored to
///   match the preview. Photos are not mirrored, so the mirror is undone;
///   otherwise a live check would compare a mirrored face with the
///   unmirrored Face ID photos.
@immutable
class CameraFrameOrientation {
  const CameraFrameOrientation({
    required this.rotationDegrees,
    required this.mirrorHorizontally,
  });

  static const CameraFrameOrientation upright = CameraFrameOrientation(
    rotationDegrees: 0,
    mirrorHorizontally: false,
  );

  /// Clockwise rotation that makes the frame upright.
  final int rotationDegrees;

  /// Whether the frame must be flipped left-right (applied before rotating).
  final bool mirrorHorizontally;

  bool get swapsWidthAndHeight => (rotationDegrees ~/ 90).isOdd;

  static CameraFrameOrientation of(
    CameraDescription? description, {
    TargetPlatform? platform,
  }) {
    if (description == null) return upright;
    final target = platform ?? defaultTargetPlatform;
    if (target == TargetPlatform.iOS) {
      return CameraFrameOrientation(
        rotationDegrees: 0,
        mirrorHorizontally:
            description.lensDirection == CameraLensDirection.front,
      );
    }
    return CameraFrameOrientation(
      rotationDegrees: ((description.sensorOrientation % 360) + 360) % 360,
      mirrorHorizontally: false,
    );
  }

  /// Stream format the face pipeline handles best: BGRA on iOS (one plane,
  /// no colour-range guesswork), YUV 4:2:0 on Android, and the plugin default
  /// on Windows (which does not stream).
  static ImageFormatGroup? preferredStreamFormat({TargetPlatform? platform}) {
    final target = platform ?? defaultTargetPlatform;
    if (kIsWeb || target == TargetPlatform.windows) return null;
    if (target == TargetPlatform.iOS) return ImageFormatGroup.bgra8888;
    return ImageFormatGroup.yuv420;
  }

  @override
  bool operator ==(Object other) =>
      other is CameraFrameOrientation &&
      other.rotationDegrees == rotationDegrees &&
      other.mirrorHorizontally == mirrorHorizontally;

  @override
  int get hashCode => Object.hash(rotationDegrees, mirrorHorizontally);

  @override
  String toString() =>
      'CameraFrameOrientation(rotate: $rotationDegrees, mirror: $mirrorHorizontally)';
}
