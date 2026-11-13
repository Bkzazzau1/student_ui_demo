import 'dart:math' as math;
import 'dart:typed_data';

/// Face alignment for the SFace embedding model.
///
/// Five landmarks (eye centres, nose tip, mouth corners) are mapped onto the
/// ArcFace 112x112 template with a least-squares similarity transform, and
/// the face is resampled bilinearly. This must stay numerically equivalent
/// to `ai_runtime/face_identity_reference.py`, which the school system uses
/// to rebuild official templates; `test/face_alignment_test.dart` checks
/// both against the same golden fixture.
abstract final class FaceAlignment {
  static const int alignedSide = 112;

  static const List<math.Point<double>> arcFaceTemplate = <math.Point<double>>[
    math.Point<double>(38.2946, 51.6963),
    math.Point<double>(73.5318, 51.5014),
    math.Point<double>(56.0252, 71.7366),
    math.Point<double>(41.5493, 92.3655),
    math.Point<double>(70.7299, 92.2041),
  ];

  /// Eye centres from the eye corners (33/133 and 362/263), nose tip (1),
  /// mouth corners (61, 291). Null if any is missing.
  static List<math.Point<double>>? fivePoints(
    Map<int, math.Point<double>> points,
  ) {
    final required = <int>[33, 133, 362, 263, 1, 61, 291];
    if (required.any((index) => !points.containsKey(index))) return null;
    math.Point<double> mid(int a, int b) => math.Point<double>(
      (points[a]!.x + points[b]!.x) / 2,
      (points[a]!.y + points[b]!.y) / 2,
    );
    return <math.Point<double>>[
      mid(33, 133),
      mid(362, 263),
      points[1]!,
      points[61]!,
      points[291]!,
    ];
  }

  /// Least-squares similarity (rotation, uniform scale, translation; never
  /// a reflection) mapping [source] onto [target].
  static SimilarityTransform? similarityLeastSquares(
    List<math.Point<double>> source,
    List<math.Point<double>> target,
  ) {
    if (source.length != target.length || source.isEmpty) return null;
    final n = source.length;
    var sx = 0.0, sy = 0.0, tx = 0.0, ty = 0.0;
    for (var i = 0; i < n; i++) {
      sx += source[i].x;
      sy += source[i].y;
      tx += target[i].x;
      ty += target[i].y;
    }
    sx /= n;
    sy /= n;
    tx /= n;
    ty /= n;
    var norm = 0.0, dotSum = 0.0, crossSum = 0.0;
    for (var i = 0; i < n; i++) {
      final px = source[i].x - sx;
      final py = source[i].y - sy;
      final qx = target[i].x - tx;
      final qy = target[i].y - ty;
      norm += px * px + py * py;
      dotSum += px * qx + py * qy;
      crossSum += px * qy - py * qx;
    }
    if (norm < 1e-9) return null;
    final a = dotSum / norm;
    final b = crossSum / norm;
    return SimilarityTransform(
      a: a,
      b: b,
      tx: tx - (a * sx - b * sy),
      ty: ty - (b * sx + a * sy),
    );
  }

  /// Resamples [rgb] (width x height, 3 bytes per pixel) through [transform]
  /// into an [alignedSide] square. Outside the source is black; values round
  /// half up.
  static Uint8List? warpBilinear(
    Uint8List rgb,
    int width,
    int height,
    SimilarityTransform transform, {
    int side = alignedSide,
  }) {
    final a = transform.a;
    final b = transform.b;
    final det = a * a + b * b;
    if (det < 1e-12 || rgb.length < width * height * 3) return null;
    final output = Uint8List(side * side * 3);
    var offset = 0;
    for (var y = 0; y < side; y++) {
      final dy = y - transform.ty;
      for (var x = 0; x < side; x++) {
        final dx = x - transform.tx;
        final srcX = (a * dx + b * dy) / det;
        final srcY = (-b * dx + a * dy) / det;
        final x0 = srcX.floor();
        final y0 = srcY.floor();
        final fx = srcX - x0;
        final fy = srcY - y0;
        for (var c = 0; c < 3; c++) {
          double sample(int sy, int sx) =>
              sx < 0 || sx >= width || sy < 0 || sy >= height
              ? 0.0
              : rgb[(sy * width + sx) * 3 + c].toDouble();
          final top = sample(y0, x0) * (1 - fx) + sample(y0, x0 + 1) * fx;
          final bottom =
              sample(y0 + 1, x0) * (1 - fx) + sample(y0 + 1, x0 + 1) * fx;
          final value = top * (1 - fy) + bottom * fy;
          output[offset++] = (value + 0.5).floor().clamp(0, 255);
        }
      }
    }
    return output;
  }
}

class SimilarityTransform {
  const SimilarityTransform({
    required this.a,
    required this.b,
    required this.tx,
    required this.ty,
  });

  /// Maps source (x, y) to (a*x - b*y + tx, b*x + a*y + ty).
  final double a;
  final double b;
  final double tx;
  final double ty;

  double get scale => math.sqrt(a * a + b * b);
}
