import 'e1_object_taxonomy.dart';

class ObjectReviewEventDecision {
  const ObjectReviewEventDecision({
    required this.eventType,
    required this.severity,
    required this.message,
    required this.labels,
    required this.metadata,
  });

  final String eventType;
  final String severity;
  final String message;
  final List<String> labels;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() => <String, Object?>{
    'event_type': eventType,
    'severity': severity,
    'message': message,
    'labels': labels,
    'metadata': metadata,
  };
}

class ObjectReviewEventMapper {
  const ObjectReviewEventMapper();

  List<ObjectReviewEventDecision> mapLabels(
    List<String> labels, {
    String source = 'native_scan_frame_review',
    String? target,
  }) {
    final resolutions = _resolveLabels(labels);
    if (resolutions.isEmpty) return const <ObjectReviewEventDecision>[];

    final decisions = <ObjectReviewEventDecision>[];

    final phoneLike = _matchingCanonical(
      resolutions,
      const <String>{'phone', 'remote'},
    );
    if (phoneLike.isNotEmpty) {
      decisions.add(
        _decision(
          eventType: 'yolo_phone_detected',
          severity: 'warning',
          message: 'Phone-like object noticed in camera view.',
          matches: phoneLike,
          source: source,
          target: target,
        ),
      );
    }

    final screens = _matchingCanonical(
      resolutions,
      const <String>{
        'laptop',
        'television',
        'monitor',
        'tablet',
        'screen_signal',
      },
    );
    if (screens.isNotEmpty) {
      decisions.add(
        _decision(
          eventType: 'yolo_extra_screen_detected',
          severity: 'warning',
          message: 'Extra screen-like object noticed in camera view.',
          matches: screens,
          source: source,
          target: target,
        ),
      );
    }

    final referenceMaterial = _matchingCanonical(
      resolutions,
      const <String>{'book', 'paper_note'},
    );
    if (referenceMaterial.isNotEmpty) {
      decisions.add(
        _decision(
          eventType: 'yolo_book_or_paper_detected',
          severity: 'warning',
          message: 'Book or paper-like object noticed in camera view.',
          matches: referenceMaterial,
          source: source,
          target: target,
        ),
      );
    }

    final calculator = _matchingCanonical(
      resolutions,
      const <String>{'calculator'},
    );
    if (calculator.isNotEmpty) {
      decisions.add(
        _decision(
          eventType: 'yolo_calculator_detected',
          severity: 'warning',
          message: 'Calculator-like object noticed in camera view.',
          matches: calculator,
          source: source,
          target: target,
        ),
      );
    }

    final smartwatch = _matchingCanonical(
      resolutions,
      const <String>{'smartwatch'},
    );
    if (smartwatch.isNotEmpty) {
      decisions.add(
        _decision(
          eventType: 'e1_smartwatch_detected',
          severity: 'warning',
          message: 'Smartwatch-like object noticed in camera view.',
          matches: smartwatch,
          source: source,
          target: target,
        ),
      );
    }

    final earbud = _matchingCanonical(
      resolutions,
      const <String>{'earbud'},
    );
    if (earbud.isNotEmpty) {
      decisions.add(
        _decision(
          eventType: 'e1_earbud_detected',
          severity: 'warning',
          message: 'Earbud-like object noticed in camera view.',
          matches: earbud,
          source: source,
          target: target,
        ),
      );
    }

    return decisions;
  }

  ObjectReviewEventDecision _decision({
    required String eventType,
    required String severity,
    required String message,
    required List<E1ObjectTaxonomyResolution> matches,
    required String source,
    required String? target,
  }) {
    final normalizedLabels = matches.map((item) => item.normalizedLabel).toSet()
      ..removeWhere((item) => item.isEmpty);
    final canonicalIds = matches.map((item) => item.canonicalObjectId).toSet();
    final coverage = matches.map((item) => item.coverage.wireValue).toSet();
    final groups = matches.map((item) => item.group).toSet();

    final labels = normalizedLabels.toList()..sort();
    final canonical = canonicalIds.toList()..sort();
    final coverageValues = coverage.toList()..sort();
    final groupValues = groups.toList()..sort();

    return ObjectReviewEventDecision(
      eventType: eventType,
      severity: severity,
      message: message,
      labels: labels,
      metadata: <String, Object?>{
        'source_component': source,
        if (target != null) 'scan_target': target,
        'matched_labels': labels,
        'taxonomy_version': E1ObjectTaxonomyV1.version,
        'canonical_object_ids': canonical,
        'object_groups': groupValues,
        'object_coverage': coverageValues,
        'specialist_required': matches.any(
          (item) => item.coverage == E1ObjectCoverage.specialistRequired,
        ),
      },
    );
  }

  List<E1ObjectTaxonomyResolution> _resolveLabels(List<String> labels) {
    final byKey = <String, E1ObjectTaxonomyResolution>{};
    for (final raw in labels) {
      final resolution = E1ObjectTaxonomyV1.resolve(raw);
      if (!resolution.isKnown) continue;
      final key =
          '${resolution.normalizedLabel}:${resolution.canonicalObjectId}:${resolution.coverage.wireValue}';
      byKey[key] = resolution;
    }
    final output = byKey.values.toList()
      ..sort((a, b) => a.normalizedLabel.compareTo(b.normalizedLabel));
    return output;
  }

  List<E1ObjectTaxonomyResolution> _matchingCanonical(
    List<E1ObjectTaxonomyResolution> resolutions,
    Set<String> canonicalIds,
  ) {
    return resolutions
        .where((item) => canonicalIds.contains(item.canonicalObjectId))
        .toList(growable: false);
  }
}
