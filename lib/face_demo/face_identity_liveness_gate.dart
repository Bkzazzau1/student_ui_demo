import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../proctoring_demo/camera_image_codec.dart';
import '../proctoring_demo/landmark_liveness_challenge_service.dart';
import '../proctoring_demo/native_face_landmarker_runtime.dart';
import '../rust/api/liveness_challenge.dart';

/// A camera frame that was part of a liveness burst, kept so the identity
/// match can use the very frames that proved liveness.
class BoundFaceFrame {
  const BoundFaceFrame({
    required this.encodedImage,
    required this.timestampMs,
    required this.yaw,
    required this.pitch,
  });

  final Uint8List encodedImage;
  final int timestampMs;
  final double yaw;
  final double pitch;

  double get frontalDistance => yaw.abs() + pitch.abs();
}

class BoundLivenessBurst {
  const BoundLivenessBurst({required this.result, required this.frames});

  final LivenessChallengeResult result;

  /// Frames from inside the burst with a usable face, most frontal first.
  final List<BoundFaceFrame> frames;

  bool get passed => result.state == 'live_challenge_passed';
}

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
    final burst = await _run(
      controller: controller,
      session: session,
      maxFrames: maxFrames,
      frameGap: frameGap,
      promptLeadIn: promptLeadIn,
      onChallengeStarted: onChallengeStarted,
      keepFrames: 0,
    );
    return burst.result;
  }

  /// Runs the challenge and also returns up to [keepFrames] of the burst's
  /// own frames (most frontal first) for the identity match. Matching on
  /// these frames means a live person cannot pass the challenge and then
  /// hold up someone else's photo for the identity samples.
  Future<BoundLivenessBurst> runBoundBurst({
    required CameraController controller,
    LivenessChallengeSession? session,
    int maxFrames = 14,
    int keepFrames = 6,
    Duration frameGap = const Duration(milliseconds: 450),
    Duration promptLeadIn = const Duration(milliseconds: 1200),
    void Function(LivenessChallengeSession session)? onChallengeStarted,
  }) => _run(
    controller: controller,
    session: session,
    maxFrames: maxFrames,
    frameGap: frameGap,
    promptLeadIn: promptLeadIn,
    onChallengeStarted: onChallengeStarted,
    keepFrames: keepFrames,
  );

  Future<BoundLivenessBurst> _run({
    required CameraController controller,
    required LivenessChallengeSession? session,
    required int maxFrames,
    required Duration frameGap,
    required Duration promptLeadIn,
    required void Function(LivenessChallengeSession session)?
    onChallengeStarted,
    required int keepFrames,
  }) async {
    final frames = _BoundFrameCollector(keepFrames);
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
    final streamed = await _runImageStream(controller, activeSession, frames);
    if (streamed != null) {
      return BoundLivenessBurst(
        result: _withDiagnostics(streamed),
        frames: frames.frontalFirst(),
      );
    }

    for (var frame = 0; frame < maxFrames; frame++) {
      if (frame > 0) await Future<void>.delayed(frameGap);
      if (!controller.value.isInitialized) break;
      Map<String, Object?>? payload;
      Uint8List encoded;
      try {
        final file = await controller.takePicture();
        encoded = await File(file.path).readAsBytes();
        final decoded = img.decodeImage(encoded);
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
      final before = activeSession.observationCount;
      final timestampMs = DateTime.now().toUtc().millisecondsSinceEpoch;
      final result = activeSession.addLandmarkPayload(
        payload,
        timestampMs: timestampMs,
      );
      final observation = activeSession.lastObservation;
      if (activeSession.observationCount > before && observation != null) {
        frames.offer(
          () => encoded,
          timestampMs: timestampMs,
          yaw: observation.headYaw,
          pitch: observation.headPitch,
        );
      }
      if (result != null &&
          (result.state == 'live_challenge_passed' ||
              result.state == 'possible_presentation_attack')) {
        return BoundLivenessBurst(
          result: result,
          frames: frames.frontalFirst(),
        );
      }
    }
    return BoundLivenessBurst(
      result: _withDiagnostics(activeSession.evaluate()),
      frames: frames.frontalFirst(),
    );
  }

  Future<LivenessChallengeResult?> _runImageStream(
    CameraController controller,
    LivenessChallengeSession session,
    _BoundFrameCollector frames,
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
            final before = session.observationCount;
            final timestampMs = DateTime.now().toUtc().millisecondsSinceEpoch;
            final result = session.addLandmarkPayload(
              payload,
              timestampMs: timestampMs,
            );
            final observation = session.lastObservation;
            if (session.observationCount > before && observation != null) {
              // Encoding is deferred: only frames the collector keeps are
              // converted, so the stream is not slowed down by JPEG work.
              frames.offer(
                () => CameraImageCodec.toUprightJpeg(
                  image,
                  sensorOrientation: controller.description.sensorOrientation,
                ),
                timestampMs: timestampMs,
                yaw: observation.headYaw,
                pitch: observation.headPitch,
              );
            }
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

/// Keeps the [capacity] most frontal frames of a burst. Frames are encoded
/// only when kept, and a new frame replaces the least frontal kept frame.
class _BoundFrameCollector {
  _BoundFrameCollector(this.capacity);

  final int capacity;
  final List<BoundFaceFrame> _frames = <BoundFaceFrame>[];

  void offer(
    Uint8List? Function() encode, {
    required int timestampMs,
    required double yaw,
    required double pitch,
  }) {
    if (capacity <= 0) return;
    final distance = yaw.abs() + pitch.abs();
    if (_frames.length >= capacity) {
      final worst = _frames.reduce(
        (a, b) => a.frontalDistance >= b.frontalDistance ? a : b,
      );
      if (distance >= worst.frontalDistance) return;
      _frames.remove(worst);
    }
    final encoded = encode();
    if (encoded == null || encoded.isEmpty) return;
    _frames.add(
      BoundFaceFrame(
        encodedImage: encoded,
        timestampMs: timestampMs,
        yaw: yaw,
        pitch: pitch,
      ),
    );
  }

  List<BoundFaceFrame> frontalFirst() =>
      List<BoundFaceFrame>.of(_frames)
        ..sort((a, b) => a.frontalDistance.compareTo(b.frontalDistance));
}
