import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../auth/student_session.dart';
import '../exam_demo/assessment_device_gate.dart';
import 'face_id_registration_capture_view.dart';
import 'local_sample_school_identity_service.dart';
import 'official_face_id_consent.dart';
import 'official_face_id_models.dart';
import 'official_identity_session.dart';
import 'sample_school_admin_view.dart';

const Color _ink = Color(0xFF0F172A);
const Color _muted = Color(0xFF64748B);
const Color _line = Color(0xFFE2E8F0);
const Color _brand = Color(0xFF0F4C81);

/// The student's Face ID screen: shows what the school has on record, and
/// lets the student register (or replace) their Face ID for approval.
///
/// Registering never changes the approved Face ID by itself. A new
/// registration waits for school staff; the approved one stays in use until
/// the new one is approved.
class OfficialFaceIdView extends StatefulWidget {
  const OfficialFaceIdView({super.key, this.studentId});

  /// Defaults to the signed-in student.
  final String? studentId;

  @override
  State<OfficialFaceIdView> createState() => _OfficialFaceIdViewState();
}

class _OfficialFaceIdViewState extends State<OfficialFaceIdView> {
  late final String _studentId = widget.studentId ?? StudentSession.studentId;
  OfficialFaceIdStatus? _status;
  String? _error;
  bool _loading = true;
  bool _submitting = false;
  bool _isSampleSchool = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final school = await SchoolIdentityServices.instance.school();
      final status = await school.fetchStatus(_studentId);
      if (!mounted) return;
      setState(() {
        _status = status;
        _isSampleSchool = school.isSample;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'Could not reach the school to check your Face ID. Check your '
            'internet connection and try again.';
      });
    }
  }

  Future<void> _register() async {
    final agreed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const _FaceIdConsentPage()),
    );
    if (agreed != true || !mounted) return;
    final consentAcceptedAt = DateTime.now().toUtc();
    final capture = await Navigator.of(context).push<FaceIdRegistrationCapture>(
      MaterialPageRoute<FaceIdRegistrationCapture>(
        builder: (_) => const FaceIdRegistrationCaptureView(),
      ),
    );
    if (capture == null || !mounted) return;
    setState(() {
      _submitting = true;
      _notice = null;
    });
    try {
      final school = await SchoolIdentityServices.instance.school();
      final random = math.Random.secure();
      final submission = OfficialFaceIdSubmission(
        submissionId:
            'sub-${DateTime.now().toUtc().millisecondsSinceEpoch}-'
            '${random.nextInt(1 << 32).toRadixString(16)}',
        studentId: _studentId,
        submittedAt: DateTime.now().toUtc(),
        consentVersion: OfficialFaceIdConsent.version,
        consentAcceptedAt: consentAcceptedAt,
        modelId: OfficialFaceIdModel.modelId,
        modelSha256: OfficialFaceIdModel.modelSha256,
        preprocessingVersion: OfficialFaceIdModel.preprocessingVersion,
        capturePlatform: Platform.operatingSystem,
        captureDeviceClass: _deviceClassName(),
        poseOrder: capture.poseOrder,
        photos: capture.photos,
      );
      await school.submitRegistration(submission);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _notice = 'Your Face ID photos were sent to your school for approval.';
      });
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _notice =
            'Your photos could not be sent. Check your connection and try '
            'again. ($error)';
      });
    }
  }

  String _deviceClassName() {
    final size = MediaQuery.sizeOf(context);
    return AssessmentDeviceClassResolver.resolve(
      platform: defaultTargetPlatform,
      shortestSide: size.shortestSide,
    ).name;
  }

  Future<void> _openSampleAdmin() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const SampleSchoolAdminView()),
    );
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('Face ID'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading || _submitting ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _statusCard(),
                  if (_notice != null) ...[
                    const SizedBox(height: 12),
                    _NoticeCard(text: _notice!),
                  ],
                  const SizedBox(height: 16),
                  ..._actions(),
                  const SizedBox(height: 20),
                  const _HowItWorksCard(),
                  if (_isSampleSchool &&
                      (kDebugMode ||
                          IdentityTrustPolicy.allowSampleSchool)) ...[
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: _submitting ? null : _openSampleAdmin,
                      icon: const Icon(Icons.admin_panel_settings_outlined),
                      label: const Text('Sample school admin (testing only)'),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Stands in for the university system until it is '
                      'connected. Staff approve or reject registrations there.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _actions() {
    final status = _status;
    if (_loading || status == null) return const <Widget>[];
    final busy = _submitting;
    final label = switch (status.state) {
      OfficialFaceIdState.notSubmitted => 'Register Face ID',
      OfficialFaceIdState.rejected => 'Register Face ID again',
      OfficialFaceIdState.pendingApproval => 'Replace my waiting registration',
      OfficialFaceIdState.approved =>
        status.hasPendingSubmission
            ? 'Replace my waiting registration'
            : 'Register a new Face ID',
    };
    final primary =
        status.state == OfficialFaceIdState.notSubmitted ||
        status.state == OfficialFaceIdState.rejected;
    final icon = busy
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.face_retouching_natural);
    final text = Text(busy ? 'Sending to your school...' : label);
    return <Widget>[
      primary
          ? FilledButton.icon(
              onPressed: busy ? null : _register,
              icon: icon,
              label: text,
            )
          : OutlinedButton.icon(
              onPressed: busy ? null : _register,
              icon: icon,
              label: text,
            ),
    ];
  }

  Widget _statusCard() {
    if (_loading) {
      return const _StatusCard(
        icon: Icons.hourglass_top,
        color: _brand,
        title: 'Checking your Face ID...',
        body: 'Asking your school for your Face ID status.',
      );
    }
    final error = _error;
    if (error != null) {
      return _StatusCard(
        icon: Icons.cloud_off_outlined,
        color: const Color(0xFFB45309),
        title: 'School not reachable',
        body: error,
      );
    }
    final status = _status!;
    return switch (status.state) {
      OfficialFaceIdState.notSubmitted => const _StatusCard(
        icon: Icons.person_add_alt_1_outlined,
        color: _brand,
        title: 'Register your Face ID',
        body:
            'Your school must approve your Face ID before you can write '
            'exams. It takes about a minute: the app guides you through '
            'seven photos.',
      ),
      OfficialFaceIdState.pendingApproval => _StatusCard(
        icon: Icons.pending_actions_outlined,
        color: const Color(0xFFB45309),
        title: 'Waiting for school approval',
        body:
            'Sent ${_date(status.pendingSubmittedAt)}. You can write exams '
            'once your school approves it.',
      ),
      OfficialFaceIdState.rejected => _StatusCard(
        icon: Icons.error_outline,
        color: const Color(0xFFDC2626),
        title: 'Not approved',
        body:
            '${status.lastRejectionReason} Please register your Face ID '
            'again.',
      ),
      OfficialFaceIdState.approved => _StatusCard(
        icon: Icons.verified_user_outlined,
        color: const Color(0xFF16A34A),
        title: 'Official Face ID approved',
        body: status.hasPendingSubmission
            ? 'Approved ${_date(status.activeApprovedAt)}. A new registration '
                  'sent ${_date(status.pendingSubmittedAt)} is waiting for '
                  'approval; your current Face ID stays in use until then.'
            : 'Approved ${_date(status.activeApprovedAt)}. You can sign in on '
                  'any approved laptop or tablet and your exams will check '
                  'your face against it.',
      ),
    };
  }

  static String _date(DateTime? value) {
    if (value == null) return 'recently';
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'on ${local.year}-${two(local.month)}-${two(local.day)} '
        'at ${two(local.hour)}:${two(local.minute)}';
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: _ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(body, style: const TextStyle(color: _muted, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        border: Border.all(color: const Color(0xFFBFDBFE)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: const TextStyle(color: _ink, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _HowItWorksCard extends StatelessWidget {
  const _HowItWorksCard();

  @override
  Widget build(BuildContext context) {
    const steps = <String>[
      'Register your Face ID once: the app takes seven guided photos.',
      'Your school reviews the photos and approves your Face ID.',
      'Before each exam, the app checks your face against it on this '
          'device. The questions open only after it passes.',
      'During the exam, short checks happen at random times.',
    ];
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'How Face ID works',
            style: TextStyle(color: _ink, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          for (var index = 0; index < steps.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${index + 1}. ',
                    style: const TextStyle(
                      color: _brand,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      steps[index],
                      style: const TextStyle(color: _muted, height: 1.4),
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

class _FaceIdConsentPage extends StatefulWidget {
  const _FaceIdConsentPage();

  @override
  State<_FaceIdConsentPage> createState() => _FaceIdConsentPageState();
}

class _FaceIdConsentPageState extends State<_FaceIdConsentPage> {
  bool _agreed = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(title: const Text(OfficialFaceIdConsent.title)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final section in OfficialFaceIdConsent.sections)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            section.heading,
                            style: const TextStyle(
                              color: _ink,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            section.body,
                            style: const TextStyle(color: _muted, height: 1.45),
                          ),
                        ],
                      ),
                    ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _agreed,
                    onChanged: (value) =>
                        setState(() => _agreed = value ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(OfficialFaceIdConsent.agreement),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _agreed
                        ? () => Navigator.of(context).pop(true)
                        : null,
                    child: const Text('Agree and take photos'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Not now'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
