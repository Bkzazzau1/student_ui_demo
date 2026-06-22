class LiveEventQueuePolicy {
  const LiveEventQueuePolicy._();

  static const int maxQueuedEvents = 250;
  static const int defaultFlushBatchSize = 25;
  static const Duration flushInterval = Duration(seconds: 15);

  static bool shouldKeepEvent(String eventType) {
    const lowValueEvents = <String>{
      'heartbeat_ok',
      'preview_frame_ok',
    };
    return !lowValueEvents.contains(eventType);
  }
}
