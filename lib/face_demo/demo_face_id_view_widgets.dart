part of 'demo_face_id_view.dart';

class _Header extends StatelessWidget {
  const _Header({
    required this.snapshot,
    required this.progress,
    required this.compact,
  });

  final DemoFaceIdSnapshot snapshot;
  final double progress;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            snapshot.isComplete ? Icons.verified_user_rounded : Icons.face_retouching_natural,
            color: Colors.white,
            size: compact ? 36 : 44,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  snapshot.isComplete
                      ? 'Backend Face ID active and locked'
                      : 'Register Face ID once for secure exams',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 4),
                Text(snapshot.statusText, style: const TextStyle(color: Color(0xFFCBD5E1))),
                if (snapshot.enrollmentId.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Enrollment: ${snapshot.enrollmentId}',
                    style: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w700),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraPreviewPanel extends StatelessWidget {
  const _CameraPreviewPanel({
    required this.controller,
    required this.openingCamera,
    required this.cameraError,
    required this.guide,
    required this.complete,
    required this.compact,
  });

  final CameraController? controller;
  final bool openingCamera;
  final String? cameraError;
  final _IdentityGuide guide;
  final bool complete;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ready = controller?.value.isInitialized ?? false;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF101828),
        borderRadius: BorderRadius.circular(8),
      ),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (ready) CameraPreview(controller!),
            if (!ready)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    openingCamera
                        ? 'Checking backend Face ID / opening camera...'
                        : complete
                            ? 'Face ID downloaded from backend and locked on this device.'
                            : cameraError ?? 'Camera preview',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            if (!complete)
              Center(
                child: Container(
                  width: compact ? 170 : 210,
                  height: compact ? 210 : 250,
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF22C55E), width: 2),
                    borderRadius: BorderRadius.circular(110),
                  ),
                ),
              ),
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.68),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  complete
                      ? 'Face ID active from backend'
                      : '${guide.title}: ${guide.instruction}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.snapshot,
    required this.progress,
    required this.guides,
    required this.backendMessage,
    required this.compact,
  });

  final DemoFaceIdSnapshot snapshot;
  final double progress;
  final List<_IdentityGuide> guides;
  final String? backendMessage;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Enrollment status',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          _Row(label: 'Student ID', value: snapshot.studentId),
          _Row(label: 'Backend synced', value: snapshot.backendSynced ? 'Yes' : 'No'),
          _Row(label: 'Locked', value: snapshot.locked ? 'Yes' : 'No'),
          _Row(label: 'Status', value: snapshot.status),
          _Row(label: 'Required images', value: '${snapshot.requiredSamples}'),
          _Row(label: 'Available images', value: '${snapshot.capturedSamples}'),
          if (snapshot.lastQualityScore != null)
            _Row(label: 'Best quality', value: '${(snapshot.lastQualityScore! * 100).round()}%'),
          if (backendMessage != null) _Row(label: 'Backend', value: backendMessage!),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: progress.clamp(0.0, 1.0)),
          const SizedBox(height: 14),
          ...guides.asMap().entries.map((entry) {
            final done = entry.key < snapshot.capturedSamples;
            final active = entry.key == snapshot.capturedSamples && !snapshot.isComplete;
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                done ? Icons.check_circle : active ? entry.value.icon : Icons.radio_button_unchecked,
                color: done
                    ? const Color(0xFF16A34A)
                    : active
                        ? const Color(0xFF0F4C81)
                        : const Color(0xFF64748B),
              ),
              title: Text(entry.value.title),
              subtitle: Text(entry.value.instruction),
            );
          }),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.snapshot,
    required this.guide,
    required this.capturing,
    required this.submitting,
    required this.onCapture,
    required this.onReset,
    required this.onBack,
  });

  final DemoFaceIdSnapshot snapshot;
  final _IdentityGuide guide;
  final bool capturing;
  final bool submitting;
  final VoidCallback onCapture;
  final VoidCallback onReset;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FilledButton.icon(
          onPressed: capturing || submitting || snapshot.locked ? null : onCapture,
          icon: Icon(submitting ? Icons.cloud_upload_outlined : guide.icon),
          label: Text(
            submitting
                ? 'Uploading to backend...'
                : 'Capture ${guide.title}',
          ),
        ),
        OutlinedButton.icon(
          onPressed: capturing || submitting || snapshot.locked ? null : onReset,
          icon: const Icon(Icons.refresh),
          label: const Text('Reset local draft'),
        ),
        TextButton.icon(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back),
          label: const Text('Back'),
        ),
      ],
    );
  }
}

class _MobileCaptureBar extends StatelessWidget {
  const _MobileCaptureBar({
    required this.snapshot,
    required this.guide,
    required this.capturing,
    required this.submitting,
    required this.onCapture,
    required this.onReset,
  });

  final DemoFaceIdSnapshot snapshot;
  final _IdentityGuide guide;
  final bool capturing;
  final bool submitting;
  final VoidCallback onCapture;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: capturing || submitting || snapshot.locked ? null : onCapture,
                icon: Icon(submitting ? Icons.cloud_upload_outlined : guide.icon),
                label: Text(submitting ? 'Uploading...' : 'Capture'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: capturing || submitting || snapshot.locked ? null : onReset,
              icon: const Icon(Icons.refresh),
              tooltip: 'Reset local draft',
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}
