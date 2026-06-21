import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

final class _FfiGazeHeadPoseDecision extends ffi.Struct {
  @ffi.Uint8()
  external int available;

  @ffi.Double()
  external double gazeX;

  @ffi.Double()
  external double gazeY;

  @ffi.Double()
  external double gazeZ;

  @ffi.Double()
  external double yawProxy;

  @ffi.Double()
  external double pitchProxy;

  @ffi.Double()
  external double rollProxy;

  @ffi.Double()
  external double confidence;

  @ffi.Uint8()
  external int stableHeadPose;

  @ffi.Uint8()
  external int lookingAway;

  @ffi.Uint32()
  external int labelCode;
}

typedef _NativeAnalyzeGaze = _FfiGazeHeadPoseDecision Function(
  ffi.Pointer<ffi.Uint8> planePtr,
  ffi.UintPtr planeLen,
  ffi.Uint32 width,
  ffi.Uint32 height,
  ffi.Uint32 bytesPerRow,
  ffi.Double previousYaw,
  ffi.Double previousPitch,
  ffi.Double previousRoll,
);

typedef _DartAnalyzeGaze = _FfiGazeHeadPoseDecision Function(
  ffi.Pointer<ffi.Uint8> planePtr,
  int planeLen,
  int width,
  int height,
  int bytesPerRow,
  double previousYaw,
  double previousPitch,
  double previousRoll,
);

class RustGazeHeadPoseRuntime {
  _DartAnalyzeGaze? _analyze;
  bool _loadAttempted = false;

  bool get available {
    _ensureLoaded();
    return _analyze != null;
  }

  RustGazeHeadPoseResult? analyse({
    required Uint8List lumaBytes,
    required int width,
    required int height,
    required int bytesPerRow,
    required double previousYaw,
    required double previousPitch,
    required double previousRoll,
  }) {
    _ensureLoaded();
    final analyze = _analyze;
    if (analyze == null ||
        lumaBytes.isEmpty ||
        width <= 0 ||
        height <= 0 ||
        bytesPerRow <= 0) {
      return null;
    }

    final pointer = calloc<ffi.Uint8>(lumaBytes.length);
    try {
      pointer.asTypedList(lumaBytes.length).setAll(0, lumaBytes);
      final decision = analyze(
        pointer,
        lumaBytes.length,
        width,
        height,
        bytesPerRow,
        previousYaw,
        previousPitch,
        previousRoll,
      );
      if (decision.available == 0) return null;
      return RustGazeHeadPoseResult(
        gazeX: decision.gazeX,
        gazeY: decision.gazeY,
        gazeZ: decision.gazeZ,
        yawProxy: decision.yawProxy,
        pitchProxy: decision.pitchProxy,
        rollProxy: decision.rollProxy,
        confidence: decision.confidence,
        stableHeadPose: decision.stableHeadPose != 0,
        lookingAway: decision.lookingAway != 0,
        label: _labelFromCode(decision.labelCode),
      );
    } finally {
      calloc.free(pointer);
    }
  }

  void _ensureLoaded() {
    if (_loadAttempted) return;
    _loadAttempted = true;
    for (final path in _libraryPathCandidates()) {
      try {
        final library = ffi.DynamicLibrary.open(path);
        _analyze = library
            .lookupFunction<_NativeAnalyzeGaze, _DartAnalyzeGaze>(
              'brain_core_analyze_gaze_head_pose_luma',
            );
        return;
      } catch (_) {
        _analyze = null;
      }
    }
  }

  List<String> _libraryPathCandidates() {
    if (Platform.isWindows) {
      return <String>[
        'brain_core.dll',
        'native/brain_core/target/release/brain_core.dll',
        '${File(Platform.resolvedExecutable).parent.path}/brain_core.dll',
      ];
    }
    if (Platform.isMacOS) {
      return <String>[
        'libbrain_core.dylib',
        'native/brain_core/target/release/libbrain_core.dylib',
        '${File(Platform.resolvedExecutable).parent.path}/libbrain_core.dylib',
      ];
    }
    return <String>[
      'libbrain_core.so',
      'native/brain_core/target/release/libbrain_core.so',
      '${File(Platform.resolvedExecutable).parent.path}/libbrain_core.so',
    ];
  }

  String _labelFromCode(int code) {
    return switch (code) {
      1 => 'possible_looking_away',
      2 => 'focused_forward',
      3 => 'head_motion_detected',
      _ => 'unknown',
    };
  }
}

class RustGazeHeadPoseResult {
  const RustGazeHeadPoseResult({
    required this.gazeX,
    required this.gazeY,
    required this.gazeZ,
    required this.yawProxy,
    required this.pitchProxy,
    required this.rollProxy,
    required this.confidence,
    required this.stableHeadPose,
    required this.lookingAway,
    required this.label,
  });

  final double gazeX;
  final double gazeY;
  final double gazeZ;
  final double yawProxy;
  final double pitchProxy;
  final double rollProxy;
  final double confidence;
  final bool stableHeadPose;
  final bool lookingAway;
  final String label;
}
