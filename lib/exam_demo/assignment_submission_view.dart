import 'package:flutter/material.dart';

import 'student_assessment_hub_extras.dart';

class AssignmentSubmissionResult {
  const AssignmentSubmissionResult({
    required this.assignment,
    required this.answerText,
    required this.submittedAt,
    this.attachmentName,
  });

  final DemoAssignmentItem assignment;
  final String answerText;
  final DateTime submittedAt;
  final String? attachmentName;

  bool get hasAttachment => attachmentName != null && attachmentName!.trim().isNotEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
        'assignment_id': assignment.id,
        'course_code': assignment.course.code,
        'answer_text': answerText,
        'submitted_at': submittedAt.toIso8601String(),
        'attachment_name': attachmentName,
        'has_attachment': hasAttachment,
      };
}

class AssignmentSubmissionView extends StatefulWidget {
  const AssignmentSubmissionView({
    super.key,
    required this.assignment,
  });

  final DemoAssignmentItem assignment;

  @override
  State<AssignmentSubmissionView> createState() => _AssignmentSubmissionViewState();
}

class _AssignmentSubmissionViewState extends State<AssignmentSubmissionView> {
  final TextEditingController _answerController = TextEditingController();
  String? _attachmentName;
  bool _submitting = false;

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _answerController.text.trim().isNotEmpty ||
      (_attachmentName != null && _attachmentName!.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final assignment = widget.assignment;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Assignment submission',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9)],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AssignmentHeader(assignment: assignment),
                    const SizedBox(height: 16),
                    _InstructionsCard(assignment: assignment),
                    const SizedBox(height: 16),
                    _SubmissionCard(
                      answerController: _answerController,
                      attachmentName: _attachmentName,
                      submitting: _submitting,
                      canSubmit: _canSubmit,
                      onChanged: () => setState(() {}),
                      onAttachDemoFile: () => setState(() {
                        _attachmentName = 'assignment_response.pdf';
                      }),
                      onRemoveAttachment: () => setState(() {
                        _attachmentName = null;
                      }),
                      onSubmit: _submit,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_canSubmit || _submitting) return;
    setState(() => _submitting = true);

    final result = AssignmentSubmissionResult(
      assignment: widget.assignment,
      answerText: _answerController.text.trim(),
      attachmentName: _attachmentName,
      submittedAt: DateTime.now(),
    );

    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;

    Navigator.of(context).pop(result);
  }
}

class _AssignmentHeader extends StatelessWidget {
  const _AssignmentHeader({required this.assignment});

  final DemoAssignmentItem assignment;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A0F172A),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _HeaderBadge(label: assignment.course.code, icon: Icons.school_outlined),
              _HeaderBadge(label: assignment.accessLabel, icon: Icons.phone_android_outlined),
              _HeaderBadge(label: 'Due ${assignment.dueLabel}', icon: Icons.event_outlined),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            assignment.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${assignment.course.title} • Lecturer: ${assignment.course.lecturer}',
            style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 15),
          ),
        ],
      ),
    );
  }
}

class _InstructionsCard extends StatelessWidget {
  const _InstructionsCard({required this.assignment});

  final DemoAssignmentItem assignment;

  @override
  Widget build(BuildContext context) {
    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            icon: Icons.notes_outlined,
            title: 'Instructions',
          ),
          const SizedBox(height: 10),
          Text(
            assignment.instructions,
            style: const TextStyle(color: Color(0xFF334155), height: 1.45),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(label: assignment.graded ? 'Graded assignment' : 'Assignment'),
              _InfoChip(label: assignment.submissionMode),
              _InfoChip(label: assignment.status),
            ],
          ),
        ],
      ),
    );
  }
}

class _SubmissionCard extends StatelessWidget {
  const _SubmissionCard({
    required this.answerController,
    required this.attachmentName,
    required this.submitting,
    required this.canSubmit,
    required this.onChanged,
    required this.onAttachDemoFile,
    required this.onRemoveAttachment,
    required this.onSubmit,
  });

  final TextEditingController answerController;
  final String? attachmentName;
  final bool submitting;
  final bool canSubmit;
  final VoidCallback onChanged;
  final VoidCallback onAttachDemoFile;
  final VoidCallback onRemoveAttachment;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            icon: Icons.edit_note_outlined,
            title: 'Your submission',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: answerController,
            onChanged: (_) => onChanged(),
            minLines: 7,
            maxLines: 12,
            decoration: InputDecoration(
              hintText: 'Write your answer here...',
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (attachmentName == null)
            OutlinedButton.icon(
              onPressed: onAttachDemoFile,
              icon: const Icon(Icons.attach_file_outlined),
              label: const Text('Attach demo file'),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.insert_drive_file_outlined, color: Color(0xFF16A34A)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      attachmentName!,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove attachment',
                    onPressed: onRemoveAttachment,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: canSubmit && !submitting ? onSubmit : null,
              icon: submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined, size: 18),
              label: Text(submitting ? 'Submitting...' : 'Submit assignment'),
            ),
          ),
        ],
      ),
    );
  }
}

class _WhiteCard extends StatelessWidget {
  const _WhiteCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F172A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _HeaderBadge extends StatelessWidget {
  const _HeaderBadge({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFFBFDBFE), size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFDBEAFE),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF2563EB)),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF475569),
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
