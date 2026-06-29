import 'package:flutter/material.dart';

import 'student_assessment_hub_extras.dart';

const Color _brand = Color(0xFF0F4C81);
const Color _brandDark = Color(0xFF0B1220);
const Color _surface = Colors.white;
const Color _surfaceSoft = Color(0xFFF8FAFC);
const Color _line = Color(0xFFE2E8F0);
const Color _muted = Color(0xFF64748B);
const Color _success = Color(0xFF16A34A);
const Color _warning = Color(0xFFF59E0B);
const Color _purple = Color(0xFF7C3AED);

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
        elevation: 0,
        titleSpacing: 0,
        title: const Text(
          'Assignment submission',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: _line),
        ),
      ),
      bottomNavigationBar: _BottomSubmitBar(
        canSubmit: _canSubmit,
        submitting: _submitting,
        hasAttachment: _attachmentName != null,
        onSubmit: _confirmSubmit,
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF8FAFC), Color(0xFFEFF4FA)],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 118),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1080),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _AssignmentHero(assignment: assignment),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth >= 900;
                          final instructions = _InstructionsCard(assignment: assignment);
                          final submission = _SubmissionCard(
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
                          );

                          if (!wide) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                instructions,
                                const SizedBox(height: 12),
                                submission,
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 4, child: instructions),
                              const SizedBox(width: 12),
                              Expanded(flex: 6, child: submission),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      const _SubmissionNotice(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmSubmit() async {
    if (!_canSubmit || _submitting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit assignment?'),
        content: const Text(
          'Please confirm that your answer and attachment are ready for submission.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Review again'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _submit();
  }

  Future<void> _submit() async {
    if (!_canSubmit || _submitting) return;
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);

    final result = AssignmentSubmissionResult(
      assignment: widget.assignment,
      answerText: _answerController.text.trim(),
      attachmentName: _attachmentName,
      submittedAt: DateTime.now(),
    );

    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    Navigator.of(context).pop(result);
  }
}

class _AssignmentHero extends StatelessWidget {
  const _AssignmentHero({required this.assignment});

  final DemoAssignmentItem assignment;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(color: Color(0x1A0F172A), blurRadius: 20, offset: Offset(0, 10)),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_brandDark, Color(0xFF113A63), _brand],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            final details = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _GlassTag(icon: Icons.school_outlined, text: assignment.course.code),
                    _GlassTag(icon: Icons.event_outlined, text: 'Due ${assignment.dueLabel}'),
                    _GlassTag(icon: Icons.assignment_turned_in_outlined, text: assignment.status),
                  ],
                ),
                const SizedBox(height: 11),
                Text(
                  assignment.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.35,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${assignment.course.title} • Lecturer: ${assignment.course.lecturer}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFE2E8F0),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            );
            final side = Container(
              width: wide ? 230 : double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  const Icon(Icons.upload_file_outlined, color: Colors.white, size: 26),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          assignment.submissionMode,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          assignment.graded ? 'Graded assignment' : 'Learning assignment',
                          style: const TextStyle(color: Color(0xFFCBD5E1), fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );

            if (!wide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [details, const SizedBox(height: 12), side],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: details),
                const SizedBox(width: 18),
                side,
              ],
            );
          },
        ),
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
            style: const TextStyle(
              color: Color(0xFF334155),
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          const _MiniLabel(title: 'Submission details'),
          const SizedBox(height: 8),
          _DetailRow(label: 'Course', value: '${assignment.course.code} - ${assignment.course.title}'),
          _DetailRow(label: 'Due date', value: assignment.dueLabel),
          _DetailRow(label: 'Mode', value: assignment.submissionMode),
          _DetailRow(label: 'Status', value: assignment.status),
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
  });

  final TextEditingController answerController;
  final String? attachmentName;
  final bool submitting;
  final bool canSubmit;
  final VoidCallback onChanged;
  final VoidCallback onAttachDemoFile;
  final VoidCallback onRemoveAttachment;

  @override
  Widget build(BuildContext context) {
    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: _SectionTitle(
                  icon: Icons.edit_note_outlined,
                  title: 'Your submission',
                ),
              ),
              _ReadyMiniStatus(canSubmit: canSubmit),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Write your response and attach a supporting file if required.',
            style: TextStyle(color: _muted, height: 1.35, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: answerController,
            onChanged: (_) => onChanged(),
            minLines: 4,
            maxLines: 7,
            decoration: InputDecoration(
              hintText: 'Write your answer here...',
              filled: true,
              fillColor: _surfaceSoft,
              contentPadding: const EdgeInsets.all(16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: _line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: _line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: _brand, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _AttachmentArea(
            attachmentName: attachmentName,
            onAttachDemoFile: onAttachDemoFile,
            onRemoveAttachment: onRemoveAttachment,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(canSubmit ? Icons.check_circle_outline : Icons.info_outline, color: canSubmit ? _success : _muted, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  canSubmit ? 'Ready to submit after review.' : 'Answer or attachment required.',
                  style: TextStyle(color: canSubmit ? _success : _muted, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReadyMiniStatus extends StatelessWidget {
  const _ReadyMiniStatus({required this.canSubmit});

  final bool canSubmit;

  @override
  Widget build(BuildContext context) {
    final color = canSubmit ? _success : _muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        canSubmit ? 'Ready' : 'Draft',
        style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12),
      ),
    );
  }
}

class _AttachmentArea extends StatelessWidget {
  const _AttachmentArea({
    required this.attachmentName,
    required this.onAttachDemoFile,
    required this.onRemoveAttachment,
  });

  final String? attachmentName;
  final VoidCallback onAttachDemoFile;
  final VoidCallback onRemoveAttachment;

  @override
  Widget build(BuildContext context) {
    if (attachmentName == null) {
      return Material(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onAttachDemoFile,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: const Row(
              children: [
                Icon(Icons.attach_file_outlined, color: _warning),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Attach file', style: TextStyle(color: _brandDark, fontWeight: FontWeight.w900)),
                      SizedBox(height: 2),
                      Text('Add PDF or supporting document where required.', style: TextStyle(color: _muted, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Icon(Icons.add_circle_outline, color: _warning),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _success.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.insert_drive_file_outlined, color: _success),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Attached file', style: TextStyle(color: _success, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(attachmentName!, style: const TextStyle(color: _brandDark, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove attachment',
            onPressed: onRemoveAttachment,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _SubmissionNotice extends StatelessWidget {
  const _SubmissionNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        border: Border.all(color: const Color(0xFFBFDBFE)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_outlined, color: _brand, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'After submission, the assignment will be recorded for the lecturer to review.',
              style: TextStyle(color: Color(0xFF1E3A8A), height: 1.4, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomSubmitBar extends StatelessWidget {
  const _BottomSubmitBar({
    required this.canSubmit,
    required this.submitting,
    required this.hasAttachment,
    required this.onSubmit,
  });

  final bool canSubmit;
  final bool submitting;
  final bool hasAttachment;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: _line)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 560;
            final helper = Text(
              hasAttachment ? 'Attachment added. Review before submitting.' : 'Answer or attachment required.',
              style: TextStyle(color: canSubmit ? _success : _muted, fontWeight: FontWeight.w800),
            );
            final button = DecoratedBox(
              decoration: BoxDecoration(
                gradient: canSubmit && !submitting
                    ? const LinearGradient(colors: [_brand, Color(0xFF1D4ED8), _success])
                    : const LinearGradient(colors: [Color(0xFFE2E8F0), Color(0xFFCBD5E1)]),
                borderRadius: BorderRadius.circular(14),
                boxShadow: canSubmit && !submitting
                    ? const [BoxShadow(color: Color(0x200F4C81), blurRadius: 14, offset: Offset(0, 8))]
                    : const [],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: canSubmit && !submitting ? onSubmit : null,
                  child: SizedBox(
                    height: 46,
                    width: compact ? double.infinity : 210,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (submitting)
                          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        else
                          Icon(Icons.send_outlined, color: canSubmit ? Colors.white : _muted, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          submitting ? 'Submitting...' : 'Submit assignment',
                          style: TextStyle(color: canSubmit ? Colors.white : _muted, fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );

            if (compact) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [helper, const SizedBox(height: 8), button],
              );
            }
            return Row(children: [Expanded(child: helper), button]);
          },
        ),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _line),
        boxShadow: const [BoxShadow(color: Color(0x080F172A), blurRadius: 16, offset: Offset(0, 8))],
      ),
      child: child,
    );
  }
}

class _GlassTag extends StatelessWidget {
  const _GlassTag({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 15),
          const SizedBox(width: 7),
          Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
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
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(13)),
          child: Icon(icon, color: _brand, size: 21),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(color: _brandDark, fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class _MiniLabel extends StatelessWidget {
  const _MiniLabel({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: const TextStyle(color: _brandDark, fontWeight: FontWeight.w900));
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 82, child: Text(label, style: const TextStyle(color: _muted, fontWeight: FontWeight.w800))),
          Expanded(child: Text(value, style: const TextStyle(color: _brandDark, fontWeight: FontWeight.w800))),
        ],
      ),
    );
  }
}
