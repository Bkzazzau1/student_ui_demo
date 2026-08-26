import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
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
    int maxFrames = 14,
    Duration frameGap = const Duration(milliseconds: 450),
    Duration promptLeadIn = const Duration(milliseconds: 1200),
    void Function(LivenessChallengeSession session)? onChallengeStarted,
  }) async {
    final activeSession =
        session ??
        LivenessChallengeSession.start(duration: const Duration(seconds: 15));
    // The caller needs this before the burst starts, not after: the student
    // has to know whether to blink or turn their head *before* the frames
    // are taken, otherwise the randomized challenge always looks like a
    // silent timeout regardless of what they actually did.
    onChallengeStarted?.call(activeSession);
    // Let the visual and spoken instruction reach the user before observations
    // begin. Previously the first captures happened while TTS was still
    // reading the challenge, consuming much of the short deadline.
    if (promptLeadIn > Duration.zero) {
      await Future<void>.delayed(promptLeadIn);
    }

    // Android/iOS cameras can supply preview frames continuously. This is
    // both faster than repeated JPEG captures and frequent enough to observe
    // the closed portion of a normal blink. Unsupported platforms retain the
    // still-capture fallback below.
    final streamed = await _runImageStream(controller, activeSession);
    if (streamed != null) return _withDiagnostics(streamed);

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
    return _withDiagnostics(activeSession.evaluate());
  }

  Future<LivenessChallengeResult?> _runImageStream(
    CameraController controller,
    LivenessChallengeSession session,
  ) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) return null;
    if (controller.value.isStreamingImages) return null;

    final completed = Completer<LivenessChallengeResult>();
    var processing = false;
    var started = false;
    var acceptingFrames = true;
    Future<void>? inFlight;
    try {
      await controller.startImageStream((image) {
        if (!acceptingFrames || processing || completed.isCompleted) return;
        processing = true;
        final work = () async {
          try {
            final payload = await _landmarker.analyseCameraImageRaw(
              image,
              rotationDegrees: controller.description.sensorOrientation,
            );
            if (payload == null || completed.isCompleted) return;
            final result = session.addLandmarkPayload(
              payload,
              timestampMs: DateTime.now().toUtc().millisecondsSinceEpoch,
            );
            if (result != null &&
                (result.state == 'live_challenge_passed' ||
                    result.state == 'possible_presentation_attack')) {
              completed.complete(result);
            }
          } catch (_) {
            // A single malformed/failed preview frame must not end the check.
          } finally {
            processing = false;
          }
        }();
        inFlight = work;
        unawaited(work);
      });
      started = true;

      final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
      final remainingMs = session.deadlineMs - nowMs;
      final timeout = Duration(milliseconds: remainingMs > 0 ? remainingMs : 1);
      return await Future.any<LivenessChallengeResult>(
        <Future<LivenessChallengeResult>>[
          completed.future,
          Future<LivenessChallengeResult>.delayed(
            timeout,
            () => session.evaluate(nowMs: session.deadlineMs + 1),
          ),
        ],
      );
    } catch (_) {
      return null;
    } finally {
      // Do not tear down CameraX while a frame is still crossing the platform
      // channel. That race produced abandoned ImageReader buffers and could
      // leave the following takePicture() without a valid capture session.
      acceptingFrames = false;
      final pending = inFlight;
      if (pending != null) {
        try {
          await pending;
        } catch (_) {
          // A bad final frame is handled the same way as any other bad frame.
        }
      }
      if (started && controller.value.isInitialized) {
        try {
          if (controller.value.isStreamingImages) {
            await controller.stopImageStream();
          }
        } catch (_) {
          // The camera may have been disposed while the challenge was active.
        }
      }
    }
  }

  LivenessChallengeResult _withDiagnostics(LivenessChallengeResult result) {
    if (result.state == 'live_challenge_passed') return result;
    return LivenessChallengeResult(
      state: result.state,
      challenge: result.challenge,
      completed: result.completed,
      reliable: result.reliable,
      progress: result.progress,
      spoofRiskScore: result.spoofRiskScore,
      usableObservations: result.usableObservations,
      reason:
          '${result.reason} '
          '(challenge: ${result.challenge}, reliable frames: '
          '${result.usableObservations}, progress: '
          '${(result.progress * 100).round()}%).',
    );
  }

  // Bulk conversion instead of a per-pixel `getPixel` loop: this runs once
  // per liveness-burst frame (up to `maxFrames` times per identity check),
  // so the per-pixel overhead was multiplied across the whole burst.
  Uint8List _toRgb(img.Image decoded) =>
      decoded.getBytes(order: img.ChannelOrder.rgb);
}
