/// A detected person box, normalized to the camera frame (0..1).
class PersonBox {
  const PersonBox({
    required this.confidence,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });

  final double confidence;
  final double x1;
  final double y1;
  final double x2;
  final double y2;

  double get area =>
      ((x2 - x1).clamp(0.0, 1.0) * (y2 - y1).clamp(0.0, 1.0)).toDouble();

  /// False when the detection came without a usable box; such a person is
  /// always counted (the edge rule needs geometry).
  bool get hasGeometry => x2 > x1 && y2 > y1;

  bool touchesEdge(double margin) =>
      x1 <= margin || y1 <= margin || x2 >= 1 - margin || y2 >= 1 - margin;

  /// Reads `objects` entries from a runtime result (`label`, `confidence`,
  /// `box: {x1, y1, x2, y2}`), keeping only people.
  static List<PersonBox> fromObjects(Iterable<Object?> objects) {
    final people = <PersonBox>[];
    for (final raw in objects) {
      if (raw is! Map) continue;
      final label = '${raw['label'] ?? raw['class'] ?? raw['name'] ?? ''}'
          .toLowerCase();
      if (label != 'person') continue;
      final box = raw['box'];
      final map = box is Map ? box : const <Object?, Object?>{};
      people.add(
        PersonBox(
          confidence: _number(raw['confidence']),
          x1: _number(map['x1']),
          y1: _number(map['y1']),
          x2: _number(map['x2'], fallback: 1),
          y2: _number(map['y2'], fallback: 1),
        ),
      );
    }
    return people;
  }

  static double _number(Object? value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? fallback;
  }
}

/// The one rule for "how many people are in the camera view", shared by live
/// proctoring and the Face ID person check.
///
/// Measured on 1,953 COCO images with the exam YOLO model: counting every
/// person box at 0.45 called a single person "two people" in 2% of frames,
/// mostly hands, feet or a head at the frame edge, and pictures of people.
/// With [minConfidence] 0.55 and the edge rule, that fell to 0.4% while still
/// finding 70% of real second people in a single frame (live proctoring then
/// requires the second person over several frames before acting).
abstract final class PersonCountPolicy {
  /// A person counts toward "how many people" at this confidence or above.
  static const double minConfidence = 0.55;

  /// A person is "present" (for the advisory no-person check) at the model's
  /// decode threshold.
  static const double presenceConfidence = 0.45;

  /// An additional person whose box touches the frame edge and covers less
  /// than this share of the frame is not counted: it is almost always the
  /// student's own hands, feet or arm, not a second person.
  static const double minEdgePersonArea = 0.10;

  static const double edgeMargin = 0.01;

  /// Number of people in the frame under this policy.
  static int count(Iterable<PersonBox> people) {
    final confident =
        people.where((person) => person.confidence >= minConfidence).toList()
          ..sort((a, b) => b.confidence.compareTo(a.confidence));
    if (confident.isEmpty) return 0;
    var count = 1;
    for (final person in confident.skip(1)) {
      if (person.hasGeometry &&
          person.touchesEdge(edgeMargin) &&
          person.area < minEdgePersonArea) {
        continue;
      }
      count++;
    }
    return count;
  }

  /// Whether anyone is visible at all (advisory only).
  static bool anyonePresent(Iterable<PersonBox> people) =>
      people.any((person) => person.confidence >= presenceConfidence);
}
