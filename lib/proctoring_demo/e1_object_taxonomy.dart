/// Stable exam-object taxonomy used by E1 policy and specialist routing.
///
/// This taxonomy intentionally separates a canonical object identity from the
/// label emitted by any particular detector. The current YOLO development
/// baseline is COCO-based, so classes absent from that model are marked as
/// requiring a specialist rather than being treated as if the base detector
/// could already observe them.
enum E1ObjectCoverage {
  baseDetector,
  specialistRequired,
  derivedSignal,
  unknown,
}

extension E1ObjectCoverageWireValue on E1ObjectCoverage {
  String get wireValue {
    switch (this) {
      case E1ObjectCoverage.baseDetector:
        return 'base_detector';
      case E1ObjectCoverage.specialistRequired:
        return 'specialist_required';
      case E1ObjectCoverage.derivedSignal:
        return 'derived_signal';
      case E1ObjectCoverage.unknown:
        return 'unknown';
    }
  }
}

class E1ObjectTaxonomyResolution {
  const E1ObjectTaxonomyResolution({
    required this.rawLabel,
    required this.normalizedLabel,
    required this.canonicalObjectId,
    required this.group,
    required this.coverage,
  });

  final String rawLabel;
  final String normalizedLabel;
  final String canonicalObjectId;
  final String group;
  final E1ObjectCoverage coverage;

  bool get isKnown => canonicalObjectId != 'unknown';
  bool get requiresSpecialist =>
      coverage == E1ObjectCoverage.specialistRequired;

  Map<String, Object?> toMetadata() => <String, Object?>{
    'taxonomy_version': E1ObjectTaxonomyV1.version,
    'raw_object_label': rawLabel,
    'normalized_object_label': normalizedLabel,
    'canonical_object_id': canonicalObjectId,
    'object_group': group,
    'object_coverage': coverage.wireValue,
  };
}

abstract final class E1ObjectTaxonomyV1 {
  static const String version = '1.0';

  static const Set<String> specialistCanonicalIds = <String>{
    'smartwatch',
    'earbud',
    'tablet',
    'paper_note',
    'calculator',
  };

  /// Resolve a raw detector/specialist label into a stable exam object ID.
  ///
  /// Generic `clock` is deliberately not an alias for `smartwatch`, and
  /// generic audio/head labels are not promoted to `earbud`. Ambiguous
  /// evidence stays ambiguous instead of being invented into a stronger class.
  static E1ObjectTaxonomyResolution resolve(String rawLabel) {
    final normalized = normalize(rawLabel);
    final entry = _entries[normalized];
    if (entry == null) {
      return E1ObjectTaxonomyResolution(
        rawLabel: rawLabel,
        normalizedLabel: normalized,
        canonicalObjectId: 'unknown',
        group: 'unknown',
        coverage: E1ObjectCoverage.unknown,
      );
    }
    return E1ObjectTaxonomyResolution(
      rawLabel: rawLabel,
      normalizedLabel: normalized,
      canonicalObjectId: entry.canonicalObjectId,
      group: entry.group,
      coverage: entry.coverage,
    );
  }

