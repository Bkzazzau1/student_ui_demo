import 'dart:async';

import 'package:camera/camera.dart';

class LiveCameraFrame {
  const LiveCameraFrame({
    required this.sequence,
    required this.owner,
    required this.purpose,
    required this.image,
    required this.capturedAt,
  });

  final int sequence;
  final String owner;
  final String purpose;
  final CameraImage image;
  final DateTime capturedAt;

  int get width => image.width;
  int get height => image.height;
  String get formatGroup => image.format.group.name;

  Map<String, Object?> toMetadata() => <String, Object?>{
        'frame_sequence': sequence,
        'frame_owner': owner,
        'frame_purpose': purpose,
        'frame_width': width,
        'frame_height': height,
        'frame_format': formatGroup,
        'captured_at': capturedAt.toUtc().toIso8601String(),
      };
}

/// Single in-process frame bus for the exam camera.
///
/// The live camera owner publishes processed frames here. Lightweight local
/// checks and future YOLO/object detection can subscribe without creating a
/// second camera controller.
class LiveCameraFrameBus {
  LiveCameraFrameBus._();

  static final LiveCameraFrameBus instance = LiveCameraFrameBus._();

  final StreamController<LiveCameraFrame> _controller =
      StreamController<LiveCameraFrame>.broadcast(sync: true);

  int _sequence = 0;
  LiveCameraFrame? _latestFrame;

  Stream<LiveCameraFrame> get frames => _controller.stream;
  LiveCameraFrame? get latestFrame => _latestFrame;
  int get latestSequence => _sequence;
  bool get hasListeners => _controller.hasListener;

  LiveCameraFrame publish({
    required String owner,
    required String purpose,
    required CameraImage image,
  }) {
    final frame = LiveCameraFrame(
      sequence: ++_sequence,
      owner: owner,
      purpose: purpose,
      image: image,
      capturedAt: DateTime.now(),
    );
    _latestFrame = frame;
    if (!_controller.isClosed) {
      _controller.add(frame);
    }
    return frame;
  }

  Map<String, Object?> currentState() => <String, Object?>{
        'latest_frame_sequence': _latestFrame?.sequence,
        'latest_frame_at': _latestFrame?.capturedAt.toUtc().toIso8601String(),
        'has_listeners': hasListeners,
      };
}
