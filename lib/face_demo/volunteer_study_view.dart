import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'face_id_registration_capture_view.dart';
import 'volunteer_study_consent.dart';
import 'volunteer_study_session_capture_view.dart';
import 'volunteer_study_store.dart';

const Color _ink = Color(0xFF0F172A);
const Color _muted = Color(0xFF64748B);

/// Staff-only capture of volunteer photos for the Face ID threshold study
/// (`docs/identity/volunteer_calibration_protocol.md`).
///
/// Photos are taken with the app's own camera settings and face pipeline,
/// kept encrypted on this device, and exported as plain JPEGs in the layout
/// `ai_runtime/face_identity_calibration.py` reads. Volunteers are study
/// codes only; no names are entered.
class VolunteerStudyView extends StatefulWidget {
  const VolunteerStudyView({super.key, this.store});

  /// For tests; the device store is used when null.
  final VolunteerStudyStore? store;

  @override
  State<VolunteerStudyView> createState() => _VolunteerStudyViewState();
}

class _VolunteerStudyViewState extends State<VolunteerStudyView> {
  VolunteerStudyStore? _store;
  bool _loading = true;
  bool _unsupported = false;
  String _deviceLabel = '';
  List<VolunteerStudyRecord> _volunteers = const <VolunteerStudyRecord>[];
  String? _message;
  final TextEditingController _deviceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void dispose() {
    _deviceController.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final store = widget.store ?? await VolunteerStudyStore.openOnDevice();
    if (!mounted) return;
    if (store == null) {
      setState(() {
        _loading = false;
        _unsupported = true;
      });
      return;
    }
    _store = store;
    _deviceLabel = await store.lastDeviceLabel() ?? '';
    _deviceController.text = _deviceLabel;
    await _reload();
  }

  Future<void> _reload() async {
    final store = _store;
    if (store == null) return;
    final records = <VolunteerStudyRecord>[];
    for (final code in await store.volunteerCodes()) {
      final record = await store.volunteer(code);
      if (record != null) records.add(record);
    }
    if (!mounted) return;
    setState(() {
      _volunteers = records;
      _loading = false;
    });
  }

  Future<void> _saveDeviceLabel() async {
    final label = VolunteerStudy.sanitizeDeviceLabel(_deviceController.text);
    if (!VolunteerStudy.isValidDeviceLabel(label)) {
      setState(
        () => _message =
            'Use a device label of 3 to 40 letters, digits or dashes, for '
            'example laptop-dell-3520.',
      );
      return;
    }
    await _store!.rememberDeviceLabel(label);
    if (!mounted) return;
    setState(() {
      _deviceLabel = label;
      _deviceController.text = label;
      _message = 'This device is $label.';
    });
  }

  Future<void> _addVolunteer() async {
    final added = await showDialog<_NewVolunteer>(
      context: context,
      builder: (_) => const _AddVolunteerDialog(),
    );
    if (added == null || !mounted) return;
    try {
      await _store!.enrol(
        code: added.code,
        deviceLabel: _deviceLabel,
        consentConfirmed: true,
        spoofTestConsent: added.spoofTestConsent,
      );
      await _reload();
      if (!mounted) return;
      await _openVolunteer(added.code);
    } on VolunteerStudyException catch (error) {
      if (mounted) setState(() => _message = error.message);
    }
  }

