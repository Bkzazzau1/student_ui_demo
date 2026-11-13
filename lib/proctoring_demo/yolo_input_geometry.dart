/// How a camera frame was mapped onto a YOLO detector's input tensor.
///
/// Native runtimes report this next to the raw YOLO tensor. Raw YOLOv8 boxes
/// are pixel `cx, cy, w, h` in the *model input* (for example 416x416), not in
/// the camera frame. [toNormalizedSourceBoxes] maps them back to normalized
/// coordinates of the original camera frame by undoing the letterbox padding
/// and scale (or a plain stretch).
class YoloInputGeometry {
  const YoloInputGeometry({
    required this.preprocessing,
    required this.inputWidth,
    required this.inputHeight,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.scaleX,
    required this.scaleY,
    required this.padX,
    required this.padY,
  });

  final String preprocessing;
  final int inputWidth;
  final int inputHeight;
  final int sourceWidth;
  final int sourceHeight;

  /// Input pixels per source pixel along each axis.
  final double scaleX;
  final double scaleY;

  /// Left/top padding in input pixels (zero for a stretch).
  final double padX;
  final double padY;

  /// Reads the geometry a native runtime reported. Returns null when the
  /// runtime did not report it (older native builds), so callers keep the
  /// raw tensor unchanged instead of guessing a mapping.
  static YoloInputGeometry? fromOutputs(Map<String, Object?> outputs) {
    final preprocessing =
        outputs['input_preprocessing']?.toString().trim() ?? '';
    final inputWidth = _int(outputs['input_width']);
    final inputHeight = _int(outputs['input_height']);
    final sourceWidth = _int(outputs['image_width']);
    final sourceHeight = _int(outputs['image_height']);
    if (inputWidth == null ||
        inputHeight == null ||
        sourceWidth == null ||
        sourceHeight == null ||
        inputWidth <= 0 ||
        inputHeight <= 0 ||
        sourceWidth <= 0 ||
        sourceHeight <= 0) {
      return null;
    }
    switch (preprocessing) {
      case 'letterbox_rgb01':
        final scaleX = _double(outputs['letterbox_scale_x']);
        final scaleY = _double(outputs['letterbox_scale_y']);
        final padX = _double(outputs['letterbox_pad_x']);
        final padY = _double(outputs['letterbox_pad_y']);
        if (scaleX == null ||
            scaleY == null ||
            padX == null ||
            padY == null ||
            !(scaleX > 0) ||
            !(scaleY > 0) ||
            padX < 0 ||
            padY < 0) {
          return null;
        }
        return YoloInputGeometry(
          preprocessing: preprocessing,
          inputWidth: inputWidth,
          inputHeight: inputHeight,
          sourceWidth: sourceWidth,
          sourceHeight: sourceHeight,
          scaleX: scaleX,
          scaleY: scaleY,
          padX: padX,
          padY: padY,
        );
      case 'stretch_rgb01':
        return YoloInputGeometry(
          preprocessing: preprocessing,
          inputWidth: inputWidth,
          inputHeight: inputHeight,
          sourceWidth: sourceWidth,
          sourceHeight: sourceHeight,
          scaleX: inputWidth / sourceWidth,
          scaleY: inputHeight / sourceHeight,
          padX: 0,
          padY: 0,
        );
      default:
        return null;
    }
  }

  /// Returns a copy of [output] whose box attributes are normalized
  /// source-frame `cx, cy, w, h`, clipped to the frame. A box that has no area
  /// inside the frame keeps its geometry but gets zero class scores, so it can
  /// never pass a confidence threshold. Returns [output] unchanged when its
  /// length does not match [numPredictions] x [attributes].
  List<double> toNormalizedSourceBoxes(
    List<double> output, {
    required int numPredictions,
    required int attributes,
    required String layout,
  }) {
    if (numPredictions <= 0 ||
        attributes < 5 ||
        output.length != numPredictions * attributes) {
      return output;
    }
    final channelsFirst =
        layout.trim().toLowerCase() == 'channels_first_yolov8';
    int index(int prediction, int attribute) => channelsFirst
        ? attribute * numPredictions + prediction
        : prediction * attributes + attribute;

    // Content size of the source frame inside the model input, in input px.
    final contentWidth = scaleX * sourceWidth;
    final contentHeight = scaleY * sourceHeight;
    final mapped = List<double>.of(output, growable: false);
    for (var prediction = 0; prediction < numPredictions; prediction++) {
      final cx = output[index(prediction, 0)];
      final cy = output[index(prediction, 1)];
      final w = output[index(prediction, 2)].abs();
      final h = output[index(prediction, 3)].abs();
      final x1 = ((cx - w / 2 - padX) / contentWidth).clamp(0.0, 1.0);
      final y1 = ((cy - h / 2 - padY) / contentHeight).clamp(0.0, 1.0);
      final x2 = ((cx + w / 2 - padX) / contentWidth).clamp(0.0, 1.0);
      final y2 = ((cy + h / 2 - padY) / contentHeight).clamp(0.0, 1.0);
      mapped[index(prediction, 0)] = (x1 + x2) / 2;
      mapped[index(prediction, 1)] = (y1 + y2) / 2;
      mapped[index(prediction, 2)] = x2 - x1;
      mapped[index(prediction, 3)] = y2 - y1;
      if (!(x2 > x1) || !(y2 > y1)) {
        for (var attribute = 4; attribute < attributes; attribute++) {
          mapped[index(prediction, attribute)] = 0;
        }
      }
    }
    return mapped;
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '');
  }

  static double? _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}
