typedef EventClock = DateTime Function();

class LiveEventCooldownGate {
  LiveEventCooldownGate({
    Duration cooldown = const Duration(seconds: 15),
    EventClock? clock,
  })  : _cooldown = cooldown,
        _clock = clock ?? DateTime.now;

  final Duration _cooldown;
  final EventClock _clock;
  final Map<String, DateTime> _lastAcceptedAt = <String, DateTime>{};

  bool shouldAccept(String eventType) {
    final now = _clock();
    final last = _lastAcceptedAt[eventType];
    if (last != null && now.difference(last) < _cooldown) {
      return false;
    }
    _lastAcceptedAt[eventType] = now;
    return true;
  }

  void reset([String? eventType]) {
    if (eventType == null) {
      _lastAcceptedAt.clear();
    } else {
      _lastAcceptedAt.remove(eventType);
    }
  }

  Map<String, Object?> currentState() => <String, Object?>{
        'cooldown_ms': _cooldown.inMilliseconds,
        'tracked_event_types': _lastAcceptedAt.keys.toList()..sort(),
      };
}
