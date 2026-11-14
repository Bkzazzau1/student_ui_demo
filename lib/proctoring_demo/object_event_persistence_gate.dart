/// Lets an object event through only when it is seen in at least [required]
/// of the last [window] analysed frames, including the current one.
///
/// One frame is not evidence: on 1,953 COCO images the exam YOLO model saw an
/// "extra screen" in 0.5% of frames without one (a dark board as a TV), and
/// at about one frame a second that would pause a two-hour exam several times.
/// A real phone or second screen stays in view for many frames.
class ObjectEventPersistenceGate {
  ObjectEventPersistenceGate({this.window = 3, this.required = 2})
    : assert(window >= 1),
      assert(required >= 1 && required <= window);

  final int window;
  final int required;
  final Map<String, List<bool>> _history = <String, List<bool>>{};

  /// Records the event types one analysed frame produced and returns those
  /// that are now sustained.
  Set<String> observe(Iterable<String> eventTypes) {
    final seen = eventTypes.toSet();
    final sustained = <String>{};
    for (final type in <String>{..._history.keys, ...seen}) {
      final history = _history.putIfAbsent(type, () => <bool>[]);
      history.add(seen.contains(type));
      if (history.length > window) {
        history.removeRange(0, history.length - window);
      }
      final hits = history.where((hit) => hit).length;
      if (seen.contains(type) && hits >= required) sustained.add(type);
      if (hits == 0) _history.remove(type);
    }
    return sustained;
  }

  /// Hits for [type] in the current window.
  int hits(String type) => _history[type]?.where((hit) => hit).length ?? 0;

  void reset() => _history.clear();
}
