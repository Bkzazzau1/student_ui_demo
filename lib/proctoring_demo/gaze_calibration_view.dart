import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../rust/api/gaze_calibration.dart';
import 'gaze_calibration_profile_store.dart';
import 'landmark_gaze_runtime_selector.dart';

class GazeCalibrationView extends StatefulWidget {
  const GazeCalibrationView({
    super.key,
    required this.studentId,
    required this.examId,
    required this.attemptId,
  });

  final String studentId;
  final String examId;
  final String attemptId;

  @override
  State<GazeCalibrationView> createState() => _GazeCalibrationViewState();
}

class _Target {
  const _Target(this.zone, this.title, this.x, this.y);
  final String zone;
  final String title;
  final double x;
  final double y;
}

class _GazeCalibrationViewState extends State<GazeCalibrationView> {
  static const targets = <_Target>[
    _Target('camera', 'Look at the camera', 0.50, 0.08),
    _Target('question_area', 'Look at the question area', 0.20, 0.40),
    _Target('answer_area', 'Look at the answer area', 0.50, 0.68),
    _Target('air_board', 'Look at the rough-work area', 0.82, 0.60),
    _Target('top_screen_area', 'Look at the top of the screen', 0.50, 0.22),
  ];
  static const modelId = 'windows-face-landmarker-478-v1';
  static const modelSha256 =
      '404c737f67469726a4b9cddcd5a3f2d05aab65c73e63496c823f53c60de8e269';

  final LandmarkGazeRuntimeSelector _runtime = LandmarkGazeRuntimeSelector();
  final GazeCalibrationProfileStore _store = GazeCalibrationProfileStore();
  final List<GazeCalibrationSample> _samples = [];
  CameraController? _camera;
  int _targetIndex = 0;
  int _targetSamples = 0;
  bool _running = false;
  bool _opening = true;
  String _message = 'Opening the camera...';

  @override
  void initState() {
    super.initState();
    _openCamera();
  }

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _openCamera() async {
    try {
      final cameras = await availableCameras();
      final selected = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        selected,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _camera = controller;
        _opening = false;
        _message = 'Keep your head comfortable and follow each marker.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _opening = false;
        _message = 'The camera could not start: $error';
      });
    }
  }

  Future<void> _start() async {
    if (_running || _camera == null) return;
    final screen = MediaQuery.sizeOf(context);
    final scale = MediaQuery.devicePixelRatioOf(context);
    setState(() {
      _running = true;
      _samples.clear();
      _targetIndex = 0;
      _targetSamples = 0;
    });
    for (var targetIndex = 0; targetIndex < targets.length; targetIndex++) {
      var attempts = 0;
      while (mounted && _targetSamples < 3 && attempts < 9) {
        attempts++;
        setState(() {
          _targetIndex = targetIndex;
          _message =
              '${targets[targetIndex].title}. Hold still (${_targetSamples + 1}/3).';
        });
        await Future<void>.delayed(const Duration(milliseconds: 650));
        final result = await _capture(targets[targetIndex]);
        if (result) {
          _targetSamples++;
        } else if (mounted) {
          setState(
            () => _message =
                'Keep your face visible and improve the lighting. Retrying...',
          );
        }
      }
      if (_targetSamples < 3) {
        if (mounted) {
          setState(() {
            _running = false;
            _message = 'Calibration quality was too low. Please try again.';
          });
        }
        return;
      }
      _targetSamples = 0;
    }
    final now = DateTime.now().toUtc();
    final camera = _camera!;
    final profile = buildGazeCalibrationProfileV2(
      samples: _samples,
      studentId: widget.studentId,
      deviceId: sha256
          .convert(
            utf8.encode(
              '${Platform.localHostname}:${Platform.operatingSystem}',
            ),
          )
          .toString(),
      examId: widget.examId,
      attemptId: widget.attemptId,
      cameraId: camera.description.name,
      screenWidth: screen.width.round(),
      screenHeight: screen.height.round(),
      displayScale: scale,
      modelId: modelId,
      modelSha256: modelSha256,
      createdAtMs: now.millisecondsSinceEpoch,
      expiresAtMs: now.add(const Duration(hours: 8)).millisecondsSinceEpoch,
    );
    final stored = profile.usable && await _store.save(profile);
    if (!mounted) {
      return;
    }
    setState(() {
      _running = false;
      _message = stored
          ? 'Calibration complete. Quality ${(profile.qualityScore * 100).round()}%.'
          : profile.reason;
    });
    if (stored) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        Navigator.of(context).pop(profile);
      }
    }
  }

  Future<bool> _capture(_Target target) async {
    final camera = _camera;
    if (camera == null || camera.value.isTakingPicture) return false;
    try {
      final picture = await camera.takePicture();
      final decoded = img.decodeImage(await picture.readAsBytes());
      if (decoded == null) return false;
      final rgb = Uint8List.fromList(
        decoded.getBytes(order: img.ChannelOrder.rgb),
      );
      final result = await _runtime.analyseRgb(
        rgbBytes: rgb,
        width: decoded.width,
        height: decoded.height,
      );
      if (result == null || !result.landmarkBased || result.confidence < 0.72) {
        return false;
      }
      _samples.add(
        GazeCalibrationSample(
          zone: target.zone,
          eyeX: ((result.gazeX + 1) / 2).clamp(0.0, 1.0),
          eyeY: ((result.gazeY + 1) / 2).clamp(0.0, 1.0),
          headYaw: result.yawProxy,
          headPitch: result.pitchProxy,
          headRoll: result.rollProxy,
          confidence: result.confidence,
          timestampMs: DateTime.now().toUtc().millisecondsSinceEpoch,
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = targets[_targetIndex.clamp(0, targets.length - 1)];
    return Scaffold(
      backgroundColor: const Color(0xFF07111F),
      appBar: AppBar(
        title: const Text('Personal gaze calibration'),
        backgroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _camera != null && _camera!.value.isInitialized
                ? Opacity(opacity: 0.30, child: CameraPreview(_camera!))
                : const Center(child: CircularProgressIndicator()),
          ),
          if (_running)
            Align(
              alignment: Alignment(target.x * 2 - 1, target.y * 2 - 1),
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.lightBlueAccent,
                  border: Border.all(color: Colors.white, width: 5),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 18),
                  ],
                ),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: _running
                        ? (_targetIndex * 3 + _targetSamples) / 15
                        : 0,
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _opening || _running || _camera == null
                        ? null
                        : _start,
                    icon: const Icon(Icons.center_focus_strong),
                    label: Text(
                      _samples.isEmpty ? 'Start calibration' : 'Try again',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
