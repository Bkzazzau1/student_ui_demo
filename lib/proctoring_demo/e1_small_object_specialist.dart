import 'e1_object_taxonomy.dart';

/// The exam-relevant small-object targets that are intentionally not claimed
/// by the current COCO YOLO development baseline.
enum E1SmallObjectTarget {
  smartwatch,
  earbud,
  tablet,
  paperNote,
  calculator,
}

extension E1SmallObjectTargetWireValue on E1SmallObjectTarget {
  String get canonicalObjectId {
    switch (this) {
      case E1SmallObjectTarget.smartwatch:
        return 'smartwatch';
      case E1SmallObjectTarget.earbud:
        return 'earbud';
      case E1SmallObjectTarget.tablet:
        return 'tablet';
      case E1SmallObjectTarget.paperNote:
        return 'paper_note';
      case E1SmallObjectTarget.calculator:
        return 'calculator';
    }
  }
}

class E1SpecialistRoiHint {
  const E1SpecialistRoiHint({
    required this.strategy,
    this.anchorCanonicalObjectId,
    this.boundingBox,
  });

  /// Examples: `person_relative_wearable`, `desk_relative_small_object`,
  /// `full_frame_periodic`. This is only a routing hint; it is not evidence that
  /// a target object exists.
  final String strategy;
  final String? anchorCanonicalObjectId;

  /// Optional normalized frame coordinates: x, y, width, height.
  final Map<String, double>? boundingBox;
}

class E1SmallObjectSpecialistRequest {
  const E1SmallObjectSpecialistRequest({
    required this.sessionId,
    required this.sourceFrameId,
    required this.captureTimestampNs,
    required this.imageWidth,
    required this.imageHeight,
    required this.targets,
    required this.reason,
    required this.roiHint,
  });

  final String sessionId;
  final int? sourceFrameId;
  final int captureTimestampNs;
  final int imageWidth;
  final int imageHeight;
  final Set<E1SmallObjectTarget> targets;
  final String reason;
  final E1SpecialistRoiHint roiHint;

  bool get isValid =>
      sessionId.trim().isNotEmpty &&
      captureTimestampNs >= 0 &&
      imageWidth > 0 &&
      imageHeight > 0 &&
      targets.isNotEmpty;
}

class E1SmallObjectSpecialistObservation {
  const E1SmallObjectSpecialistObservation({
    required this.canonicalObjectId,
    required this.confidence,
    required this.boundingBox,
    required this.modelId,
    required this.modelVersion,
    required this.sourceFrameId,
    required this.captureTimestampNs,
    required this.inferenceTimestampNs,
  });

  final String canonicalObjectId;
  final double confidence;
  final Map<String, double> boundingBox;
  final String modelId;
  final String modelVersion;
  final int? sourceFrameId;
  final int captureTimestampNs;
  final int inferenceTimestampNs;

  /// Specialist outputs must remain within the declared specialist taxonomy,
  /// carry real model provenance, and respect capture-before-inference time.
  bool get isValid {
    if (!E1ObjectTaxonomyV1.specialistCanonicalIds.contains(
      canonicalObjectId,
    )) {
      return false;
    }
    if (!confidence.isFinite || confidence < 0.0 || confidence > 1.0) {
      return false;
    }
    if (modelId.trim().isEmpty || modelVersion.trim().isEmpty) return false;
    if (captureTimestampNs < 0 || inferenceTimestampNs < captureTimestampNs) {
      return false;
    }
    final x = boundingBox['x'];
    final y = boundingBox['y'];
    final width = boundingBox['width'];
    final height = boundingBox['height'];
    if (x == null || y == null || width == null || height == null) return false;
    return x.isFinite &&
        y.isFinite &&
        width.isFinite &&
        height.isFinite &&
        x >= 0.0 &&
        y >= 0.0 &&
        width > 0.0 &&
        height > 0.0 &&
        x <= 1.0 &&
        y <= 1.0 &&
        x + width <= 1.0001 &&
        y + height <= 1.0001;
  }
}

/// Production implementations must run locally on the candidate device.
///
/// No cloud/foundation model is permitted on this live runtime interface.
abstract interface class E1SmallObjectSpecialist {
  Future<List<E1SmallObjectSpecialistObservation>> infer(
    E1SmallObjectSpecialistRequest request,
  );
}

/// Plans *where specialist inference would be useful* from base E1 evidence.
/// It never claims a specialist object is present.
class E1SmallObjectCascadePlanner {
  const E1SmallObjectCascadePlanner();

  List<E1SmallObjectSpecialistRequest> plan({
    required String sessionId,
    required int? sourceFrameId,
    required int captureTimestampNs,
    required int imageWidth,
    required int imageHeight,
    required Iterable<String> baseLabels,
  }) {
    final canonical = baseLabels
        .map(E1ObjectTaxonomyV1.resolve)
        .where((item) => item.isKnown)
        .map((item) => item.canonicalObjectId)
        .toSet();

    final requests = <E1SmallObjectSpecialistRequest>[];
    if (canonical.contains('person')) {
      requests.add(
        E1SmallObjectSpecialistRequest(
          sessionId: sessionId,
          sourceFrameId: sourceFrameId,
          captureTimestampNs: captureTimestampNs,
          imageWidth: imageWidth,
          imageHeight: imageHeight,
          targets: const <E1SmallObjectTarget>{
            E1SmallObjectTarget.smartwatch,
            E1SmallObjectTarget.earbud,
          },
          reason: 'person_anchor_available_for_wearable_specialist',
          roiHint: const E1SpecialistRoiHint(
            strategy: 'person_relative_wearable',
            anchorCanonicalObjectId: 'person',
          ),
        ),
      );
    }

    const deskAnchors = <String>{'book', 'laptop', 'keyboard', 'mouse'};
    if (canonical.any(deskAnchors.contains)) {
      requests.add(
        E1SmallObjectSpecialistRequest(
          sessionId: sessionId,
          sourceFrameId: sourceFrameId,
          captureTimestampNs: captureTimestampNs,
          imageWidth: imageWidth,
          imageHeight: imageHeight,
          targets: const <E1SmallObjectTarget>{
            E1SmallObjectTarget.tablet,
            E1SmallObjectTarget.paperNote,
            E1SmallObjectTarget.calculator,
          },
          reason: 'desk_anchor_available_for_small_object_specialist',
          roiHint: const E1SpecialistRoiHint(
            strategy: 'desk_relative_small_object',
          ),
        ),
      );
    }

    return List<E1SmallObjectSpecialistRequest>.unmodifiable(requests);
  }
}