  Future<void> _openVolunteer(String code) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _VolunteerPage(
          store: _store!,
          code: code,
          deviceLabel: _deviceLabel,
        ),
      ),
    );
    await _reload();
  }

  Future<Directory> _exportRoot() async {
    if (Platform.isAndroid) {
      // App-specific external storage: reachable over USB, no extra
      // permission, removed with the app.
      final external = await getExternalStorageDirectory();
      if (external != null) {
        return Directory(
          '${external.path}${Platform.pathSeparator}study_exports',
        );
      }
    }
    final documents = await getApplicationDocumentsDirectory();
    return Directory(
      '${documents.path}${Platform.pathSeparator}KSLAS study exports',
    );
  }

  Future<void> _export() async {
    final store = _store;
    if (store == null || _deviceLabel.isEmpty) return;
    setState(() => _message = 'Exporting...');
    try {
      final root = await _exportRoot();
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(RegExp(r'[^0-9T]'), '')
          .substring(0, 15);
      final result = await store.exportTo(
        Directory(
          '${root.path}${Platform.pathSeparator}'
          'kslas_study_${_deviceLabel}_$stamp',
        ),
        deviceLabel: _deviceLabel,
      );
      if (!mounted) return;
      setState(() => _message = null);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Study photos exported'),
          content: SelectableText(
            '${result.photos} photos of ${result.volunteers} volunteers in:\n\n'
            '${result.folder.path}\n\n'
            'Copy this folder\'s contents into the study folder on the '
            'analysis computer (exports from several devices go into the same '
            'study folder), run the calibration tool, then delete the copies.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _message = 'Export failed: $error');
    }
  }

  Future<void> _deleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all study photos on this device?'),
        content: const Text(
          'This removes every volunteer\'s photos and records from this '
          'device. Exports already copied elsewhere are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _store!.deleteAll();
    await _reload();
    if (mounted) setState(() => _message = 'All study photos were deleted.');
  }

  String _summary(VolunteerStudyRecord record) {
    final parts = <String>[
      record.registration == null
          ? 'Not registered on this device'
          : 'Registered on ${record.registration!.deviceLabel}',
    ];
    if (_deviceLabel.isNotEmpty) {
      final done = StudySession.values
          .map(
            (session) => record.hasSession(_deviceLabel, session)
                ? session.code.toUpperCase()
                : '-',
          )
          .join(' ');
      parts.add('Sessions here: $done');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(title: const Text('Volunteer study')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _unsupported
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'The volunteer study needs protected storage and the face AI, '
                'which this device does not have.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    'Staff only. Photos for the Face ID threshold study, taken '
                    'with this app\'s camera settings. They are stored '
                    'encrypted on this device until you export them. Use '
                    'study codes, never names. Delete everything within 30 '
                    'days of the final report.',
                    style: TextStyle(color: _ink, height: 1.4),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'This device',
                  style: TextStyle(color: _ink, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _deviceController,
                        decoration: const InputDecoration(
                          labelText: 'Device label',
                          hintText:
                              'laptop-dell-3520, tablet-samsung-a8, ipad-10',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _saveDeviceLabel(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _saveDeviceLabel,
                      child: const Text('Save'),
                    ),
                  ],
                ),
                if (_message != null) ...[
                  const SizedBox(height: 10),
                  Text(_message!, style: const TextStyle(color: _ink)),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Volunteers (${_volunteers.length})',
                        style: const TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _deviceLabel.isEmpty ? null : _addVolunteer,
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      label: const Text('Add volunteer'),
                    ),
                  ],
                ),
                if (_deviceLabel.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Save this device\'s label first.',
                      style: TextStyle(color: _muted),
                    ),
                  ),
                const SizedBox(height: 8),
                for (final record in _volunteers)
                  Card(
                    elevation: 0,
                    child: ListTile(
                      title: Text(
                        record.code,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(_summary(record)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _deviceLabel.isEmpty
                          ? null
                          : () => _openVolunteer(record.code),
                    ),
                  ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: _volunteers.isEmpty || _deviceLabel.isEmpty
                      ? null
                      : _export,
                  icon: const Icon(Icons.drive_file_move_outline),
                  label: const Text('Export study photos'),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _volunteers.isEmpty ? null : _deleteAll,
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: const Text('Delete all study photos on this device'),
                ),
              ],
            ),
    );
  }
}

class _NewVolunteer {
  const _NewVolunteer(this.code, this.spoofTestConsent);

  final String code;
  final bool spoofTestConsent;
}

class _AddVolunteerDialog extends StatefulWidget {
  const _AddVolunteerDialog();

  @override
  State<_AddVolunteerDialog> createState() => _AddVolunteerDialogState();
}

