import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/e1_object_taxonomy.dart';

void main() {
  test('current COCO manifest does not claim specialist-only classes', () async {
    final manifestFile = File('assets/models/yolo_exam_review/manifest.json');
    final decoded = jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
    final classNames = (decoded['class_names'] as List<dynamic>)
        .map((item) => E1ObjectTaxonomyV1.normalize(item.toString()))
        .toSet();

    expect(classNames, contains('cell phone'));
    expect(classNames, contains('person'));
    expect(classNames, contains('book'));

    for (final specialistLabel in <String>[
      'smartwatch',
      'earbud',
      'tablet',
      'calculator',
      'paper',
    ]) {
      expect(classNames, isNot(contains(specialistLabel)), reason: specialistLabel);
    }
  });
}
