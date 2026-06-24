import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class SnapshotGazeFallbackResult {
  const SnapshotGazeFallbackResult({
    required this.ready,
    required this.centerX,
    required this.centerY,
    required this.baselineX,
    required this.baselineY,
    required this.shiftX,
    required this.shiftY,
    required this.shiftScore,
    required this.asymmetry,
    required this.baselineAsymmetry,
    required this.asymmetryShift,
    required this.horizontalSpread,
    required this.verticalSpread,
    required this.profileScore,
    required this.personCount,
    required this.multiplePeopleLikely,
    required this.headPoseShiftLikely,
    required this.label,
  });

  final bool ready;
  final double centerX;
  final double centerY;
  final double baselineX;
  final double baselineY;
  final double shiftX;
  final double shiftY;
  final double shiftScore;
  final double asymmetry;
  final double baselineAsymmetry;
  final double asymmetryShift;
  final double horizontalSpread;
  final double verticalSpread;
  final double profileScore;
  final int personCount;
  final bool multiplePeopleLikely;
  final bool headPoseShiftLikely;
  final String label;

  Map<String, Object?> toJson() => <String, Object?>{
        'ready': ready,
        'center_x': centerX,
        'center_y': centerY,
        'baseline_x': baselineX,
        'baseline_y': baselineY,
        'shift_x': shiftX,
        'shift_y': shiftY,
        'shift_score': shiftScore,
        'asymmetry': asymmetry,
        'baseline_asymmetry': baselineAsymmetry,
        'asymmetry_shift': asymmetryShift,
        'horizontal_spread': horizontalSpread,
        'vertical_spread': verticalSpread,
        'profile_score': profileScore,
        'person_count': personCount,
        'multiple_people_likely': multiplePeopleLikely,
        'head_pose_shift_likely': headPoseShiftLikely,
        'label': label,
        'source': 'snapshot_fallback',
      };
}

class SnapshotGazeFallbackService {
  static const int _baselineWindow = 3;
  final List<_HeadSignal> _baselineSamples = <_HeadSignal>[];
  _HeadSignal? _baseline;

  SnapshotGazeFallbackResult? analyseJpeg(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final resized = img.copyResize(decoded, width: 128);
    final width = resized.width;
    final height = resized.height;
    if (width < 32 || height < 24) return null;

    final signal = _estimateHeadSignal(resized);
    if (signal == null) return null;

    if (_baseline == null) {
      _baselineSamples.add(signal);
      if (_baselineSamples.length >= _baselineWindow) {
        _baseline = _HeadSignal(
          _baselineSamples.map((item) => item.x).reduce((a, b) => a + b) /
              _baselineSamples.length,
          _baselineSamples.map((item) => item.y).reduce((a, b) => a + b) /
              _baselineSamples.length,
          _baselineSamples
                  .map((item) => item.asymmetry)
                  .reduce((a, b) => a + b) /
              _baselineSamples.length,
          horizontalSpread: _baselineSamples
                  .map((item) => item.horizontalSpread)
                  .reduce((a, b) => a + b) /
              _baselineSamples.length,
          verticalSpread: _baselineSamples
                  .map((item) => item.verticalSpread)
                  .reduce((a, b) => a + b) /
              _baselineSamples.length,
          profileScore: _baselineSamples
                  .map((item) => item.profileScore)
                  .reduce((a, b) => a + b) /
              _baselineSamples.length,
          personCount: 1,
          multiplePeopleLikely: false,
        );
      }
      return SnapshotGazeFallbackResult(
        ready: false,
        centerX: signal.x,
        centerY: signal.y,
        baselineX: _baseline?.x ?? signal.x,
        baselineY: _baseline?.y ?? signal.y,
        shiftX: 0,
        shiftY: 0,
        shiftScore: 0,
        asymmetry: signal.asymmetry,
        baselineAsymmetry: _baseline?.asymmetry ?? signal.asymmetry,
        asymmetryShift: 0,
        horizontalSpread: signal.horizontalSpread,
        verticalSpread: signal.verticalSpread,
        profileScore: signal.profileScore,
        personCount: signal.personCount,
        multiplePeopleLikely: signal.multiplePeopleLikely,
        headPoseShiftLikely: false,
        label: signal.multiplePeopleLikely
            ? 'possible_multiple_people'
            : 'learning_head_position',
      );
    }

    final baseline = _baseline!;
    final shiftX = signal.x - baseline.x;
    final shiftY = signal.y - baseline.y;
    final shiftScore = math.sqrt((shiftX * shiftX) + (shiftY * shiftY));
    final asymmetryShift = signal.asymmetry - baseline.asymmetry;
    final spreadShift = signal.horizontalSpread - baseline.horizontalSpread;
    final profileTurnLikely = asymmetryShift.abs() >= 0.16 ||
        signal.asymmetry.abs() >= 0.30 ||
        signal.profileScore >= 0.30 ||
        spreadShift.abs() >= 0.08;
    final headPoseShiftLikely = shiftX.abs() >= 0.14 ||
        shiftY.abs() >= 0.14 ||
        shiftScore >= 0.18 ||
        profileTurnLikely;
    final multiplePeopleLikely = signal.multiplePeopleLikely && signal.personCount >= 2;

    return SnapshotGazeFallbackResult(
      ready: true,
      centerX: signal.x,
      centerY: signal.y,
      baselineX: baseline.x,
      baselineY: baseline.y,
      shiftX: shiftX,
      shiftY: shiftY,
      shiftScore: shiftScore,
      asymmetry: signal.asymmetry,
      baselineAsymmetry: baseline.asymmetry,
      asymmetryShift: asymmetryShift,
      horizontalSpread: signal.horizontalSpread,
      verticalSpread: signal.verticalSpread,
      profileScore: signal.profileScore,
      personCount: signal.personCount,
      multiplePeopleLikely: multiplePeopleLikely,
      headPoseShiftLikely: headPoseShiftLikely,
      label: multiplePeopleLikely
          ? 'possible_multiple_people'
          : headPoseShiftLikely
              ? 'head_or_gaze_shift_detected'
              : 'head_position_stable',
    );
  }