class _AddVolunteerDialogState extends State<_AddVolunteerDialog> {
  final TextEditingController _code = TextEditingController();
  bool _consent = false;
  bool _spoofTest = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  String? get _normalized => VolunteerStudy.normalizeCode(_code.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Add a volunteer'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _code,
                decoration: const InputDecoration(
                  labelText: 'Study code',
                  hintText: 'v001',
                  helperText: 'From the signed consent form. Never a name.',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              Text(
                VolunteerStudyConsent.title,
                style: theme.textTheme.titleSmall,
              ),
              for (final section in VolunteerStudyConsent.sections)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${section.heading}. ',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(text: section.body),
                      ],
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _consent,
                onChanged: (value) => setState(() => _consent = value == true),
                title: const Text(VolunteerStudyConsent.staffConfirmation),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _spoofTest,
                onChanged: (value) =>
                    setState(() => _spoofTest = value == true),
                title: const Text(VolunteerStudyConsent.spoofTestConfirmation),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _consent && _normalized != null
              ? () =>
                    Navigator.of(context)
                        .pop(_NewVolunteer(_normalized!, _spoofTest))
              : null,
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _VolunteerPage extends StatefulWidget {
  const _VolunteerPage({
    required this.store,
    required this.code,
    required this.deviceLabel,
  });

  final VolunteerStudyStore store;
  final String code;
  final String deviceLabel;

  @override
  State<_VolunteerPage> createState() => _VolunteerPageState();
}

class _VolunteerPageState extends State<_VolunteerPage> {
  VolunteerStudyRecord? _record;
  String? _message;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final record = await widget.store.volunteer(widget.code);
    if (mounted) setState(() => _record = record);
  }

  Future<void> _register() async {
    final capture = await Navigator.of(context).push<FaceIdRegistrationCapture>(
      MaterialPageRoute<FaceIdRegistrationCapture>(
        builder: (_) => const FaceIdRegistrationCaptureView(),
      ),
    );
    if (capture == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final record = await widget.store.saveRegistration(
        widget.code,
        deviceLabel: widget.deviceLabel,
        photos: [
          for (final photo in capture.photos)
            StudyRegistrationPhoto(
              poseCode: photo.poseCode,
              jpegBytes: photo.jpegBytes,
              qualityScore: photo.qualityScore,
            ),
        ],
      );
      if (mounted) {
        setState(() {
          _record = record;
          _message = 'Registration saved: ${capture.photos.length} photos.';
        });
      }
    } on VolunteerStudyException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _capture(StudySession session) async {
    final capture = await Navigator.of(context).push<StudySessionCapture>(
      MaterialPageRoute<StudySessionCapture>(
        builder: (_) => VolunteerStudySessionCaptureView(
          volunteerCode: widget.code,
          session: session,
        ),
      ),
    );
    if (capture == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final record = await widget.store.saveSession(
        widget.code,
        deviceLabel: widget.deviceLabel,
        session: session,
        photos: capture.photos,
        attempts: capture.attempts,
        rejected: capture.rejected,
      );
      if (mounted) {
        setState(() {
          _record = record;
          _message = '${session.title} saved.';
        });
      }
    } on VolunteerStudyException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _withdraw() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${widget.code}?'),
        content: const Text(
          'Use this when a volunteer withdraws. It deletes their photos and '
          'record on this device. Delete them from other study devices and '
          'from any exports too.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.store.deleteVolunteer(widget.code);
    if (mounted) Navigator.of(context).pop();
  }

  String _date(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final record = _record;
    final registration = record?.registration;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(title: Text('Volunteer ${widget.code}')),
      body: record == null
          ? const Center(child: CircularProgressIndicator())
          : AbsorbPointer(
              absorbing: _busy,
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  Text(
                    'Consent ${record.consentVersion}, confirmed '
                    '${_date(record.consentConfirmedAt)}'
                    '${record.spoofTestConsent ? ' (spoofing test agreed)' : ''}.',
                    style: const TextStyle(color: _muted),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '1. Registration (once per volunteer, good light)',
                    style: TextStyle(color: _ink, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    registration == null
                        ? 'Uses the same guided 7-pose screen as students. In '
                              'the study, the photos stay on this device.'
                        : 'Done on ${registration.deviceLabel}, '
                              '${_date(registration.capturedAt)}: '
                              '${registration.poses.length} photos.',
                    style: const TextStyle(color: _muted),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _register,
                    icon: const Icon(Icons.face_retouching_natural_outlined),
                    label: Text(
                      registration == null
                          ? 'Take registration photos'
                          : 'Take registration photos again',
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '2. Exam photos on ${widget.deviceLabel}',
                    style: const TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final session in StudySession.values)
                    Card(
                      elevation: 0,
                      child: ListTile(
                        leading: Icon(
                          record.hasSession(widget.deviceLabel, session)
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: record.hasSession(widget.deviceLabel, session)
                              ? Colors.green
                              : _muted,
                        ),
                        title: Text(session.title),
                        subtitle: Text(
                          record.hasSession(widget.deviceLabel, session)
                              ? 'Done ${_date(record.sessions[widget.deviceLabel]![session.code]!.capturedAt)}. Tap to take it again.'
                              : session.instruction,
                        ),
                        onTap: () => _capture(session),
                      ),
                    ),
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    Text(_message!, style: const TextStyle(color: _ink)),
                  ],
                  const SizedBox(height: 24),
                  TextButton.icon(
                    onPressed: _withdraw,
                    icon: const Icon(Icons.person_remove_outlined),
                    label: const Text('Delete this volunteer (withdrawal)'),
                  ),
                ],
              ),
            ),
    );
  }
}
