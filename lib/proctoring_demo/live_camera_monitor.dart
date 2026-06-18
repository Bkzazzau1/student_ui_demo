import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class LiveCameraMonitor extends StatefulWidget {
  const LiveCameraMonitor({super.key});

  @override
  State<LiveCameraMonitor> createState() => _LiveCameraMonitorState();
}

class _LiveCameraMonitorState extends State<LiveCameraMonitor> {
  CameraController? _controller;
  Timer? _heartbeat;
  String _status = 'Opening camera...';
  bool _opening = false;
  int _secondsLive = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_openCamera());
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _openCamera() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _status = 'Opening camera...';
    });
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _opening = false;
          _status = 'Camera not found';
        });
        return;
      }
      final camera = cameras.firstWhere(
        (item) => item.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.low,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _opening = false;
        _status = 'Camera monitoring active';
      });
      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _secondsLive++);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _opening = false;
        _status = 'Camera monitoring unavailable';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _controller?.value.isInitialized ?? false;
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
                  ready ? Icons.videocam : Icons.videocam_off_outlined,
                  color: ready ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _status,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ready
                    ? CameraPreview(_controller!)
                    : Container(
                        color: const Color(0xFF101828),
                        alignment: Alignment.center,
                        child: Text(
                          _status,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Live duration: ${_secondsLive}s',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
