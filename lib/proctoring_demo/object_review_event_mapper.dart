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
    final normalized = _normalizeLabels(labels);
    if (normalized.isEmpty) return const <ObjectReviewEventDecision>[];

    final decisions = <ObjectReviewEventDecision>[];

    final phoneLabels = _matching(
      normalized,
      const <String>['phone', 'cell phone', 'mobile', 'smartphone'],
    );
    if (phoneLabels.isNotEmpty) {
      decisions.add(
        _decision(
          eventType: 'yolo_phone_detected',
          severity: 'warning',
          message: 'Phone-like object noticed in camera view.',
          labels: phoneLabels,
          source: source,
          target: target,
        ),
      );
    }

    final screenLabels = _matching(
      normalized,
      const <String>['laptop', 'monitor', 'tv monitor', 'screen', 'tablet'],
    );
    if (screenLabels.isNotEmpty) {
      decisions.add(
        _decision(
          eventType: 'yolo_extra_screen_detected',
          severity: 'warning',
          message: 'Extra screen-like object noticed in camera view.',
          labels: screenLabels,
          source: source,
          target: target,
        ),
      );
    }

    final paperLabels = _matching(
      normalized,
      const <String>['book', 'paper', 'notebook', 'notes', 'sheet'],
    );
    if (paperLabels.isNotEmpty) {
      decisions.add(
        _decision(
          eventType: 'yolo_book_or_paper_detected',
          severity: 'warning',
          message: 'Book or paper-like object noticed in camera view.',
          labels: paperLabels,
          source: source,
          target: target,
        ),
      );
    }

    final calculatorLabels = _matching(
      normalized,
      const <String>['calculator'],
    );
    if (calculatorLabels.isNotEmpty) {
      decisions.add(
        _decision(
          eventType: 'yolo_calculator_detected',
          severity: 'warning',
          message: 'Calculator-like object noticed in camera view.',
          labels: calculatorLabels,
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
    required List<String> labels,
    required String source,
    required String? target,
  }) {
    return ObjectReviewEventDecision(
      eventType: eventType,
      severity: severity,
      message: message,
      labels: labels,
      metadata: <String, Object?>{
        'source_component': source,
        if (target != null) 'scan_target': target,
        'matched_labels': labels,
      },
    );
  }

  List<String> _normalizeLabels(List<String> labels) {
    final normalized = <String>{};
    for (final label in labels) {
      final value = label
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[_\-]+'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ');
      if (value.isEmpty || value == 'background' || value == 'none') continue;
      normalized.add(value);
    }
    return normalized.toList()..sort();
  }

  List<String> _matching(List<String> labels, List<String> keywords) {
    return labels
        .where(
          (label) => keywords.any(
            (keyword) => label == keyword || label.contains(keyword),
          ),
        )
        .toList();
  }
}
