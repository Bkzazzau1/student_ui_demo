// ignore_for_file: unused_element

part of 'demo_face_id_view.dart';

const Color _identityBrand = Color(0xFF0F4C81);
const Color _identityDark = Color(0xFF0B1220);
const Color _identitySurface = Colors.white;
const Color _identitySoft = Color(0xFFF8FAFC);
const Color _identityLine = Color(0xFFE2E8F0);
const Color _identityMuted = Color(0xFF64748B);
const Color _identitySuccess = Color(0xFF16A34A);
const Color _identityWarning = Color(0xFFF59E0B);

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
    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_identityDark, _identityBrand],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            const Icon(Icons.face_retouching_natural, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    snapshot.isComplete ? 'Identity ready' : 'Face enrollment',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    snapshot.isComplete
                        ? 'Protected on this device'
                        : '${snapshot.capturedSamples}/${snapshot.requiredSamples} captured · Follow the camera guide',
                    style: const TextStyle(
                      color: Color(0xFFE2E8F0),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 6,
                      value: progress.clamp(0.0, 1.0),
                      backgroundColor: Colors.white24,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1F0F172A),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Container(
        padding: EdgeInsets.all(compact ? 18 : 24),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_identityDark, Color(0xFF113A63), _identityBrand],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 720;
            final content = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: compact ? 52 : 66,
                  height: compact ? 52 : 66,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.20),
                    ),
                  ),
                  child: Icon(
                    snapshot.isComplete
                        ? Icons.verified_user_rounded
                        : Icons.account_circle_outlined,
                    color: Colors.white,
                    size: compact ? 28 : 36,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: const [
                          _HeaderTag(
                            icon: Icons.school_outlined,
                            text: 'K-SLAS',
                          ),
                          _HeaderTag(
                            icon: Icons.verified_outlined,
                            text: 'Identity setup',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        snapshot.isComplete
                            ? 'Identity setup active'
                            : 'Set up your identity',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.3,
                            ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        snapshot.isComplete
                            ? 'Your identity setup is protected and ready for exam checks.'
                            : 'Keep your face inside the guide. The app will capture each step automatically.',
                        style: const TextStyle(
                          color: Color(0xFFE2E8F0),
                          height: 1.4,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
            final status = _HeaderProgress(
              snapshot: snapshot,
              progress: progress,
            );
            if (!wide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [content, const SizedBox(height: 16), status],
              );
            }
            return Row(
              children: [
                Expanded(child: content),
                const SizedBox(width: 20),
                SizedBox(width: 250, child: status),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HeaderTag extends StatelessWidget {
  const _HeaderTag({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 15),
          const SizedBox(width: 7),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderProgress extends StatelessWidget {
  const _HeaderProgress({required this.snapshot, required this.progress});

  final DemoFaceIdSnapshot snapshot;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            snapshot.isComplete
                ? Icons.check_circle_outline
                : Icons.pending_actions_outlined,
            color: snapshot.isComplete
                ? const Color(0xFF86EFAC)
                : const Color(0xFFBFDBFE),
            size: 28,
          ),
          const SizedBox(height: 10),
          Text(
            snapshot.isComplete
                ? 'Ready'
                : '${snapshot.capturedSamples}/${snapshot.requiredSamples} captured',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: progress.clamp(0.0, 1.0),
              backgroundColor: Colors.white.withValues(alpha: 0.18),
              valueColor: AlwaysStoppedAnimation<Color>(
                snapshot.isComplete
                    ? const Color(0xFF22C55E)
                    : const Color(0xFF60A5FA),
              ),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            snapshot.isComplete
                ? 'Identity confirmed'
                : 'Follow the guide on screen',
            style: const TextStyle(
              color: Color(0xFFCBD5E1),
              fontWeight: FontWeight.w800,
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
    required this.statusMessage,
    required this.liveGuideState,
  });

  final CameraController? controller;
  final bool openingCamera;
  final String? cameraError;
  final _IdentityGuide guide;
  final bool complete;
  final bool compact;
  final String? statusMessage;
  final _LiveGuideState liveGuideState;

  @override
  Widget build(BuildContext context) {
    final ready = controller?.value.isInitialized ?? false;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _identityDark,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _identityLine),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        complete
                            ? Icons.verified_user_outlined
                            : Icons.photo_camera_front_outlined,
                        color: Colors.white,
                        size: 34,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        openingCamera
                            ? 'Preparing identity check...'
                            : complete
                            ? 'Identity setup is active on this device.'
                            : cameraError ?? 'Camera preview will appear here',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (!complete)
              Center(
                child: _DirectionalFaceGuide(
                  guide: guide,
                  compact: compact,
                  state: liveGuideState,
                ),
              ),
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.all(14),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.70),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!complete) _LiveStateDot(state: liveGuideState),
                    if (!complete) const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        complete
                            ? 'Identity setup active'
                            : '${guide.title}: ${guide.instruction}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!complete)
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: _CameraHint(
                    message: statusMessage,
                    state: liveGuideState,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DirectionalFaceGuide extends StatefulWidget {
  const _DirectionalFaceGuide({
    required this.guide,
    required this.compact,
    required this.state,
  });

  final _IdentityGuide guide;
  final bool compact;
  final _LiveGuideState state;

  @override
  State<_DirectionalFaceGuide> createState() => _DirectionalFaceGuideState();
}

class _DirectionalFaceGuideState extends State<_DirectionalFaceGuide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = switch (widget.guide.code) {
      'left_angle' => -1.0,
      'right_angle' => 1.0,
      _ => 0.0,
    };
    final vertical = switch (widget.guide.code) {
      'look_up' || 'front_face' => -1.0,
      'look_down' || 'smile' || 'open_mouth' => 1.0,
      _ => 0.0,
    };
    final icon = switch (widget.guide.code) {
      'left_angle' => Icons.arrow_back_rounded,
      'right_angle' => Icons.arrow_forward_rounded,
      'look_up' => Icons.arrow_upward_rounded,
      'look_down' => Icons.arrow_downward_rounded,
      'smile' => Icons.sentiment_very_satisfied_rounded,
      'open_mouth' => Icons.record_voice_over_rounded,
      _ => Icons.center_focus_strong_rounded,
    };
    final width = widget.compact ? 178.0 : 230.0;
    final height = widget.compact ? 218.0 : 270.0;
    // Reacts to what the live capture engine currently sees, the way a real
    // KYC scan UI does: gray while no face is found, amber while a face is
    // present but not yet matching the requested pose, green with a check
    // once it's about to auto-capture.
    final ringColor = switch (widget.state) {
      _LiveGuideState.ready => const Color(0xFF22C55E),
      _LiveGuideState.adjusting => const Color(0xFFF59E0B),
      _LiveGuideState.idle => const Color(0xFF94A3B8),
    };
    final ready = widget.state == _LiveGuideState.ready;
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final travel = ready ? 0.0 : 10 * _animation.value;
        return SizedBox(
          width: width + 100,
          height: height + 70,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                width: width,
                height: height,
                decoration: BoxDecoration(
                  color: ringColor.withValues(alpha: 0.08),
                  border: Border.all(
                    color: ringColor,
                    width: ready ? 5 : 4,
                  ),
                  borderRadius: BorderRadius.circular(150),
                  boxShadow: [
                    BoxShadow(
                      color: ringColor.withValues(alpha: 0.40),
                      blurRadius: ready ? 34 : 24,
                    ),
                  ],
                ),
              ),
              Transform.translate(
                offset: Offset(
                  horizontal * (width / 2 + 34 + travel),
                  vertical * (height / 2 + 22 + travel),
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: ringColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: ringColor.withValues(alpha: 0.60),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      ready ? Icons.check_rounded : icon,
                      key: ValueKey<bool>(ready),
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LiveStateDot extends StatelessWidget {
  const _LiveStateDot({required this.state});

  final _LiveGuideState state;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _LiveGuideState.ready => _identitySuccess,
      _LiveGuideState.adjusting => _identityWarning,
      _LiveGuideState.idle => const Color(0xFF94A3B8),
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 6),
        ],
      ),
    );
  }
}

class _CameraHint extends StatelessWidget {
  const _CameraHint({this.message, this.state = _LiveGuideState.idle});

  final String? message;
  final _LiveGuideState state;

  @override
  Widget build(BuildContext context) {
    final accent = switch (state) {
      _LiveGuideState.ready => _identitySuccess,
      _LiveGuideState.adjusting => _identityWarning,
      _LiveGuideState.idle => _identityDark,
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.35), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            switch (state) {
              _LiveGuideState.ready => Icons.check_circle_rounded,
              _LiveGuideState.adjusting => Icons.autorenew_rounded,
              _LiveGuideState.idle => Icons.face_retouching_natural_rounded,
            },
            color: accent,
            size: 15,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              message?.trim().isNotEmpty == true
                  ? message!
                  : 'Stay still while the app captures automatically',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _identityDark,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
        ],
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
        color: _identitySurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _identityLine),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x080F172A),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.fact_check_outlined,
                  color: _identityBrand,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Identity setup progress',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: _identityDark,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusPill(
                'Images',
                '${snapshot.capturedSamples}/${snapshot.requiredSamples}',
              ),
              _StatusPill('Protected', snapshot.locked ? 'Yes' : 'Pending'),
              _StatusPill(
                'Status',
                snapshot.isComplete ? 'Active' : 'In progress',
              ),
              if (snapshot.lastQualityScore != null)
                _StatusPill(
                  'Quality',
                  '${(snapshot.lastQualityScore! * 100).round()}%',
                ),
            ],
          ),
          if (statusMessage != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: Color(0xFF2563EB),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      statusMessage!,
                      style: const TextStyle(
                        color: Color(0xFF334155),
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          ...guides.asMap().entries.map((entry) {
            final done = entry.key < snapshot.capturedSamples;
            final active =
                entry.key == snapshot.capturedSamples && !snapshot.isComplete;
            return _GuideStep(
              guide: entry.value,
              number: entry.key + 1,
              done: done,
              active: active,
            );
          }),
        ],
      ),
    );
  }
}