  static String normalize(String label) {
    return label
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[_\-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static const Map<String, _E1TaxonomyEntry> _entries =
      <String, _E1TaxonomyEntry>{
        // People.
        'person': _E1TaxonomyEntry(
          'person',
          'person',
          E1ObjectCoverage.baseDetector,
        ),
        'additional person': _E1TaxonomyEntry(
          'additional_person',
          'person',
          E1ObjectCoverage.derivedSignal,
        ),
        'partial person': _E1TaxonomyEntry(
          'partial_person',
          'person',
          E1ObjectCoverage.derivedSignal,
        ),

        // Communication devices. COCO baseline emits `cell phone`.
        'cell phone': _E1TaxonomyEntry(
          'phone',
          'communication_device',
          E1ObjectCoverage.baseDetector,
        ),
        'phone': _E1TaxonomyEntry(
          'phone',
          'communication_device',
          E1ObjectCoverage.baseDetector,
        ),
        'mobile phone': _E1TaxonomyEntry(
          'phone',
          'communication_device',
          E1ObjectCoverage.baseDetector,
        ),
        'mobile': _E1TaxonomyEntry(
          'phone',
          'communication_device',
          E1ObjectCoverage.baseDetector,
        ),
        'smartphone': _E1TaxonomyEntry(
          'phone',
          'communication_device',
          E1ObjectCoverage.baseDetector,
        ),

        // Base-detector screen/peripheral classes.
        'laptop': _E1TaxonomyEntry(
          'laptop',
          'extra_screen',
          E1ObjectCoverage.baseDetector,
        ),
        'tv': _E1TaxonomyEntry(
          'television',
          'extra_screen',
          E1ObjectCoverage.baseDetector,
        ),
        'television': _E1TaxonomyEntry(
          'television',
          'extra_screen',
          E1ObjectCoverage.baseDetector,
        ),
        'monitor': _E1TaxonomyEntry(
          'monitor',
          'extra_screen',
          E1ObjectCoverage.specialistRequired,
        ),
        'tv monitor': _E1TaxonomyEntry(
          'monitor',
          'extra_screen',
          E1ObjectCoverage.specialistRequired,
        ),
        'keyboard': _E1TaxonomyEntry(
          'keyboard',
          'computer_peripheral',
          E1ObjectCoverage.baseDetector,
        ),
        'mouse': _E1TaxonomyEntry(
          'mouse',
          'computer_peripheral',
          E1ObjectCoverage.baseDetector,
        ),
        'remote': _E1TaxonomyEntry(
          'remote',
          'communication_device',
          E1ObjectCoverage.baseDetector,
        ),

        // Reference material.
        'book': _E1TaxonomyEntry(
          'book',
          'reference_material',
          E1ObjectCoverage.baseDetector,
        ),
        'paper': _E1TaxonomyEntry(
          'paper_note',
          'reference_material',
          E1ObjectCoverage.specialistRequired,
        ),
        'note': _E1TaxonomyEntry(
          'paper_note',
          'reference_material',
          E1ObjectCoverage.specialistRequired,
        ),
        'notes': _E1TaxonomyEntry(
          'paper_note',
          'reference_material',
          E1ObjectCoverage.specialistRequired,
        ),
        'notebook': _E1TaxonomyEntry(
          'paper_note',
          'reference_material',
          E1ObjectCoverage.specialistRequired,
        ),
        'sheet': _E1TaxonomyEntry(
          'paper_note',
          'reference_material',
          E1ObjectCoverage.specialistRequired,
        ),

        // Exam-relevant small objects absent from the current COCO baseline.
        'calculator': _E1TaxonomyEntry(
          'calculator',
          'calculation_device',
          E1ObjectCoverage.specialistRequired,
        ),
        'tablet': _E1TaxonomyEntry(
          'tablet',
          'extra_screen',
          E1ObjectCoverage.specialistRequired,
        ),
        'tablet computer': _E1TaxonomyEntry(
          'tablet',
          'extra_screen',
          E1ObjectCoverage.specialistRequired,
        ),
        'smartwatch': _E1TaxonomyEntry(
          'smartwatch',
          'wearable_screen',
          E1ObjectCoverage.specialistRequired,
        ),
        'smart watch': _E1TaxonomyEntry(
          'smartwatch',
          'wearable_screen',
          E1ObjectCoverage.specialistRequired,
        ),
        'earbud': _E1TaxonomyEntry(
          'earbud',
          'wearable_audio',
          E1ObjectCoverage.specialistRequired,
        ),
        'earbuds': _E1TaxonomyEntry(
          'earbud',
          'wearable_audio',
          E1ObjectCoverage.specialistRequired,
        ),
        'wireless earbud': _E1TaxonomyEntry(
          'earbud',
          'wearable_audio',
          E1ObjectCoverage.specialistRequired,
        ),
        'earphone': _E1TaxonomyEntry(
          'earbud',
          'wearable_audio',
          E1ObjectCoverage.specialistRequired,
        ),

        // Frame-level derived evidence, not a detector class.
        'screen': _E1TaxonomyEntry(
          'screen_signal',
          'extra_screen',
          E1ObjectCoverage.derivedSignal,
        ),
      };
}

class _E1TaxonomyEntry {
  const _E1TaxonomyEntry(
    this.canonicalObjectId,
    this.group,
    this.coverage,
  );

  final String canonicalObjectId;
  final String group;
  final E1ObjectCoverage coverage;
}
