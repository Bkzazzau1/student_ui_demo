import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../proctoring_demo/native_face_landmarker_runtime.dart';
import 'face_identity_landmark_matrix.dart';
import 'face_identity_person_gate.dart';
import 'face_identity_quality.dart';

/// Drives face-quality analysis directly off the live camera preview stream
/// instead of the blind takePicture()-then-check polling enrollment used to
/// rely on. Frames are dropped while a previous one is still processing —
/// the same latest-frame-only pattern `DemoCameraScanFrameSource` already
/// uses for proctoring — so this never falls behind a backlog of stale
/// frames.
///
/// This only decides WHEN a frame looks good enough; the actual identity
/// sample is still captured with the existing `takePicture()` +
/// `FaceEmbeddingPipeline.processEncodedImage()` path once the caller acts
/// on a good frame, so alignment/embedding/anti-swap logic is untouched.
class FaceLiveCaptureEngine {
  FaceLiveCaptureEngine({
    NativeFaceLandmarkerRuntime? landmarker,
    FaceIdentityPersonGate? personGate,
    FaceIdentityQualityGrader? qualityGrader,
    this.personGateFrameInterval = 10,
    this.minimumFrameInterval = const Duration(milliseconds: 320),
  }) : _landmarker = landmarker ?? NativeFaceLandmarkerRuntime(),
       _personGate = personGate ?? FaceIdentityPersonGate(),
       _qualityGrader = qualityGrader ?? const FaceIdentityQualityGrader();

  final NativeFaceLandmarkerRuntime _landmarker;
  final FaceIdentityPersonGate _personGate;
  final FaceIdentityQualityGrader _qualityGrader;

  /// How many processed frames pass between YOLO "multiple people" sweeps.
  /// The landmarker-based checks already run on every processed frame; YOLO
  /// is heavier and its only blocking signal here (multiple people) doesn't
  /// need per-frame freshness.
  final int personGateFrameInterval;

  /// Face enrollment does not benefit from analyzing all 30 camera frames
  /// per second. Each raw YUV frame crosses a platform channel and becomes
  /// two full-size native bitmaps (YUV-decode + sensor-rotation correction),
  /// so keeping this well under 5 fps matters for large-object GC/native
  /// allocation pressure on mid-range devices, not just battery — a real
  /// device (MediaTek Mali GPU) hit a native crash correlated with heavy
  /// large-object GC churn during live capture testing at 200ms/~5fps.
  final Duration minimumFrameInterval;

  CameraController? _controller;
  bool _streaming = false;
  bool _processing = false;
  int _frameCounter = 0;
  int _session = 0;
  DateTime? _lastFrameStartedAt;
  static const FaceIdentityPersonGateResult _waitingForPersonSweep =
      FaceIdentityPersonGateResult(
        state: FaceIdentityPersonGateState.runtimeUnavailable,
        personCount: 0,
        personConfidence: 0.0,
        reason: 'Waiting for the first live person-gate sweep.',
      );
  FaceIdentityPersonGateResult _lastPersonGate = _waitingForPersonSweep;

  bool get isStreaming => _streaming;

  /// Attempts to start live-stream analysis on [controller]. Returns false
  /// (without throwing) when streaming isn't supported on this platform/build
  /// — e.g. `camera_windows`, which does not implement `startImageStream` —
  /// so callers can fall back to the existing still-capture polling loop.
  Future<bool> start({
    required CameraController controller,
    required void Function(
      FaceLandmarkMatrix landmarks,
      FaceIdentityQualityGrade grade,
    )
    onFrame,
  }) async {
    if (_streaming) return true;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      return false;
    }
    _controller = controller;
    _frameCounter = 0;
    _lastFrameStartedAt = null;
    _lastPersonGate = _waitingForPersonSweep;
    final session = ++_session;
    try {
      await controller.startImageStream((image) {
        if (_processing) return;
        final now = DateTime.now();
        final previous = _lastFrameStartedAt;
        if (previous != null &&
            now.difference(previous) < minimumFrameInterval) {
          return;
        }
        _lastFrameStartedAt = now;
        _processing = true;
        unawaited(_handleFrame(image, onFrame, session));
      });
      if (session != _session) return false;
      _streaming = true;
      return true;
    } catch (_) {
      _streaming = false;
      return false;
    }
  }

  Future<void> stop() async {
    _streaming = false;
    _session++;
    final controller = _controller;
    _controller = null;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {
      // Already stopped, e.g. the controller was disposed first.
    }
  }

  Future<void> _handleFrame(
    CameraImage image,
    void Function(FaceLandmarkMatrix, FaceIdentityQualityGrade) onFrame,
    int session,
  ) async {
    try {
      final rotationDegrees = _controller?.description.sensorOrientation ?? 0;
      final payload = await _landmarker.analyseCameraImageRaw(
        image,
        rotationDegrees: rotationDegrees,
      );
      if (session != _session) return;
      // The native side rotates the bitmap by `rotationDegrees` before
      // running detection, so the landmark points it returns are normalized
      // against the ROTATED image — for a 90/270 rotation that means width
      // and height are swapped relative to the raw `CameraImage`. Scaling
      // the normalized points back with the un-rotated dimensions here
      // silently skews every geometry check (coverage, centering, aspect
      // ratio), which is what made the quality gate reject a
      // correctly-framed face as "move closer and center".
      final rotatedQuarterTurn = (rotationDegrees ~/ 90).isOdd;
      final analysisWidth = rotatedQuarterTurn ? image.height : image.width;
      final analysisHeight = rotatedQuarterTurn ? image.width : image.height;
      final confidence = _number(payload?['confidence']);
      final points = _points(
        payload?['landmarks'],
        analysisWidth,
        analysisHeight,
      );
      final matrix = payload == null
          ? FaceLandmarkMatrix.empty()
          : FaceLandmarkMatrix.fromPoints(points, analysisWidth, analysisHeight);

      _frameCounter++;
      if (_frameCounter % personGateFrameInterval == 0) {
        _lastPersonGate = await _personGate.analyzeCameraImage(image);
      }

      final grade = _qualityGrader.grade(
        personGate: _lastPersonGate,
        faceConfidence: confidence,
        landmarks: matrix,
      );
      if (_streaming && session == _session) onFrame(matrix, grade);
    } catch (_) {
      // A single bad frame must not stop the stream; the next frame retries.
    } finally {
      _processing = false;
    }
  }

  Map<int, math.Point<double>> _points(Object? raw, int width, int height) {
    if (raw is! Iterable) return const {};
    final result = <int, math.Point<double>>{};
    for (final value in raw.whereType<Map>()) {
      final point = Map<String, Object?>.from(value);
      final index = (point['index'] as num?)?.toInt();
      if (index == null) continue;
      result[index] = math.Point<double>(
        _number(point['x']) * width,
        _number(point['y']) * height,
      );
    }
    return result;
  }

  double _number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0.0;
}
