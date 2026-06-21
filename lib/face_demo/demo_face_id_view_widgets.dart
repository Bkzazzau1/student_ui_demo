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
      padding: EdgeInsets.all(compact ? 16 : 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF17325A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x1A000000), blurRadius: 18, offset: Offset(0, 10)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 48 : 58,
            height: compact ? 48 : 58,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
            ),
            child: Icon(
              snapshot.isComplete ? Icons.verified_user_rounded : Icons.face_retouching_natural,
              color: Colors.white,
              size: compact ? 28 : 34,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  snapshot.isComplete ? 'Face ID is active' : 'Set up Face ID',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  snapshot.isComplete
                      ? 'Your saved Face ID is protected and ready for exam identity checks.'
                      : 'Keep your face inside the guide. The app will capture each step automatically.',
                  style: const TextStyle(color: Color(0xFFCBD5E1), height: 1.35),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 7,
                    value: progress.clamp(0.0, 1.0),
                    backgroundColor: Colors.white.withValues(alpha: 0.16),
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF22C55E)),
                  ),
                ),
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
        color: const Color(0xFF0B1220),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x12000000), blurRadius: 18, offset: Offset(0, 10)),
        ],
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
                  padding: const EdgeInsets.all(22),
                  child: Text(
                    openingCamera
                        ? 'Preparing Face ID check...'
                        : complete
                            ? 'Face ID is active on this device.'
                            : cameraError ?? 'Camera preview',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            if (!complete)
              Center(
                child: Container(
                  width: compact ? 170 : 220,
                  height: compact ? 210 : 260,
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF22C55E), width: 3),
                    borderRadius: BorderRadius.circular(130),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(color: Color(0x5522C55E), blurRadius: 18),
                    ],
                  ),
                ),
              ),
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.all(14),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.70),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  complete ? 'Face ID active' : '${guide.title}: ${guide.instruction}',
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
    required this.statusMessage,
    required this.compact,
  });

  final DemoFaceIdSnapshot snapshot;
  final double progress;
  final List<_IdentityGuide> guides;
  final String? statusMessage;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x08000000), blurRadius: 16, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Face ID progress',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusPill('Images', '${snapshot.capturedSamples}/${snapshot.requiredSamples}'),
              _StatusPill('Protected', snapshot.locked ? 'Yes' : 'Pending'),
              _StatusPill('Status', snapshot.isComplete ? 'Active' : 'In progress'),
              if (snapshot.lastQualityScore != null)
                _StatusPill('Quality', '${(snapshot.lastQualityScore! * 100).round()}%'),
            ],
          ),
          if (statusMessage != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFF2563EB), size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(statusMessage!)),
                ],
              ),
            ),
          ],
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
                        : const Color(0xFF94A3B8),
              ),
              title: Text(entry.value.title, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(entry.value.instruction),
            );
          }),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text('$label: $value', style: const TextStyle(fontWeight: FontWeight.w800)),
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
          icon: Icon(submitting ? Icons.cloud_done_outlined : Icons.auto_awesome_motion_outlined),
          label: Text(
            submitting
                ? 'Saving Face ID...'
                : capturing
                    ? 'Automatic capture running...'
                    : 'Start automatic capture',
          ),
        ),
        OutlinedButton.icon(
          onPressed: capturing || submitting || snapshot.locked ? null : onReset,
          icon: const Icon(Icons.refresh),
          label: const Text('Restart setup'),
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
                icon: Icon(submitting ? Icons.cloud_done_outlined : Icons.auto_awesome_motion_outlined),
                label: Text(submitting ? 'Saving...' : 'Auto capture'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: capturing || submitting || snapshot.locked ? null : onReset,
              icon: const Icon(Icons.refresh),
              tooltip: 'Restart setup',
            ),
          ],
        ),
      ),
    );
  }
}
