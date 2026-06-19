import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'companion_cam_service.dart';
import 'live_proctoring_event_service.dart';

class CompanionCamPanel extends StatefulWidget {
  const CompanionCamPanel({
    super.key,
    required this.studentId,
    required this.examId,
    required this.attemptId,
    required this.onCompanionLost,
    this.assessmentType = 'exam',
    this.reviewAudience = 'invigilator',
  });

  final String studentId;
  final String examId;
  final String attemptId;
  final ValueChanged<String> onCompanionLost;
  final String assessmentType;
  final String reviewAudience;

  @override
  State<CompanionCamPanel> createState() => _CompanionCamPanelState();
}

class _CompanionCamPanelState extends State<CompanionCamPanel> {
  static const String _baseUrl = String.fromEnvironment(
    'KSLAS_API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8080',
  );

  late final CompanionCamService _service;
  late final LiveProctoringEventService _events;
  StreamSubscription<CompanionCamFrame>? _frameSub;
  StreamSubscription<bool>? _connectionSub;
  CompanionCamSession? _session;
  Uint8List? _latestFrame;
  bool _starting = false;
  bool _connected = false;
  int _frameCount = 0;
  DateTime? _lastFrameAt;
  Timer? _heartbeat;
  String _status = 'Start companion camera for high-stakes monitoring.';

  @override
  void initState() {
    super.initState();
    _service = CompanionCamService(
      studentId: widget.studentId,
      examId: widget.examId,
      attemptId: widget.attemptId,
    );
    _events = LiveProctoringEventService(baseUrl: _baseUrl);
    _frameSub = _service.frames.listen(_onFrame);
    _connectionSub = _service.connectionChanges.listen(_onConnectionChanged);
    _heartbeat = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _checkHeartbeat(),
    );
    unawaited(_start());
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    _frameSub?.cancel();
    _connectionSub?.cancel();
    _events.dispose();
    unawaited(_service.dispose());
    super.dispose();
  }

  Future<void> _start() async {
    if (_starting) return;
    setState(() {
      _starting = true;
      _status = 'Creating secure local pairing QR...';
    });
    try {
      final session = await _service.start();
      if (!mounted) return;
      setState(() {
        _session = session;
        _starting = false;
        _connected = false;
        _status =
            'Scan QR with phone on same Wi-Fi. Place phone behind or beside you.';
      });
      await _sendEvent(
        eventType: 'companion_cam_qr_generated',
        severity: 'info',
        message: 'Companion camera pairing QR generated.',
        metadata: <String, Object?>{
          'host': session.host,
          'port': session.port,
          'expires_at': session.expiresAt.toIso8601String(),
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _status = 'Companion camera server could not start: $e';
      });
      await _sendEvent(
        eventType: 'companion_cam_server_failed',
        severity: 'warning',
        message: 'Companion camera local server could not start.',
        metadata: <String, Object?>{'error': e.toString()},
      );
    }
  }

  void _onFrame(CompanionCamFrame frame) {
    if (!mounted) return;
    setState(() {
      _latestFrame = frame.bytes;
      _frameCount = frame.frameNumber;
      _lastFrameAt = frame.receivedAt;
      _connected = true;
      _status = 'Companion camera streaming. Frame $_frameCount received.';
    });
  }

  void _onConnectionChanged(bool connected) {
    if (!mounted) return;
    setState(() {
      _connected = connected;
      _status = connected
          ? 'Companion camera connected.'
          : 'Companion camera disconnected. Re-scan QR or keep phone awake.';
    });
    unawaited(
      _sendEvent(
        eventType: connected
            ? 'companion_cam_connected'
            : 'companion_cam_disconnected',
        severity: connected ? 'info' : 'warning',
        message: connected
            ? 'Companion camera connected over local Wi-Fi.'
            : 'Companion camera disconnected during exam.',
      ),
    );
  }

  void _checkHeartbeat() {
    final last = _lastFrameAt;
    if (_connected &&
        last != null &&
        DateTime.now().difference(last).inSeconds > 20) {
      setState(() {
        _connected = false;
        _status =
            'Companion camera feed stale. Phone may be locked or disconnected.';
      });
      unawaited(
        _sendEvent(
          eventType: 'companion_cam_feed_stale',
          severity: 'high',
          message: 'Companion camera feed stopped sending frames during exam.',
          metadata: <String, Object?>{
            'last_frame_at': last.toIso8601String(),
            'frame_count': _frameCount,
          },
        ),
      );
      widget.onCompanionLost(
        'Companion camera feed stopped. Keep phone camera connected for this high-stakes exam.',
      );
    }
  }

  Future<void> _sendEvent({
    required String eventType,
    required String severity,
    required String message,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return _events.send(
      LiveProctoringEvent(
        studentId: widget.studentId,
        examId: widget.examId,
        attemptId: widget.attemptId,
        eventType: eventType,
        severity: severity,
        message: message,
        createdAt: DateTime.now(),
        metadata: metadata,
        assessmentType: widget.assessmentType,
        reviewAudience: widget.reviewAudience,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  _connected ? Icons.link : Icons.qr_code_2,
                  color: _connected
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFF59E0B),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Companion camera',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  tooltip: 'Restart pairing',
                  onPressed: _starting ? null : () => unawaited(_start()),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_status, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            if (session != null && !_connected)
              Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: QrImageView(
                      data: session.pairingUrl,
                      version: QrVersions.auto,
                      size: 190,
                    ),
                  ),
                ),
              ),
            if (_latestFrame != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  _latestFrame!,
                  fit: BoxFit.cover,
                  height: 150,
                  gaplessPlayback: true,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Local Wi-Fi only • dynamic signed QR • no cloud streaming',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}