class _GuideStep extends StatelessWidget {
  const _GuideStep({
    required this.guide,
    required this.number,
    required this.done,
    required this.active,
  });

  final _IdentityGuide guide;
  final int number;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = done
        ? _identitySuccess
        : active
        ? _identityBrand
        : _identityMuted;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: done
            ? const Color(0xFFF0FDF4)
            : active
            ? const Color(0xFFEFF6FF)
            : _identitySoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: done
              ? const Color(0xFFBBF7D0)
              : active
              ? const Color(0xFFBFDBFE)
              : _identityLine,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.22)),
            ),
            child: Icon(
              done
                  ? Icons.check_circle
                  : active
                  ? guide.icon
                  : Icons.circle_outlined,
              color: color,
              size: 19,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Step $number',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        guide.title,
                        style: const TextStyle(
                          color: _identityDark,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  guide.instruction,
                  style: const TextStyle(
                    color: _identityMuted,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
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

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _identitySoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _identityLine),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          color: _identityDark,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _identitySurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _identityLine),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x080F172A),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton.icon(
            onPressed: capturing || submitting || snapshot.locked
                ? null
                : onCapture,
            icon: Icon(
              submitting
                  ? Icons.cloud_done_outlined
                  : Icons.auto_awesome_motion_outlined,
            ),
            label: Text(
              submitting
                  ? 'Saving identity...'
                  : capturing
                  ? 'Automatic capture running...'
                  : 'Start automatic capture',
            ),
          ),
          OutlinedButton.icon(
            onPressed: capturing || submitting || snapshot.locked
                ? null
                : onReset,
            icon: const Icon(Icons.refresh),
            label: const Text('Restart setup'),
          ),
          TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back'),
          ),
        ],
      ),
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
          border: Border(top: BorderSide(color: _identityLine)),
        ),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: capturing || submitting || snapshot.locked
                    ? null
                    : onCapture,
                icon: Icon(
                  submitting
                      ? Icons.cloud_done_outlined
                      : Icons.auto_awesome_motion_outlined,
                ),
                label: Text(submitting ? 'Saving...' : 'Auto capture'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: capturing || submitting || snapshot.locked
                  ? null
                  : onReset,
              icon: const Icon(Icons.refresh),
              tooltip: 'Restart setup',
            ),
          ],
        ),
      ),
    );
  }
}
