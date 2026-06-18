import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

import 'proctoring_demo_models.dart';

class DemoEvidenceService {
  Directory? _scanDirectory;

  Directory? get scanDirectory => _scanDirectory;

  Future<Directory> startScan() async {
    final base = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}students_ui_demo_proctoring',
    );
    if (!base.existsSync()) {
      base.createSync(recursive: true);
    }
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final directory = Directory('${base.path}${Platform.pathSeparator}$stamp');
    directory.createSync(recursive: true);
    _scanDirectory = directory;
    return directory;
  }

  Future<String?> saveTargetFrame({
    required String target,
    required img.Image? decodedImage,
    required CameraImage? cameraImage,
  }) async {
    final directory = _scanDirectory ?? await startScan();
    final safeTarget = target
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+$'), '');
    final file = File(
      '${directory.path}${Platform.pathSeparator}$safeTarget.jpg',
    );
    final image = decodedImage ?? _cameraImageToLumaPreview(cameraImage);
    if (image == null) return null;
    await file.writeAsBytes(img.encodeJpg(image, quality: 82));
    return file.path;
  }

  Future<String> saveManifest({
    required List<DemoScanTarget> targets,
    required List<DemoCalibrationEntry> calibrationLog,
    required List<AgenticReviewEvent> reviewEvents,
    required String decision,
    required String frameSourceMode,
  }) async {
    final directory = _scanDirectory ?? await startScan();
    final file = File(
      '${directory.path}${Platform.pathSeparator}manifest.json',
    );
    final payload = <String, Object?>{
      'created_at': DateTime.now().toIso8601String(),
      'decision': decision,
      'frame_source_mode': frameSourceMode,
      'targets': targets
          .map(
            (target) => <String, Object?>{
              'name': target.name,
              'captured': target.captured,
              'frame_path': target.framePath,
              'labels': target.labels,
            },
          )
          .toList(),
      'calibration_log': calibrationLog.map((entry) => entry.toJson()).toList(),
      'security_review': reviewEvents
          .map(
            (event) => <String, String>{
              'title': event.title,
              'detail': event.detail,
              'severity': event.severity,
            },
          )
          .toList(),
    };
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
    return file.path;
  }

  img.Image? _cameraImageToLumaPreview(CameraImage? image) {
    if (image == null || image.planes.isEmpty) return null;
    final plane = image.planes.first;
    if (plane.bytes.isEmpty || image.width <= 0 || image.height <= 0) {
      return null;
    }
    final preview = img.Image(width: image.width, height: image.height);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final index = y * plane.bytesPerRow + x;
        final value = index < plane.bytes.length ? plane.bytes[index] : 0;
        preview.setPixelRgb(x, y, value, value, value);
      }
    }
    return preview;
  }
}
