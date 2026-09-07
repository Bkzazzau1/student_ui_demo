class E1ExamObjectTaxonomy {
  const E1ExamObjectTaxonomy._();

  static const String taxonomyId = 'e1-exam-object-taxonomy';
  static const String taxonomyVersion = '1.0.0';

  static const Set<String> requiredDetectorClasses = <String>{
    'person',
    'phone',
    'tablet',
    'smartwatch',
    'earbud',
    'headphone',
    'paper',
    'book',
    'note',
    'calculator',
    'laptop',
    'display',
  };

  static const Set<String> derivedContextStates = <String>{
    'partial_person',
    'additional_person',
    'additional_laptop',
    'additional_display',
  };

  static const Set<String> contextualObservationClasses = <String>{
    'keyboard',
    'mouse',
    'remote',
  };

  static const Map<String, String> aliases = <String, String>{
    'person': 'person',
    'human': 'person',
    'cell phone': 'phone',
    'mobile phone': 'phone',
    'smartphone': 'phone',
    'phone': 'phone',
    'tablet': 'tablet',
    'tablet computer': 'tablet',
    'smart watch': 'smartwatch',
    'smartwatch': 'smartwatch',
    'wristwatch': 'smartwatch',
    'earbud': 'earbud',
    'earbuds': 'earbud',
    'earphone': 'earbud',
    'earphones': 'earbud',
    'headphone': 'headphone',
    'headphones': 'headphone',
    'paper': 'paper',
    'sheet of paper': 'paper',
    'document': 'paper',
    'book': 'book',
    'textbook': 'book',
    'note': 'note',
    'notes': 'note',
    'written note': 'note',
    'calculator': 'calculator',
    'laptop': 'laptop',
    'notebook computer': 'laptop',
    'tv': 'display',
    'television': 'display',
    'monitor': 'display',
    'computer monitor': 'display',
    'screen': 'display',
    'display': 'display',
    'keyboard': 'keyboard',
    'mouse': 'mouse',
    'remote': 'remote',
  };

  static String canonicalize(String rawLabel) {
    final normalized = normalizeRawLabel(rawLabel);
    if (normalized.isEmpty) return '';
    return aliases[normalized] ?? _fallbackClassId(normalized);
  }

  static bool isKnownCanonicalClass(String classId) {
    return requiredDetectorClasses.contains(classId) ||
        contextualObservationClasses.contains(classId) ||
        derivedContextStates.contains(classId);
  }

  static bool isRequiredDetectorClass(String classId) =>
      requiredDetectorClasses.contains(classId);

  static String normalizeRawLabel(String rawLabel) {
    return rawLabel
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[_\-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static String _fallbackClassId(String normalizedLabel) {
    return normalizedLabel
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }
}
