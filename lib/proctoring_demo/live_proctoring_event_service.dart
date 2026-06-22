import 'dart:convert';

import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;

class LiveProctoringEvent {
  const LiveProctoringEvent({
    required this.studentId,
    required this.examId,
    required this.attemptId,
    required this.eventType,
    required this.severity,
    required this.message,
    required this.createdAt,
    this.metadata = const <String, Object?>{},
    this.assessmentType = 'exam',
    this.reviewAudience = 'invigilator',
  });

  final String studentId;
  final String examId;
  final String attemptId;
  final String eventType;
  final String severity;
  final String message;
  final DateTime createdAt;
  final Map<String, Object?> metadata;
  final String assessmentType;
  final String reviewAudience;

  Map<String, Object?> toJson() => <String, Object?>{
        'student_id': studentId,
        'exam_id': examId,
        'attempt_id': attemptId,
        'event_type': eventType,
        'severity': severity,
        'message': message,
        'created_at': createdAt.toUtc().toIso8601String(),
        'assessment_type': assessmentType,
        'review_audience': reviewAudience,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };
}

class LiveProctoringEventService {
  LiveProctoringEventService({
    http.Client? client,
    required this.baseUrl,
    GetStorage? storage,
  })  : _client = client ?? http.Client(),
        _storage = storage ?? GetStorage();

  static const String _queueKey = 'kslas_live_proctoring_event_queue_v1';
  static const int _maxQueuedEvents = 250;

  final http.Client _client;
  final GetStorage _storage;
  final String baseUrl;

  bool _flushing = false;

  Future<bool> send(LiveProctoringEvent event) async {
    await flushQueued();

    final payload = event.toJson();
    final delivered = await _postJson(payload);
    if (delivered) return true;

    await _queue(payload);
    return false;
  }

  Future<int> flushQueued({int maxEvents = 25}) async {
    if (_flushing) return 0;
    _flushing = true;
    try {
      final queued = _readQueue();
      if (queued.isEmpty) return 0;

      final remaining = <Map<String, Object?>>[];
      var delivered = 0;
      var processed = 0;

      for (final event in queued) {
        if (processed >= maxEvents) {
          remaining.add(event);
          continue;
        }
        processed++;
        final ok = await _postJson(event);
        if (ok) {
          delivered++;
        } else {
          remaining.add(event);
        }
      }

      await _writeQueue(remaining);
      return delivered;
    } finally {
      _flushing = false;
    }
  }

  Future<bool> _postJson(Map<String, Object?> payload) async {
    final body = _safeJsonEncode(payload);
    if (body == null) return false;

    final attempts = <Uri>[
      Uri.parse('$baseUrl/api/proctoring/live-events'),
      Uri.parse('$baseUrl/api/proctoring/pre-exam-review'),
      Uri.parse('$baseUrl/api/exam-attempts/${payload['attempt_id']}/proctoring-alerts'),
    ];

    for (final uri in attempts) {
      try {
        final response = await _client.post(
          uri,
          headers: const <String, String>{'Content-Type': 'application/json'},
          body: body,
        );
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return true;
        }
      } catch (_) {
        // Try the next compatible endpoint. If all fail, the event is queued.
      }
    }
    return false;
  }

  Future<void> _queue(Map<String, Object?> event) async {
    final queued = _readQueue();
    queued.add(<String, Object?>{
      ...event,
      'queued_at': DateTime.now().toUtc().toIso8601String(),
    });

    final trimmed = queued.length > _maxQueuedEvents
        ? queued.sublist(queued.length - _maxQueuedEvents)
        : queued;
    await _writeQueue(trimmed);
  }

  List<Map<String, Object?>> _readQueue() {
    final raw = _storage.read<String>(_queueKey);
    if (raw == null || raw.trim().isEmpty) return <Map<String, Object?>>[];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, Object?>.from(item))
          .toList();
    } catch (_) {
      return <Map<String, Object?>>[];
    }
  }

  Future<void> _writeQueue(List<Map<String, Object?>> events) async {
    if (events.isEmpty) {
      await _storage.remove(_queueKey);
      return;
    }
    await _storage.write(_queueKey, jsonEncode(events));
  }

  String? _safeJsonEncode(Map<String, Object?> payload) {
    try {
      return jsonEncode(payload);
    } catch (_) {
      return null;
    }
  }

  void dispose() => _client.close();
}
