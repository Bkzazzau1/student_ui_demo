import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:students_ui_demo/proctoring_demo/camera_frame_orientation.dart';
import 'package:students_ui_demo/proctoring_demo/camera_image_codec.dart';

const CameraDescription _front = CameraDescription(
  name: 'front',
  lensDirection: CameraLensDirection.front,
  sensorOrientation: 270,
);
const CameraDescription _back = CameraDescription(
  name: 'back',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 90,
);

/// A [width]x[height] iOS camera frame: left half red, right half blue.
CameraImage _iosFrame({required bool nv12, int width = 32, int height = 16}) {
  final planes = <Map<String, Object?>>[];
  if (nv12) {
    final luma = Uint8List(width * height);
    final chroma = Uint8List(width * height ~/ 2);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final red = x < width / 2;
        // BT.601 video range for pure red / pure blue.
        luma[y * width + x] = red ? 81 : 41;
        if (y.isEven && x.isEven) {
          final o = (y ~/ 2) * width + x;
          chroma[o] = red ? 90 : 240; // Cb
          chroma[o + 1] = red ? 240 : 110; // Cr
        }
      }
    }
    planes.add({
      'bytes': luma,
      'bytesPerRow': width,
      'bytesPerPixel': 1,
      'width': width,
      'height': height,
    });
    planes.add({
      'bytes': chroma,
      'bytesPerRow': width,
      'bytesPerPixel': 2,
      'width': width ~/ 2,
      'height': height ~/ 2,
    });
  } else {
    final bgra = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        final red = x < width / 2;
        bgra[i] = red ? 0 : 255;
        bgra[i + 2] = red ? 255 : 0;
        bgra[i + 3] = 255;
      }
    }
    planes.add({
      'bytes': bgra,
      'bytesPerRow': width * 4,
      'bytesPerPixel': 4,
      'width': width,
      'height': height,
    });
  }
  // ignore: deprecated_member_use
  return CameraImage.fromPlatformData(<String, Object?>{
    'format': nv12 ? 875704438 : 1111970369,
    'width': width,
    'height': height,
    'planes': planes,
  });
}

bool _isRed(img.Pixel pixel) => pixel.r > 180 && pixel.b < 90;
bool _isBlue(img.Pixel pixel) => pixel.b > 180 && pixel.r < 90;

void main() {
  group('CameraFrameOrientation', () {
    test('iOS frames are already upright; the front camera is unmirrored', () {
      expect(
        CameraFrameOrientation.of(_front, platform: TargetPlatform.iOS),
        const CameraFrameOrientation(
          rotationDegrees: 0,
          mirrorHorizontally: true,
        ),
      );
      expect(
        CameraFrameOrientation.of(_back, platform: TargetPlatform.iOS),
        CameraFrameOrientation.upright,
      );
    });

    test('Android frames are rotated by the sensor orientation', () {
      final front = CameraFrameOrientation.of(
        _front,
        platform: TargetPlatform.android,
      );
      expect(front.rotationDegrees, 270);
      expect(front.mirrorHorizontally, isFalse);
      expect(front.swapsWidthAndHeight, isTrue);
      expect(
        CameraFrameOrientation.of(null, platform: TargetPlatform.android),
        CameraFrameOrientation.upright,
      );
    });

    test('stream format: BGRA on iOS, YUV on Android, default on Windows', () {
      expect(
        CameraFrameOrientation.preferredStreamFormat(
          platform: TargetPlatform.iOS,
        ),
        ImageFormatGroup.bgra8888,
      );
      expect(
        CameraFrameOrientation.preferredStreamFormat(
          platform: TargetPlatform.android,
        ),
        ImageFormatGroup.yuv420,
      );
      expect(
        CameraFrameOrientation.preferredStreamFormat(
          platform: TargetPlatform.windows,
        ),
        isNull,
      );
    });
  });

  group('CameraImageCodec on iOS frames', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    for (final nv12 in [false, true]) {
      final name = nv12 ? 'NV12' : 'BGRA';

      test('$name frame decodes with the right colours', () {
        final jpeg = CameraImageCodec.toUprightJpeg(
          _iosFrame(nv12: nv12),
          sensorOrientation: 0,
        );
        final decoded = img.decodeJpg(jpeg!)!;
        expect(decoded.width, 32);
        expect(_isRed(decoded.getPixel(4, 8)), isTrue);
        expect(_isBlue(decoded.getPixel(27, 8)), isTrue);
      });

      test('$name front-camera mirror is undone', () {
        final jpeg = CameraImageCodec.toUprightJpeg(
          _iosFrame(nv12: nv12),
          sensorOrientation: 0,
          mirrorHorizontally: true,
        );
        final decoded = img.decodeJpg(jpeg!)!;
        expect(_isBlue(decoded.getPixel(4, 8)), isTrue);
        expect(_isRed(decoded.getPixel(27, 8)), isTrue);
      });
    }
  });
}
