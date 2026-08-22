import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

import '../proctoring_demo/landmark_liveness_challenge_service.dart';
import '../proctoring_demo/native_face_landmarker_runtime.dart';
import '../rust/api/liveness_challenge.dart';

/// Drives a short randomized-challenge liveness check for 1:1 identity
/// verification, reusing the same [LivenessChallengeSession] /
/// `analyzeLivenessChallenge` engine the proctoring feature already relies
/// on instead of inventing a second liveness system.
///
/// A printed photo or a face replayed on another screen will not pass this:
/// the underlying Rust evaluator requires genuine motion (a blink or a head
/// turn) matching a challenge chosen at random for this session, and flags
/// repeated/flat frames as a possible presentation attack rather than
/// silently accepting them.
class FaceIdentityLivenessGate {
  FaceIdentityLivenessGate({NativeFaceLandmarkerRuntime? landmarker})
    : _landmarker = landmarker ?? NativeFaceLandmarkerRuntime();

  final NativeFaceLandmarkerRuntime _landmarker;

  Future<LivenessChallengeResult> runBurst({
    required CameraController controller,
    LivenessChallengeSession? session,
    int maxFrames = 6,
    Duration frameGap = const Duration(milliseconds: 650),
  }) async {
    final activeSession = session ?? LivenessChallengeSession.start();
    for (var frame = 0; frame < maxFrames; frame++) {
      if (frame > 0) await Future<void>.delayed(frameGap);
      if (!controller.value.isInitialized) break;
      Map<String, Object?>? payload;
      try {
        final file = await controller.takePicture();
        final decoded = img.decodeImage(await File(file.path).readAsBytes());
        if (decoded == null) continue;
        payload = await _landmarker.analyseRgbRaw(
          rgbBytes: _toRgb(decoded),
          width: decoded.width,
          height: decoded.height,
        );
      } catch (_) {
        continue;
      }
      if (payload == null) continue;
      final result = activeSession.addLandmarkPayload(
        payload,
        timestampMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      );
      if (result != null &&
          (result.state == 'live_challenge_passed' ||
              result.state == 'possible_presentation_attack')) {
        return result;
      }
    }
    return activeSession.evaluate();
  }

  // Bulk conversion instead of a per-pixel `getPixel` loop: this runs once
  // per liveness-burst frame (up to `maxFrames` times per identity check),
  // so the per-pixel overhead was multiplied across the whole burst.
  Uint8List _toRgb(img.Image decoded) => decoded.getBytes(order: img.ChannelOrder.rgb);
}