  _HeadSignal? _estimateHeadSignal(img.Image image) {
    final width = image.width;
    final height = image.height;
    final xStart = (width * 0.05).round();
    final xEnd = (width * 0.95).round();
    final yStart = (height * 0.06).round();
    final yEnd = (height * 0.78).round();
    final bins = List<double>.filled(16, 0.0);

    var weightedX = 0.0;
    var weightedY = 0.0;
    var totalWeight = 0.0;
    var leftWeight = 0.0;
    var rightWeight = 0.0;
    var weightedX2 = 0.0;
    var weightedY2 = 0.0;
    var skinLeft = 0.0;
    var skinRight = 0.0;
    var skinWeight = 0.0;
    var darkLeft = 0.0;
    var darkRight = 0.0;

    for (var y = yStart + 1; y < yEnd - 1; y += 2) {
      for (var x = xStart + 1; x < xEnd - 1; x += 2) {
        final pixel = image.getPixel(x, y);
        final left = image.getPixel(x - 1, y);
        final right = image.getPixel(x + 1, y);
        final up = image.getPixel(x, y - 1);
        final down = image.getPixel(x, y + 1);

        final luma = _luma(pixel);
        final edge = ((_luma(left) - _luma(right)).abs() +
                (_luma(up) - _luma(down)).abs()) /
            2.0;
        final saturation = _saturation(pixel);
        final skinLike = saturation >= 0.09 && saturation <= 0.78 && luma >= 26 && luma <= 238;
        final darkFeature = luma < 105 && edge > 8;
        if (!skinLike && !darkFeature) continue;

        final yBias = 1.0 - ((y / height) - 0.38).abs().clamp(0.0, 0.82);
        final xBias = 1.0 - ((x / width) - 0.5).abs().clamp(0.0, 0.5);
        final weight = (edge * 0.62) +
            (skinLike ? 30.0 : 0.0) +
            (darkFeature ? 12.0 : 0.0);
        final normalizedX = x / width;
        final normalizedY = y / height;
        final finalWeight = weight * yBias * xBias;
        weightedX += normalizedX * finalWeight;
        weightedY += normalizedY * finalWeight;
        weightedX2 += normalizedX * normalizedX * finalWeight;
        weightedY2 += normalizedY * normalizedY * finalWeight;
        totalWeight += finalWeight;
        final binIndex = ((x / width) * bins.length).floor().clamp(0, bins.length - 1);
        bins[binIndex] += finalWeight;
        if (x < width / 2) {
          leftWeight += finalWeight;
          if (skinLike) skinLeft += finalWeight;
          if (darkFeature) darkLeft += finalWeight;
        } else {
          rightWeight += finalWeight;
          if (skinLike) skinRight += finalWeight;
          if (darkFeature) darkRight += finalWeight;
        }
        if (skinLike) skinWeight += finalWeight;
      }
    }

    if (totalWeight < 80) return null;
    final asymmetry = ((rightWeight - leftWeight) / totalWeight).clamp(-1.0, 1.0);
    final meanX = (weightedX / totalWeight).clamp(0.0, 1.0);
    final meanY = (weightedY / totalWeight).clamp(0.0, 1.0);
    final horizontalSpread =
        math.sqrt(math.max(0.0, (weightedX2 / totalWeight) - (meanX * meanX)));
    final verticalSpread =
        math.sqrt(math.max(0.0, (weightedY2 / totalWeight) - (meanY * meanY)));
    final skinAsymmetry = skinWeight <= 0
        ? 0.0
        : ((skinRight - skinLeft) / skinWeight).clamp(-1.0, 1.0);
    final featureAsymmetry =
        ((darkRight - darkLeft) / math.max(1.0, darkLeft + darkRight))
            .clamp(-1.0, 1.0);
    final narrowFaceSignal = (0.17 - horizontalSpread).clamp(0.0, 0.17) / 0.17;
    final profileScore =
        ((skinAsymmetry.abs() * 0.55) + (featureAsymmetry.abs() * 0.25) + (narrowFaceSignal * 0.20))
            .clamp(0.0, 1.0);
    final personCount = _estimateSeparatedPersonClusters(bins, totalWeight);
    return _HeadSignal(
      meanX,
      meanY,
      asymmetry,
      horizontalSpread: horizontalSpread,
      verticalSpread: verticalSpread,
      profileScore: profileScore,
      personCount: personCount,
      multiplePeopleLikely: personCount >= 2,
    );
  }

