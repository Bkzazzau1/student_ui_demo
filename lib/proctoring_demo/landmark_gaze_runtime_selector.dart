import 'package:camera/camera.dart';
import 'dart:typed_data';

import 'gaze_head_pose_estimator.dart';
import 'native_face_landmarker_runtime.dart';

class LandmarkGazeRuntimeSelector {
  LandmarkGazeRuntimeSelector({NativeFaceLandmarkerRuntime? runtime})
    : _runtime = runtime ?? NativeFaceLandmarkerRuntime();

  final NativeFaceLandmarkerRuntime _runtime;
  final GazeHeadPoseEstimator _fallback = GazeHeadPoseEstimator();
  bool _checked = false;
  bool _ready = false;

  bool get modelRuntimeReady => _ready;
  bool get fallbackActive => !_ready;

  Future<GazeHeadPoseResult?> analyse(CameraImage image) async {
    if (!_checked) {
      _checked = true;
      _ready = await _runtime.initialize();
    }
    if (_ready) {
      final result = await _runtime.analyse(image);
      if (result != null) return result;
    }
    return _fallback.analyse(image);
  }

  Future<GazeHeadPoseResult?> analyseRgb({
    required Uint8List rgbBytes,
    required int width,
    required int height,
  }) async {
    if (!_checked) {
      _checked = true;
      _ready = await _runtime.initialize();
    }
    if (!_ready) return null;
    return _runtime.analyseRgb(
      rgbBytes: rgbBytes,
      width: width,
      height: height,
    );
  }

  Future<Map<String, Object?>?> analyseRgbPayload({
    required Uint8List rgbBytes,
    required int width,
    required int height,
  }) async {
    if (!_checked) {
      _checked = true;
      _ready = await _runtime.initialize();
    }
    if (!_ready) return null;
    return _runtime.analyseRgbRaw(
      rgbBytes: rgbBytes,
      width: width,
      height: height,
    );
  }
}
