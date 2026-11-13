import 'dart:async';

import 'package:flutter/material.dart';

import 'local_sample_school_identity_service.dart';
import 'official_face_id_models.dart';
import 'official_identity_session.dart';

const Color _ink = Color(0xFF0F172A);
const Color _muted = Color(0xFF64748B);
const Color _line = Color(0xFFE2E8F0);

/// TESTING ONLY. Plays the part of school staff in the local sample school:
/// review waiting Face ID registrations, approve or reject them, and see the
/// identity evidence the app has uploaded. The university's own admin system
/// replaces this once it is connected.
class SampleSchoolAdminView extends StatefulWidget {
  const SampleSchoolAdminView({super.key});

  @override
  State<SampleSchoolAdminView> createState() => _SampleSchoolAdminViewState();
}

class _SampleSchoolAdminViewState extends State<SampleSchoolAdminView> {
  LocalSampleSchoolIdentityService? _school;
  List<SampleSchoolReviewItem> _pending = const <SampleSchoolReviewItem>[];
  List<Map<String, Object?>> _evidence = const <Map<String, Object?>>[];
  bool _loading = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final school = await SchoolIdentityServices.instance.sampleSchool();
    if (school == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = 'The sample school is not active in this build.';
      });
      return;
    }
    final pending = await school.pendingReviews();
    final evidence = await school.storedEvidence();
    evidence.sort(
      (a, b) => (b['created_at']?.toString() ?? '').compareTo(
        a['created_at']?.toString() ?? '',
      ),
    );
    if (!mounted) return;
    setState(() {
      _school = school;
      _pending = pending;
      _evidence = evidence.take(30).toList();
      _loading = false;
    });
  }

  Future<void> _rebuildAll() async {
    final school = _school;
    if (school == null) return;
    setState(() {
      _loading = true;
      _message = 'Rebuilding approved Face IDs from their stored photos...';
    });
    final count = await school.rebuildActiveTemplates();
    if (!mounted) return;
    setState(
      () => _message =
          'Rebuilt $count approved Face ID${count == 1 ? '' : 's'} for the '
          'current face model.',
    );
    await _refresh();
  }

  Future<void> _openReview(SampleSchoolReviewItem item) async {
    final school = _school;
    if (school == null) return;
    final submission = await school.loadSubmission(item.submissionId);
    if (submission == null || !mounted) return;
    final message = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => _ReviewPage(school: school, submission: submission),
      ),
    );
    if (!mounted) return;
    setState(() => _message = message);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('Sample school admin'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    border: Border.all(color: const Color(0xFFFED7AA)),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    'Testing only. This stands in for the university admin '
                    'system. Approving rebuilds the Face ID from the photos '
                    'and signs it with the sample school key.',
                    style: TextStyle(color: _ink, height: 1.4),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _rebuildAll,
                  icon: const Icon(Icons.model_training_outlined),
                  label: const Text(
                    'Rebuild approved Face IDs for this face model',
                  ),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _message!,
                    style: const TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Text(
                  'Waiting for approval (${_pending.length})',
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                if (_pending.isEmpty)
                  const Text(
                    'No registrations are waiting.',
                    style: TextStyle(color: _muted),
                  ),
                for (final item in _pending)
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      side: const BorderSide(color: _line),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.face_outlined),
                      title: Text(item.studentId),
                      subtitle: Text(
                        '${item.photoCount} photos · ${_time(item.submittedAt)}'
                        '${item.replacesApprovedFaceId ? ' · replaces an approved Face ID' : ''}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openReview(item),
                    ),
                  ),
                const SizedBox(height: 22),
                Text(
                  'Identity evidence received (latest ${_evidence.length})',
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                if (_evidence.isEmpty)
                  const Text(
                    'No identity checks have been uploaded yet.',
                    style: TextStyle(color: _muted),
                  ),
                for (final record in _evidence)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      record['decision'] == 'identity_verified'
                          ? Icons.check_circle_outline
                          : Icons.report_outlined,
                      color: record['decision'] == 'identity_verified'
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFDC2626),
                    ),
                    title: Text(
                      '${record['check_kind']} · ${record['decision']}',
                    ),
                    subtitle: Text(
                      '${record['student_id']} · ${record['exam_id']} · '
                      '${record['created_at']}'
                      '${record['review_photo_jpeg_b64'] != null ? ' · photo kept for review' : ''}',
                    ),
                  ),
              ],
            ),
    );
  }

  static String _time(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class _ReviewPage extends StatefulWidget {
  const _ReviewPage({required this.school, required this.submission});

  final LocalSampleSchoolIdentityService school;
  final OfficialFaceIdSubmission submission;

  @override
  State<_ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<_ReviewPage> {
  bool _working = false;
  String? _message;

  Future<void> _approve() async {
    setState(() {
      _working = true;
      _message = 'Rebuilding the Face ID from the photos...';
    });
    final result = await widget.school.approve(widget.submission.submissionId);
    if (!mounted) return;
    if (result.approved) {
      Navigator.of(context).pop(result.message);
      return;
    }
    setState(() {
      _working = false;
      _message = result.message;
    });
  }

  Future<void> _reject() async {
    final controller = TextEditingController(
      text: 'The photos are not clear enough.',
    );
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject registration'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Reason shown to the student',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || !mounted) return;
    setState(() => _working = true);
    await widget.school.reject(widget.submission.submissionId, reason: reason);
    if (!mounted) return;
    Navigator.of(context).pop('Rejected ${widget.submission.studentId}.');
  }

  @override
  Widget build(BuildContext context) {
    final submission = widget.submission;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(title: Text('Review ${submission.studentId}')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            'Submitted ${submission.submittedAt.toLocal()} from '
            '${submission.capturePlatform} (${submission.captureDeviceClass}). '
            'Consent ${submission.consentVersion}.',
            style: const TextStyle(color: _muted, height: 1.4),
          ),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: MediaQuery.sizeOf(context).width > 700 ? 4 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: [
              for (final photo in submission.photos)
                Column(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          photo.jpegBytes,
                          fit: BoxFit.cover,
                          width: double.infinity,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${photo.title} · ${(photo.qualityScore * 100).round()}%',
                      style: const TextStyle(fontSize: 12, color: _ink),
                    ),
                  ],
                ),
            ],
          ),
          if (_message != null) ...[
            const SizedBox(height: 14),
            Text(
              _message!,
              style: const TextStyle(color: _ink, fontWeight: FontWeight.w700),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _working ? null : _approve,
                  icon: const Icon(Icons.verified_outlined),
                  label: const Text('Approve'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _working ? null : _reject,
                  icon: const Icon(Icons.block),
                  label: const Text('Reject'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