  int _estimateSeparatedPersonClusters(List<double> bins, double totalWeight) {
    if (bins.isEmpty || totalWeight <= 0) return 1;
    final strongest = bins.reduce(math.max);
    if (strongest <= 0) return 1;
    final threshold = math.max(totalWeight * 0.085, strongest * 0.46);
    final candidates = <_ClusterCandidate>[];
    var inCluster = false;
    var clusterWeight = 0.0;
    var weightedIndex = 0.0;
    var clusterWidth = 0;
    var startIndex = 0;

    for (var i = 0; i < bins.length; i++) {
      final weight = bins[i];
      if (weight >= threshold) {
        if (!inCluster) {
          inCluster = true;
          startIndex = i;
        }
        clusterWeight += weight;
        weightedIndex += weight * i;
        clusterWidth++;
      } else if (inCluster) {
        _addClusterCandidate(
          candidates,
          clusterWeight,
          weightedIndex,
          clusterWidth,
          startIndex,
          i - 1,
          strongest,
          threshold,
        );
        inCluster = false;
        clusterWeight = 0.0;
        weightedIndex = 0.0;
        clusterWidth = 0;
      }
    }
    if (inCluster) {
      _addClusterCandidate(
        candidates,
        clusterWeight,
        weightedIndex,
        clusterWidth,
        startIndex,
        bins.length - 1,
        strongest,
        threshold,
      );
    }

    if (candidates.length < 2) return 1;
    candidates.sort((a, b) => b.weight.compareTo(a.weight));
    final primary = candidates.first;
    for (final candidate in candidates.skip(1)) {
      final separated = (candidate.center - primary.center).abs() >= 4.0;
      final strongEnough = candidate.weight >= primary.weight * 0.62 &&
          candidate.weight >= strongest * 0.72;
      if (separated && strongEnough) return 2;
    }
    return 1;
  }

  void _addClusterCandidate(
    List<_ClusterCandidate> candidates,
    double clusterWeight,
    double weightedIndex,
    int clusterWidth,
    int startIndex,
    int endIndex,
    double strongest,
    double threshold,
  ) {
    if (clusterWidth < 1) return;
    if (clusterWeight < threshold * 1.75) return;
    if (clusterWeight < strongest * 0.70) return;
    candidates.add(
      _ClusterCandidate(
        center: weightedIndex / clusterWeight,
        weight: clusterWeight,
        startIndex: startIndex,
        endIndex: endIndex,
      ),
    );
  }

  double _luma(img.Pixel pixel) {
    return (0.299 * pixel.r) + (0.587 * pixel.g) + (0.114 * pixel.b);
  }

  double _saturation(img.Pixel pixel) {
    final r = pixel.r / 255.0;
    final g = pixel.g / 255.0;
    final b = pixel.b / 255.0;
    final maxValue = math.max(r, math.max(g, b));
    final minValue = math.min(r, math.min(g, b));
    if (maxValue == 0) return 0;
    return (maxValue - minValue) / maxValue;
  }
}

class _HeadSignal {
  const _HeadSignal(
    this.x,
    this.y,
    this.asymmetry, {
    required this.horizontalSpread,
    required this.verticalSpread,
    required this.profileScore,
    required this.personCount,
    required this.multiplePeopleLikely,
  });

  final double x;
  final double y;
  final double asymmetry;
  final double horizontalSpread;
  final double verticalSpread;
  final double profileScore;
  final int personCount;
  final bool multiplePeopleLikely;
}

class _ClusterCandidate {
  const _ClusterCandidate({
    required this.center,
    required this.weight,
    required this.startIndex,
    required this.endIndex,
  });

  final double center;
  final double weight;
  final int startIndex;
  final int endIndex;
}
