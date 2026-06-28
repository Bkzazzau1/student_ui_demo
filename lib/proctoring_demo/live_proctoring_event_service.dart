import 'dart:convert';
import 'dart:typed_data';

import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;

class LocalFirstEventPayloadPolicy {
  const LocalFirstEventPayloadPolicy._();

  static const int maxStringLength = 2000;
  static const int maxListItems = 50;
  static const int maxMapEntries = 80;

  static const Set<String> _localOnlyKeys = <String>{
    'bytes',
    'raw_bytes',
    'frame_bytes',
    'image_bytes',
    'audio_bytes',
    'pcm_bytes',
    'wav_bytes',
    'video_bytes',
    'base64',
    'image_base64',
    'audio_base64',
    'video_base64',
    'raw_frame',
    'raw_image',
    'raw_audio',
    'raw_video',
    'file_path',
    'directory_path',
    'absolute_path',
    'path',
    'image_path',
    'audio_path',
    'video_path',
    'snapshot_path',
    'recording_path',
    'local_file',
    'local_path',
  };

  static const Set<String> _allowedEvidenceReferenceKeys = <String>{
    'id',
    'event_type',
    'file_type',
    'sha256',
    'size_bytes',
    'created_at',
    'review_reason',
  };

  static Map<String, Object?> sanitizePayload(Map<String, Object?> payload) {
    final sanitized = _sanitizeMap(payload, depth: 0);
    return sanitized;
  }

  static Map<String, Object?> _sanitizeMap(
    Map<Object?, Object?> map, {
    required int depth,
  }) {
    final result = <String, Object?>{};
    final entries = map.entries.take(maxMapEntries);
    for (final entry in entries) {
      final key = entry.key?.toString() ?? '';
      if (key.trim().isEmpty) continue;
      final normalizedKey = _normalizeKey(key);
      if (_localOnlyKeys.contains(normalizedKey)) {
        result[key] = '[stored_locally]';
        continue;
      }
      if (normalizedKey == 'local_record' && entry.value is Map) {
        result[key] = _sanitizeLocalRecord(Map<Object?, Object?>.from(entry.value as Map));
        continue;
      }
      result[key] = _sanitizeValue(entry.value, depth: depth + 1);
    }
    if (map.length > maxMapEntries) {
      result['truncated_map_entries'] = map.length - maxMapEntries;
    }
    return result;
  }

  static Map<String, Object?> _sanitizeLocalRecord(Map<Object?, Object?> record) {
    final result = <String, Object?>{};
    for (final entry in record.entries) {
      final key = entry.key?.toString() ?? '';
      if (key.trim().isEmpty) continue;
      final normalizedKey = _normalizeKey(key);
      if (_allowedEvidenceReferenceKeys.contains(normalizedKey)) {
        result[key] = _sanitizeValue(entry.value, depth: 1);
      }
    }
    result['storage'] = 'local_device_vault';
    return result;
  }

  static Object? _sanitizeValue(Object? value, {required int depth}) {
    if (value == null || value is num || value is bool) return value;
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is Uint8List || value is ByteBuffer || value is ByteData) {
      return '[stored_locally]';
    }
    if (value is String) return _sanitizeString(value);
    if (depth >= 8) return '[nested_metadata_truncated]';
    if (value is Map) {
      return _sanitizeMap(Map<Object?, Object?>.from(value), depth: depth);
    }
    if (value is Iterable) {
      final items = value.take(maxListItems).map((item) => _sanitizeValue(item, depth: depth + 1)).toList();
      if (value.length > maxListItems) {
        items.add(<String, Object?>{'truncated_list_items': value.length - maxListItems});
      }
      return items;
    }
    return _sanitizeString(value.toString());
  }

  static String _sanitizeString(String value) {
    final trimmed = value.length > maxStringLength
        ? '${value.substring(0, maxStringLength)}...[truncated]'
        : value;
    if (_looksLikeEncodedMedia(trimmed) || _looksLikeLocalPath(trimmed)) {
      return '[stored_locally]';
    }
    return trimmed;
  }

  static bool _looksLikeEncodedMedia(String value) {
    final compact = value.trim();
    if (compact.startsWith('data:image/') || compact.startsWith('data:audio/') || compact.startsWith('data:video/')) {
      return true;
    }
    if (compact.length < 600) return false;
    return RegExp(r'^[A-Za-z0-9+/=\r\n]+$').hasMatch(compact);
  }

  static bool _looksLikeLocalPath(String value) {
    final lower = value.toLowerCase();
    if (lower.startsWith('/tmp/') || lower.startsWith('/var/') || lower.startsWith('/users/')) return true;
    if (lower.startsWith('c:\\') || lower.startsWith('d:\\')) return true;
    if (lower.contains('\\appdata\\') || lower.contains('/appdata/')) return true;
    if (lower.contains('kslas_evidence') || lower.contains('local_evidence')) return true;
    return false;
  }

  static String _normalizeKey(String key) {
    return key.trim().toLowerCase().replaceAll('-', '_');
  }
}

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

  Map<String, Object?> toJson() {
    final payload = <String, Object?>{
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
    return LocalFirstEventPayloadPolicy.sanitizePayload(payload);
  }
}

class LiveProctoringEventService {
  LiveProctoringEventService({
    http.Client? client,
    required this.baseUrl,
    GetStorage? storage,
  })  : _client = client ?? http.Client(),
        _storage = storage ?? GetStorage();

  static const String _queueKey = 'kslas_live_proctoring_event_queue_v2';
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
    final safePayload = LocalFirstEventPayloadPolicy.sanitizePayload(payload);
    final body = _safeJsonEncode(safePayload);
    if (body == null) return false;

    final attempts = <Uri>[
      Uri.parse('$baseUrl/api/proctoring/live-events'),
      Uri.parse('$baseUrl/api/proctoring/pre-exam-review'),
      Uri.parse(
        '$baseUrl/api/exam-attempts/${safePayload['attempt_id']}/proctoring-alerts',
      ),
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
    queued.add(LocalFirstEventPayloadPolicy.sanitizePayload(<String, Object?>{
      ...event,
      'queued_at': DateTime.now().toUtc().toIso8601String(),
    }));

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
          .map((item) => LocalFirstEventPayloadPolicy.sanitizePayload(Map<String, Object?>.from(item)))
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
    final sanitized = events
        .map((event) => LocalFirstEventPayloadPolicy.sanitizePayload(event))
        .toList();
    await _storage.write(_queueKey, jsonEncode(sanitized));
  }

  String? _safeJsonEncode(Map<String, Object?> payload) {
    try {
      return jsonEncode(LocalFirstEventPayloadPolicy.sanitizePayload(payload));
    } catch (_) {
      return null;
    }
  }

  void dispose() => _client.close();
}
