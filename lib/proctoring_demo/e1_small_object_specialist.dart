import 'e1_object_taxonomy.dart';
import 'model_event_v1.dart';

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

/// A normalized full-frame rectangle used only to route specialist inference.
///
/// An ROI is not evidence that an object exists. It only says which bounded
/// part of the source frame is worth inspecting at higher effective detail.
class E1NormalizedRoi {
  const E1NormalizedRoi({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  bool get isValid =>
      x.isFinite &&
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

  double get right => x + width;
  double get bottom => y + height;
  double get area => width * height;

  Map<String, double> toBoundingBox() => <String, double>{
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };

  static E1NormalizedRoi? tryFrom(Object? value) {
    if (value is! Map) return null;
    final box = Map<Object?, Object?>.from(value);
    final x = _readDouble(box['x']);
    final y = _readDouble(box['y']);
    final width = _readDouble(box['width']);
    final height = _readDouble(box['height']);
    if (x == null || y == null || width == null || height == null) return null;
    final roi = E1NormalizedRoi(x: x, y: y, width: width, height: height);
    return roi.isValid ? roi : null;
  }

  static double? _readDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}

class E1SpecialistRoiHint {
  const E1SpecialistRoiHint({
    required this.strategy,
    this.anchorCanonicalObjectId,
    this.boundingBox,
  });

  /// Examples: `person_head_earbud`, `person_arm_watch`, and
  /// `desk_anchor_union`. This is only a routing hint; it is not evidence that
  /// a target object exists.
  final String strategy;
  final String? anchorCanonicalObjectId;

  /// Normalized full-frame coordinates: x, y, width, height.
  final Map<String, double>? boundingBox;

  E1NormalizedRoi? get roi => E1NormalizedRoi.tryFrom(boundingBox);
  bool get hasValidBoundingBox => roi != null;
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
      targets.isNotEmpty &&
      roiHint.strategy.trim().isNotEmpty &&
      roiHint.hasValidBoundingBox;
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
    return E1NormalizedRoi.tryFrom(boundingBox) != null;
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

class _E1GeometryAnchor {
  const _E1GeometryAnchor({
    required this.canonicalObjectId,
    required this.roi,
    required this.confidence,
  });

  final String canonicalObjectId;
  final E1NormalizedRoi roi;
  final double? confidence;
}

/// Plans *where specialist inference would be useful* from formal base E1
/// geometry. It never claims a specialist object is present.
class E1SmallObjectCascadePlanner {
  const E1SmallObjectCascadePlanner({this.maxPersonAnchors = 2});

  final int maxPersonAnchors;

  List<E1SmallObjectSpecialistRequest> plan({
    required String sessionId,
    required int? sourceFrameId,
    required int captureTimestampNs,
    required int imageWidth,
    required int imageHeight,
    required Iterable<ModelEventV1Payload> baseEvents,
  }) {
    if (sessionId.trim().isEmpty ||
        captureTimestampNs < 0 ||
        imageWidth <= 0 ||
        imageHeight <= 0 ||
        maxPersonAnchors <= 0) {
      return const <E1SmallObjectSpecialistRequest>[];
    }

    final anchors = baseEvents
        .map(
          (event) => _anchorFromEvent(
            event,
            sessionId: sessionId,
            sourceFrameId: sourceFrameId,
            captureTimestampNs: captureTimestampNs,
          ),
        )
        .whereType<_E1GeometryAnchor>()
        .toList(growable: false);

    final requests = <E1SmallObjectSpecialistRequest>[];
    final people = anchors
        .where((anchor) => anchor.canonicalObjectId == 'person')
        .toList(growable: false)
      ..sort(_compareAnchors);

    for (final person in people.take(maxPersonAnchors)) {
      final earRoi = _personEarRoi(person.roi);
      final watchRoi = _personWatchRoi(person.roi);
      if (earRoi != null) {
        requests.add(
          E1SmallObjectSpecialistRequest(
            sessionId: sessionId,
            sourceFrameId: sourceFrameId,
            captureTimestampNs: captureTimestampNs,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            targets: const <E1SmallObjectTarget>{E1SmallObjectTarget.earbud},
            reason: 'person_geometry_available_for_earbud_specialist',
            roiHint: E1SpecialistRoiHint(
              strategy: 'person_head_earbud',
              anchorCanonicalObjectId: 'person',
              boundingBox: earRoi.toBoundingBox(),
            ),
          ),
        );
      }
      if (watchRoi != null) {
        requests.add(
          E1SmallObjectSpecialistRequest(
            sessionId: sessionId,
            sourceFrameId: sourceFrameId,
            captureTimestampNs: captureTimestampNs,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            targets: const <E1SmallObjectTarget>{E1SmallObjectTarget.smartwatch},
            reason: 'person_geometry_available_for_watch_specialist',
            roiHint: E1SpecialistRoiHint(
              strategy: 'person_arm_watch',
              anchorCanonicalObjectId: 'person',
              boundingBox: watchRoi.toBoundingBox(),
            ),
          ),
        );
      }
    }

    const deskAnchorIds = <String>{'book', 'laptop', 'keyboard', 'mouse'};
    final deskAnchors = anchors
        .where((anchor) => deskAnchorIds.contains(anchor.canonicalObjectId))
        .map((anchor) => anchor.roi)
        .toList(growable: false);
    final deskRoi = _deskUnionRoi(deskAnchors);
    if (deskRoi != null) {
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
          reason: 'desk_geometry_available_for_small_object_specialist',
          roiHint: E1SpecialistRoiHint(
            strategy: 'desk_anchor_union',
            anchorCanonicalObjectId: 'desk_context',
            boundingBox: deskRoi.toBoundingBox(),
          ),
        ),
      );
    }

    return List<E1SmallObjectSpecialistRequest>.unmodifiable(requests);
  }

  _E1GeometryAnchor? _anchorFromEvent(
    ModelEventV1Payload event, {
    required String sessionId,
    required int? sourceFrameId,
    required int captureTimestampNs,
  }) {
    if (event.sessionId != sessionId ||
        event.sourceFrameId != sourceFrameId ||
        event.captureTimestampNs != captureTimestampNs ||
        event.geometry?.coordinateSpace != 'normalized_frame') {
      return null;
    }
    final canonicalObjectId =
        event.metadata['canonical_object_id']?.toString().trim() ?? '';
    if (canonicalObjectId.isEmpty || canonicalObjectId == 'unknown') return null;
    final roi = E1NormalizedRoi.tryFrom(event.geometry?.boundingBox);
    if (roi == null) return null;
    return _E1GeometryAnchor(
      canonicalObjectId: canonicalObjectId,
      roi: roi,
      confidence: event.confidence,
    );
  }

  int _compareAnchors(_E1GeometryAnchor left, _E1GeometryAnchor right) {
    final confidenceOrder = (right.confidence ?? -1.0).compareTo(
      left.confidence ?? -1.0,
    );
    if (confidenceOrder != 0) return confidenceOrder;
    return right.roi.area.compareTo(left.roi.area);
  }

  E1NormalizedRoi? _personEarRoi(E1NormalizedRoi person) {
    return _clipBounds(
      left: person.x - person.width * 0.12,
      top: person.y - person.height * 0.05,
      right: person.right + person.width * 0.12,
      bottom: person.y + person.height * 0.46,
    );
  }

  E1NormalizedRoi? _personWatchRoi(E1NormalizedRoi person) {
    return _clipBounds(
      left: person.x - person.width * 0.18,
      top: person.y + person.height * 0.25,
      right: person.right + person.width * 0.18,
      bottom: person.bottom + person.height * 0.05,
    );
  }

  E1NormalizedRoi? _deskUnionRoi(List<E1NormalizedRoi> anchors) {
    if (anchors.isEmpty) return null;
    var left = anchors.first.x;
    var top = anchors.first.y;
    var right = anchors.first.right;
    var bottom = anchors.first.bottom;
    for (final anchor in anchors.skip(1)) {
      if (anchor.x < left) left = anchor.x;
      if (anchor.y < top) top = anchor.y;
      if (anchor.right > right) right = anchor.right;
      if (anchor.bottom > bottom) bottom = anchor.bottom;
    }
    final width = right - left;
    final height = bottom - top;
    return _clipBounds(
      left: left - width * 0.25,
      top: top - height * 0.35,
      right: right + width * 0.25,
      bottom: bottom + height * 0.35,
    );
  }

  E1NormalizedRoi? _clipBounds({
    required double left,
    required double top,
    required double right,
    required double bottom,
  }) {
    final clippedLeft = left.clamp(0.0, 1.0).toDouble();
    final clippedTop = top.clamp(0.0, 1.0).toDouble();
    final clippedRight = right.clamp(0.0, 1.0).toDouble();
    final clippedBottom = bottom.clamp(0.0, 1.0).toDouble();
    final roi = E1NormalizedRoi(
      x: clippedLeft,
      y: clippedTop,
      width: clippedRight - clippedLeft,
      height: clippedBottom - clippedTop,
    );
    return roi.isValid ? roi : null;
  }
}
