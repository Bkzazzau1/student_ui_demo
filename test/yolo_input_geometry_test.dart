import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/native_vision_bridge.dart';
import 'package:students_ui_demo/proctoring_demo/optimized_vision_object_event_adapter.dart';
import 'package:students_ui_demo/proctoring_demo/optimized_vision_runtime_bridge.dart';
import 'package:students_ui_demo/proctoring_demo/yolo_input_geometry.dart';

// 640x480 camera frame letterboxed into 416x416: scale 0.65, content 416x312,
// 52 px of padding above and below.
const _letterbox = <String, Object?>{
  'input_preprocessing': 'letterbox_rgb01',
  'input_width': 416,
  'input_height': 416,
  'image_width': 640,
  'image_height': 480,
  'letterbox_scale_x': 0.65,
  'letterbox_scale_y': 0.65,
  'letterbox_pad_x': 0.0,
  'letterbox_pad_y': 52.0,
};

/// Two predictions, two classes, channels-first: [cx, cy, w, h, c0, c1] x N.
List<double> _channelsFirst(List<List<double>> predictions) {
  const attributes = 6;
  final n = predictions.length;
  final output = List<double>.filled(attributes * n, 0);
  for (var p = 0; p < n; p++) {
    for (var a = 0; a < attributes; a++) {
      output[a * n + p] = predictions[p][a];
    }
  }
  return output;
}

void main() {
  test(
    'letterbox inverse maps input pixels back to normalized frame boxes',
    () {
      final geometry = YoloInputGeometry.fromOutputs(_letterbox)!;
      // Frame box (160,240)-(480,480) px -> input (104,208)-(312,364) px.
      final mapped = geometry.toNormalizedSourceBoxes(
        _channelsFirst(<List<double>>[
          <double>[208, 286, 208, 156, 0.9, 0.1],
          <double>[100, 20, 40, 30, 0.8, 0.2], // entirely inside top padding
        ]),
        numPredictions: 2,
        attributes: 6,
        layout: 'channels_first_yolov8',
      );
      // Channels-first: attribute a of prediction p is at a * 2 + p.
      expect(mapped[0], closeTo(0.5, 1e-9)); // cx
      expect(mapped[2], closeTo(0.75, 1e-9)); // cy
      expect(mapped[4], closeTo(0.5, 1e-9)); // w
      expect(mapped[6], closeTo(0.5, 1e-9)); // h
      expect(mapped[8], 0.9); // class scores untouched
      // The padding-only box has no area in the frame: scores are zeroed.
      expect(mapped[7], 0); // h of prediction 1
      expect(mapped[9], 0);
      expect(mapped[11], 0);
    },
  );

  test('boxes are clipped to the frame and rows layout is supported', () {
    final geometry = YoloInputGeometry.fromOutputs(_letterbox)!;
    // Row layout. Box spills 20 px into the bottom padding (y2 = 384 > 364).
    final mapped = geometry.toNormalizedSourceBoxes(
      <double>[208, 334, 104, 100, 0.7, 0.1],
      numPredictions: 1,
      attributes: 6,
      layout: 'rows_yolov8',
    );
    final y1 = (284 - 52) / 312;
    expect(mapped[1], closeTo((y1 + 1.0) / 2, 1e-9));
    expect(mapped[3], closeTo(1.0 - y1, 1e-9));
    expect(mapped[4], 0.7);
  });

  test('stretch geometry scales each axis independently', () {
    final geometry = YoloInputGeometry.fromOutputs(const <String, Object?>{
      'input_preprocessing': 'stretch_rgb01',
      'input_width': 416,
      'input_height': 416,
      'image_width': 832,
      'image_height': 208,
    })!;
    final mapped = geometry.toNormalizedSourceBoxes(
      <double>[208, 208, 104, 208, 0.5, 0.5],
      numPredictions: 1,
      attributes: 6,
      layout: 'rows_yolov8',
    );
    expect(mapped.sublist(0, 4), <double>[0.5, 0.5, 0.25, 0.5]);
  });

  test('missing or invalid geometry leaves callers on the raw tensor', () {
    expect(YoloInputGeometry.fromOutputs(const <String, Object?>{}), isNull);
    expect(
      YoloInputGeometry.fromOutputs(<String, Object?>{
        ..._letterbox,
        'letterbox_scale_x': 0,
      }),
      isNull,
    );
    expect(
      YoloInputGeometry.fromOutputs(<String, Object?>{
        ..._letterbox,
        'input_preprocessing': 'stretch_rgb_pm1',
      }),
      isNull,
    );
    final geometry = YoloInputGeometry.fromOutputs(_letterbox)!;
    final raw = <double>[1, 2, 3];
    expect(
      identical(
        geometry.toNormalizedSourceBoxes(
          raw,
          numPredictions: 1,
          attributes: 6,
          layout: 'rows_yolov8',
        ),
        raw,
      ),
      isTrue,
    );
  });

  test('event adapter hands frame-space boxes to the Rust decoder', () {
    final bridge = _RecordingNativeVision();
    final adapter = OptimizedVisionObjectEventAdapter(nativeVision: bridge);
    adapter.mapResult(
      OptimizedVisionRuntimeResult(
        available: true,
        backend: 'onnxRuntimeCpu',
        precision: 'fp32Fallback',
        inferenceMs: 1,
        outputs: <String, Object?>{
          ..._letterbox,
          'model_family': 'yolo',
          'layout': 'channels_first_yolov8',
          'class_names': const <String>['person', 'phone'],
          'num_predictions': 1,
          'yolo_output': const <double>[208, 286, 208, 156, 0.9, 0.1],
        },
      ),
    );
    expect(bridge.calls, 1);
    expect(bridge.lastImageWidth, 640);
    expect(bridge.lastImageHeight, 480);
    // Normalized frame coordinates; Rust scales them by the frame size.
    const expected = <double>[0.5, 0.75, 0.5, 0.5];
    for (var i = 0; i < expected.length; i++) {
      expect(bridge.lastOutput![i], closeTo(expected[i], 1e-9));
    }
  });
}

class _RecordingNativeVision implements NativeVisionBridge {
  int calls = 0;
  List<double>? lastOutput;
  int? lastImageWidth;
  int? lastImageHeight;

  @override
  NativeObjectReviewSnapshot? decodeYoloOutput({
    required List<double> output,
    required int numPredictions,
    required int numClasses,
    required int imageWidth,
    required int imageHeight,
    required double confidenceThreshold,
    required double iouThreshold,
    required String layout,
    required List<String> classNames,
  }) {
    calls++;
    lastOutput = output;
    lastImageWidth = imageWidth;
    lastImageHeight = imageHeight;
    return null;
  }

  @override
  NativeVisionFrameQualitySnapshot? analyzeFrameQuality(CameraImage image) =>
      null;

  @override
  NativeHeadPoseReviewSnapshot? analyzeHeadPoseGeometry({
    required double leftEyeX,
    required double leftEyeY,
    required double rightEyeX,
    required double rightEyeY,
    required double noseX,
    required double noseY,
    required double mouthX,
    required double mouthY,
    required double faceWidth,
    required double faceHeight,
  }) => null;
}
