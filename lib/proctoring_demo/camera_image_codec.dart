import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

/// Converts a streamed camera frame (Android YUV420 / iOS BGRA) into an
/// upright JPEG the face pipeline can read, so identity checks can run on
/// the very frames a liveness or monitoring stream already captured.
abstract final class CameraImageCodec {
  static Uint8List? toUprightJpeg(
    CameraImage image, {
    required int sensorOrientation,
    int quality = 82,
  }) {
    if (image.width <= 0 || image.height <= 0 || image.planes.isEmpty) {
      return null;
    }
    final output = img.Image(width: image.width, height: image.height);
    if (image.format.group == ImageFormatGroup.yuv420 &&
        image.planes.length >= 3) {
      final yPlane = image.planes[0];
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];
      final uvPixelStride = uPlane.bytesPerPixel ?? 1;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final yi = y * yPlane.bytesPerRow + x;
          final ui = (y ~/ 2) * uPlane.bytesPerRow + (x ~/ 2) * uvPixelStride;
          final vi =
              (y ~/ 2) * vPlane.bytesPerRow +
              (x ~/ 2) * (vPlane.bytesPerPixel ?? uvPixelStride);
          if (yi >= yPlane.bytes.length ||
              ui >= uPlane.bytes.length ||
              vi >= vPlane.bytes.length) {
            continue;
          }
          final yy = yPlane.bytes[yi].toDouble();
          final uu = uPlane.bytes[ui] - 128.0;
          final vv = vPlane.bytes[vi] - 128.0;
          output.setPixelRgb(
            x,
            y,
            (yy + 1.402 * vv).round().clamp(0, 255),
            (yy - 0.344136 * uu - 0.714136 * vv).round().clamp(0, 255),
            (yy + 1.772 * uu).round().clamp(0, 255),
          );
        }
      }
    } else if (image.format.group == ImageFormatGroup.bgra8888) {
      final plane = image.planes.first;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final i = y * plane.bytesPerRow + x * 4;
          if (i + 2 >= plane.bytes.length) continue;
          output.setPixelRgb(
            x,
            y,
            plane.bytes[i + 2],
            plane.bytes[i + 1],
            plane.bytes[i],
          );
        }
      }
    } else {
      return null;
    }
    final orientation = sensorOrientation;
    final upright = orientation == 0
        ? output
        : img.copyRotate(output, angle: orientation);
    return Uint8List.fromList(img.encodeJpg(upright, quality: quality));
  }
}
