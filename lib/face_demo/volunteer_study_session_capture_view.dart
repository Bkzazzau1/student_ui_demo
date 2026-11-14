import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'face_embedding_pipeline.dart';
import 'volunteer_study_store.dart';

/// The three exam photos of one study session.
class StudySessionCapture {
  const StudySessionCapture({
    required this.photos,
    required this.attempts,
    required this.rejected,
  });

  final List<Uint8List> photos;
  final int attempts;
  final int rejected;
}

/// Takes one study session's exam photos on this device.
///
/// Uses the identity check's camera settings (front camera, medium
/// resolution) and the app's own face pipeline: a photo the app would reject
/// for quality (no face, blur, bad framing) is not kept, exactly as a real
/// check would retry it, but it is counted. Photos are taken automatically a
/// moment apart while the volunteer looks at the screen, as during an exam.
class VolunteerStudySessionCaptureView extends StatefulWidget {
  const VolunteerStudySessionCaptureView({
    super.key,
    required this.volunteerCode,
    required this.session,
    this.pipeline,
  });

  final String volunteerCode;
  final StudySession session;
  final FaceEmbeddingPipeline? pipeline;

  @override
  State<VolunteerStudySessionCaptureView> createState() =>
      _VolunteerStudySessionCaptureViewState();
}

enum _Stage { opening, ready, countdown, capturing, done, incomplete, failed }

class _VolunteerStudySessionCaptureViewState
    extends State<VolunteerStudySessionCaptureView> {
  static const int _maxAttempts = 10;
  static const Duration _gap = Duration(milliseconds: 1500);

  late final FaceEmbeddingPipeline _pipeline =
      widget.pipeline ?? FaceEmbeddingPipeline();
  CameraController? _controller;
  _Stage _stage = _Stage.opening;
  String _message = 'Opening the camera...';
  int _countdown = 0;
  int _attempts = 0;
  int _rejected = 0;
  String? _lastRejection;
  final List<Uint8List> _photos = <Uint8List>[];

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void dispose() {
    _stage = _Stage.failed;
    unawaited(_controller?.dispose());
    super.dispose();
  }

  Future<void> _open() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _fail('No camera was found on this device.');
        return;
      }
      final camera = cameras.firstWhere(
        (item) => item.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      // Same settings as FaceIdentityCheckView, so study photos look like
      // the photos real checks use.
      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      if (!await _pipeline.initialize()) {
        _fail('The face AI is not available on this device.');
        return;
      }
      if (!mounted) return;
      setState(() {
        _stage = _Stage.ready;
        _message = widget.session.instruction;
      });
    } catch (error) {
      _fail('The camera could not open: $error');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _stage = _Stage.failed;
      _message = message;
    });
  }

  Future<void> _start() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    setState(() {
      _photos.clear();
      _attempts = 0;
      _rejected = 0;
      _lastRejection = null;
      _stage = _Stage.countdown;
    });
    for (var seconds = 3; seconds > 0; seconds--) {
      if (!mounted || _stage != _Stage.countdown) return;
      setState(() => _countdown = seconds);
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    if (!mounted) return;
    setState(() => _stage = _Stage.capturing);

    while (mounted &&
        _stage == _Stage.capturing &&
        _photos.length < StudySession.photosPerSession &&
        _attempts < _maxAttempts) {
      try {
        final picture = await controller.takePicture();
        final bytes = await picture.readAsBytes();
        _attempts++;
        final result = await _pipeline.processEncodedImage(bytes);
        if (!mounted) return;
        setState(() {
          if (result == null) {
            _rejected++;
            _lastRejection = _pipeline.lastFailureReason.isEmpty
                ? 'No usable face in that photo.'
                : _pipeline.lastFailureReason;
          } else {
            _photos.add(bytes);
            _lastRejection = null;
          }
        });
      } catch (error) {
        _attempts++;
        _rejected++;
        if (mounted) setState(() => _lastRejection = 'Camera error: $error');
      }
      if (_photos.length < StudySession.photosPerSession) {
        await Future<void>.delayed(_gap);
      }
    }
    if (!mounted || _stage != _Stage.capturing) return;
    setState(() {
      _stage = _photos.length == StudySession.photosPerSession
          ? _Stage.done
          : _Stage.incomplete;
    });
  }

  void _save() {
    Navigator.of(context).pop(
      StudySessionCapture(
        photos: List<Uint8List>.unmodifiable(_photos),
        attempts: _attempts,
        rejected: _rejected,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.volunteerCode}: ${widget.session.title}'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (controller != null && controller.value.isInitialized)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(controller),
                      if (_stage == _Stage.countdown)
                        Center(
                          child: Text(
                            '$_countdown',
                            style: theme.textTheme.displayLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              )
            else
              const AspectRatio(
                aspectRatio: 4 / 3,
                child: Center(child: CircularProgressIndicator()),
              ),
            const SizedBox(height: 16),
            Text(widget.session.instruction, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 12),
            _Progress(
              kept: _photos.length,
              attempts: _attempts,
              rejected: _rejected,
            ),
            if (_lastRejection != null) ...[
              const SizedBox(height: 8),
              Text(
                'Not kept: $_lastRejection',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            if (_stage == _Stage.failed) ...[
              const SizedBox(height: 12),
              Text(_message, style: TextStyle(color: theme.colorScheme.error)),
            ],
            if (_stage == _Stage.incomplete) ...[
              const SizedBox(height: 12),
              Text(
                'Only ${_photos.length} of ${StudySession.photosPerSession} '
                'photos passed the quality check after $_attempts tries. '
                'Improve the framing (face centred, about an arm\'s length '
                'away) and run the session again. Keep the light as the '
                'session describes.',
              ),
            ],
            const SizedBox(height: 16),
            if (_stage == _Stage.ready || _stage == _Stage.incomplete)
              FilledButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.photo_camera_front_outlined),
                label: Text(
                  _stage == _Stage.ready
                      ? 'Start: 3 photos'
                      : 'Run the session again',
                ),
              ),
            if (_stage == _Stage.done) ...[
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save this session'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _start,
                child: const Text('Take the session again'),
              ),
            ],
            if (_stage == _Stage.capturing || _stage == _Stage.countdown)
              const Text(
                'Keep looking at the screen as when writing an exam.',
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({
    required this.kept,
    required this.attempts,
    required this.rejected,
  });

  final int kept;
  final int attempts;
  final int rejected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < StudySession.photosPerSession; i++)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Icon(
              i < kept ? Icons.check_circle : Icons.radio_button_unchecked,
              color: i < kept ? Colors.green : Colors.grey,
            ),
          ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$kept of ${StudySession.photosPerSession} kept'
            '${attempts > 0 ? ' · $attempts taken, $rejected not usable' : ''}',
          ),
        ),
      ],
    );
  }
}
