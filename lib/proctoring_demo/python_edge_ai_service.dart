import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'live_proctoring_event_service.dart';

class EdgeAiReviewDecision {
  const EdgeAiReviewDecision({
    required this.riskScore,
    required this.riskLevel,
    required this.disposition,
    required this.reasons,
    required this.proposedActions,
    required this.requiresHumanReview,
    this.signalGroups = const <String>[],
    this.windowSeconds = 120,
  });

  final int riskScore;
  final String riskLevel;
  final String disposition;
  final List<String> reasons;
  final List<String> proposedActions;
  final bool requiresHumanReview;
  final List<String> signalGroups;
  final int windowSeconds;

  Map<String, Object?> toJson() => <String, Object?>{
    'risk_score': riskScore,
    'risk_level': riskLevel,
    'disposition': disposition,
    'reasons': reasons,
    'proposed_actions': proposedActions,
    'requires_human_review': requiresHumanReview,
    'signal_groups': signalGroups,
    'window_seconds': windowSeconds,
    'observable_behaviour_only': true,
  };

  factory EdgeAiReviewDecision.fromJson(Map<String, Object?> json) {
    return EdgeAiReviewDecision(
      riskScore: (json['risk_score'] as num?)?.round() ?? 0,
      riskLevel: json['risk_level'] as String? ?? 'low',
      disposition: json['disposition'] as String? ?? 'continue_observation',
      reasons: _stringList(json['reasons']),
      proposedActions: _stringList(json['proposed_actions']),
      requiresHumanReview: json['requires_human_review'] == true,
      signalGroups: _stringList(json['signal_groups']),
      windowSeconds: (json['window_seconds'] as num?)?.round() ?? 120,
    );
  }
}

class PythonEdgeAiProtocol {
  const PythonEdgeAiProtocol._();

  static const String version = '1.0';

  static String requestLine({
    required String requestId,
    required String type,
    Map<String, Object?>? payload,
  }) {
    return jsonEncode(<String, Object?>{
      'protocol_version': version,
      'request_id': requestId,
      'type': type,
      if (payload != null) 'payload': payload,
    });
  }

  static Map<String, Object?> parseResponse(String line) {
    final decoded = jsonDecode(line);
    if (decoded is! Map) {
      throw const FormatException('AI response is not an object');
    }
    final response = Map<String, Object?>.from(decoded);
    if (response['protocol_version'] != version) {
      throw const FormatException('Unsupported AI protocol version');
    }
    return response;
  }
}

abstract class EdgeAiReviewer {
  Future<EdgeAiReviewDecision> review(LiveProctoringEvent event);
  Future<void> observeGaze(String attemptId, Map<String, Object?> observation);
  Future<Map<String, Object?>> observeAudio(
    String attemptId,
    Map<String, Object?> observation,
  ) async => const <String, Object?>{};
  Future<bool> clearAttempt(String attemptId);
  Future<void> dispose();
}

class PythonEdgeAiService implements EdgeAiReviewer {
  PythonEdgeAiService({
    this.executable = 'python',
    this.arguments = const <String>['-m', 'ai_runtime'],
    this.workingDirectory,
    this.requestTimeout = const Duration(seconds: 3),
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Duration requestTimeout;

  Process? _process;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  final Map<String, Completer<Map<String, Object?>>> _pending = {};
  int _nextRequestId = 0;
  String _recentStderr = '';

  bool get isRunning => _process != null;

  Future<void> start() async {
    if (_process != null) return;
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: Platform.isWindows,
    );
    _process = process;
    _stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleResponse, onError: _failAll);
    _stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => _recentStderr = line);
    process.exitCode.then((code) {
      if (identical(_process, process)) {
        _process = null;
        _failAll(
          StateError('Python edge AI exited with code $code: $_recentStderr'),
        );
      }
    });

    final health = await _request('health');
    if (health['status'] != 'ready') {
      await dispose();
      throw StateError('Python edge AI did not become ready');
    }
  }

  @override
  Future<EdgeAiReviewDecision> review(LiveProctoringEvent event) async {
    await start();
    final confidenceValue = event.metadata['confidence'];
    final confidence = confidenceValue is num
        ? confidenceValue.toDouble()
        : 1.0;
    final result = await _request(
      'review_event',
      payload: <String, Object?>{
        'attempt_id': event.attemptId,
        'event_type': event.eventType,
        'confidence': confidence.clamp(0.0, 1.0),
        'signal_quality': _metadataConfidence(
          event.metadata['signal_quality'],
          confidence,
        ),
        'occurred_at': event.createdAt.toUtc().toIso8601String(),
      },
    );
    return EdgeAiReviewDecision.fromJson(result);
  }

  double _metadataConfidence(Object? value, double fallback) {
    return value is num ? value.toDouble().clamp(0.0, 1.0) : fallback;
  }

  @override
  Future<bool> clearAttempt(String attemptId) async {
    if (_process == null) return false;
    final result = await _request(
      'clear_attempt',
      payload: <String, Object?>{'attempt_id': attemptId},
    );
    return result['cleared'] == true;
  }

  @override
  Future<void> observeGaze(
    String attemptId,
    Map<String, Object?> observation,
  ) async {
    await start();
    await _request(
      'observe_gaze',
      payload: <String, Object?>{'attempt_id': attemptId, ...observation},
    );
  }

  @override
  Future<Map<String, Object?>> observeAudio(
    String attemptId,
    Map<String, Object?> observation,
  ) async {
    await start();
    return _request(
      'observe_audio',
      payload: <String, Object?>{'attempt_id': attemptId, ...observation},
    );
  }

  Future<Map<String, Object?>> _request(
    String type, {
    Map<String, Object?>? payload,
  }) async {
    final process = _process;
    if (process == null) throw StateError('Python edge AI is not running');
    final requestId = (++_nextRequestId).toString();
    final completer = Completer<Map<String, Object?>>();
    _pending[requestId] = completer;
    process.stdin.writeln(
      PythonEdgeAiProtocol.requestLine(
        requestId: requestId,
        type: type,
        payload: payload,
      ),
    );
    try {
      final response = await completer.future.timeout(requestTimeout);
      if (response['ok'] != true) {
        final error = response['error'];
        throw StateError('Python edge AI rejected $type: $error');
      }
      final result = response['result'];
      if (result is! Map) {
        throw const FormatException('AI result is not an object');
      }
      return Map<String, Object?>.from(result);
    } finally {
      _pending.remove(requestId);
    }
  }

  void _handleResponse(String line) {
    try {
      final response = PythonEdgeAiProtocol.parseResponse(line);
      final requestId = response['request_id'];
      if (requestId is String) _pending[requestId]?.complete(response);
    } catch (error, stackTrace) {
      _failAll(error, stackTrace);
    }
  }

  void _failAll(Object error, [StackTrace? stackTrace]) {
    for (final completer in _pending.values.toList()) {
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
    }
    _pending.clear();
  }

  @override
  Future<void> dispose() async {
    final process = _process;
    _process = null;
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;
    _failAll(StateError('Python edge AI was stopped'));
    if (process != null) {
      await process.stdin.close();
      process.kill();
    }
  }
}

List<String> _stringList(Object? value) => value is List
    ? value.whereType<String>().toList(growable: false)
    : const [];
