import 'package:flutter/material.dart';

import 'demo_exam_models.dart';

const Color _brand = Color(0xFF0F4C81);
const Color _brandDark = Color(0xFF0B1220);
const Color _surface = Colors.white;
const Color _surfaceSoft = Color(0xFFF8FAFC);
const Color _line = Color(0xFFE2E8F0);
const Color _muted = Color(0xFF64748B);
const Color _success = Color(0xFF16A34A);
const Color _warning = Color(0xFFF59E0B);
const Color _purple = Color(0xFF7C3AED);

class StudentExamFeedbackView extends StatefulWidget {
  const StudentExamFeedbackView({super.key, required this.result});

  final DemoExamResult result;

  @override
  State<StudentExamFeedbackView> createState() =>
      _StudentExamFeedbackViewState();
}

class _StudentExamFeedbackViewState extends State<StudentExamFeedbackView> {
  final TextEditingController _message = TextEditingController();
  String _selectedTopic = 'Exam experience';
  String _selectedFeeling = 'Good';
  bool _submitted = false;

  static const List<String> _topics = <String>[
    'Exam experience',
    'Question clarity',
    'Technical issue',
    'Result concern',
    'Other',
  ];

  static const List<String> _feelings = <String>[
    'Excellent',
    'Good',
    'Fair',
    'Needs attention',
  ];

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  void _submit() {
    if (_message.text.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _submitted = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Feedback saved. Thank you.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final assessment = widget.result.assessment;
    final canSubmit = !_submitted && _message.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Student feedback',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: _line),
        ),
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
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 90),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _FeedbackHero(assessment: assessment),
                      const SizedBox(height: 16),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth >= 900;
                          final form = _FeedbackFormCard(
                            selectedTopic: _selectedTopic,
                            selectedFeeling: _selectedFeeling,
                            message: _message,
                            submitted: _submitted,
                            canSubmit: canSubmit,
                            topics: _topics,
                            feelings: _feelings,
                            onTopicChanged: (value) {
                              if (value != null) setState(() => _selectedTopic = value);
                            },
                            onFeelingChanged: (value) => setState(() => _selectedFeeling = value),
                            onMessageChanged: () => setState(() {}),
                            onSubmit: _submit,
                          );
                          final side = _FeedbackSidePanel(
                            submitted: _submitted,
                            topic: _selectedTopic,
                            feeling: _selectedFeeling,
                          );

                          if (!wide) {
                            return Column(
                              children: [form, const SizedBox(height: 16), side],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 7, child: form),
                              const SizedBox(width: 16),
                              Expanded(flex: 4, child: side),
                            ],
                          );
                        },
                      ),
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
}

class _FeedbackHero extends StatelessWidget {
  const _FeedbackHero({required this.assessment});

  final DemoAssessment assessment;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F0F172A),
            blurRadius: 26,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_brandDark, Color(0xFF113A63), _brand],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 720;
            final details = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _GlassTag(text: assessment.course.code),
                    _GlassTag(text: assessment.graded ? 'Graded activity' : 'Learning activity'),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Share your assessment experience',
                  style: TextStyle(
                    color: Color(0xFFDBEAFE),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  assessment.title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${assessment.course.title} • ${assessment.course.lecturer}',
                  style: const TextStyle(
                    color: Color(0xFFE2E8F0),
                    fontSize: 16,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            );
            final iconBox = Container(
              width: wide ? 180 : double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.rate_review_outlined, color: Colors.white, size: 30),
                  SizedBox(height: 12),
                  Text(
                    'Your feedback helps the school improve assessment quality.',
                    style: TextStyle(
                      color: Color(0xFFCBD5E1),
                      height: 1.4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            );

            if (!wide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [details, const SizedBox(height: 18), iconBox],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: details),
                const SizedBox(width: 22),
                iconBox,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FeedbackFormCard extends StatelessWidget {
  const _FeedbackFormCard({
    required this.selectedTopic,
    required this.selectedFeeling,
    required this.message,
    required this.submitted,
    required this.canSubmit,
    required this.topics,
    required this.feelings,
    required this.onTopicChanged,
    required this.onFeelingChanged,
    required this.onMessageChanged,
    required this.onSubmit,
  });

  final String selectedTopic;
  final String selectedFeeling;
  final TextEditingController message;
  final bool submitted;
  final bool canSubmit;
  final List<String> topics;
  final List<String> feelings;
  final ValueChanged<String?> onTopicChanged;
  final ValueChanged<String> onFeelingChanged;
  final VoidCallback onMessageChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _line),
        boxShadow: const [
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
                child: const Icon(Icons.edit_note_outlined, color: _brand),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Write your feedback',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: _brandDark,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Tell the school what went well, what was unclear, or what needs attention.',
            style: TextStyle(
              color: _muted,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
            initialValue: selectedTopic,
            decoration: _fieldDecoration(
              label: 'Feedback topic',
              icon: Icons.topic_outlined,
            ),
            items: topics
                .map(
                  (topic) => DropdownMenuItem<String>(
                    value: topic,
                    child: Text(topic),
                  ),
                )
                .toList(),
            onChanged: submitted ? null : onTopicChanged,
          ),
          const SizedBox(height: 16),
          Text(
            'How was the experience?',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: _brandDark,
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final feeling in feelings)
                _FeelingChip(
                  label: feeling,
                  selected: selectedFeeling == feeling,
                  enabled: !submitted,
                  onTap: () => onFeelingChanged(feeling),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: message,
            enabled: !submitted,
            minLines: 7,
            maxLines: 12,
            decoration: _fieldDecoration(
              label: 'Your message',
              icon: Icons.message_outlined,
              hint:
                  'Write what you want the school to know about this exam or assessment.',
            ),
            onChanged: (_) => onMessageChanged(),
          ),
          const SizedBox(height: 16),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: submitted || !canSubmit
                  ? const LinearGradient(colors: [Color(0xFFE2E8F0), Color(0xFFCBD5E1)])
                  : const LinearGradient(colors: [_brand, Color(0xFF1D4ED8), _success]),
              borderRadius: BorderRadius.circular(14),
              boxShadow: submitted || !canSubmit
                  ? const []
                  : const [
                      BoxShadow(
                        color: Color(0x200F4C81),
                        blurRadius: 14,
                        offset: Offset(0, 8),
                      ),
                    ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: canSubmit ? onSubmit : null,
                child: SizedBox(
                  height: 52,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        submitted ? Icons.check_circle_outline : Icons.send_outlined,
                        color: submitted || canSubmit ? Colors.white : const Color(0xFF64748B),
                        size: 20,
                      ),
                      const SizedBox(width: 9),
                      Text(
                        submitted ? 'Feedback saved' : 'Send feedback',
                        style: TextStyle(
                          color: submitted || canSubmit ? Colors.white : const Color(0xFF64748B),
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, size: 20),
      filled: true,
      fillColor: _surfaceSoft,
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
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _line),
      ),
    );
  }
}

class _FeelingChip extends StatelessWidget {
  const _FeelingChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(label);
    return Material(
      color: selected ? color : _surfaceSoft,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            border: Border.all(color: selected ? color : _line),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                size: 16,
                color: selected ? Colors.white : color,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : _brandDark,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _colorFor(String value) {
    switch (value) {
      case 'Excellent':
        return _success;
      case 'Good':
        return _brand;
      case 'Fair':
        return _warning;
      default:
        return _purple;
    }
  }
}

class _FeedbackSidePanel extends StatelessWidget {
  const _FeedbackSidePanel({
    required this.submitted,
    required this.topic,
    required this.feeling,
  });

  final bool submitted;
  final String topic;
  final String feeling;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _line),
            boxShadow: const [
              BoxShadow(
                color: Color(0x080F172A),
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                submitted ? Icons.verified_outlined : Icons.info_outline,
                color: submitted ? _success : _brand,
                size: 30,
              ),
              const SizedBox(height: 12),
              Text(
                submitted ? 'Feedback received' : 'Before you send',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: _brandDark,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                submitted
                    ? 'Thank you. Your feedback has been saved for review.'
                    : 'Be clear and respectful. Include only what will help the school understand your experience.',
                style: const TextStyle(
                  color: _muted,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              _SummaryLine(label: 'Topic', value: topic),
              _SummaryLine(label: 'Experience', value: feeling),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            border: Border.all(color: const Color(0xFFFDE68A)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline, color: _warning, size: 21),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Your feedback is linked to this assessment record and helps improve the student experience.',
                  style: TextStyle(
                    color: Color(0xFF78350F),
                    height: 1.4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: const TextStyle(color: _muted, fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: _brandDark, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassTag extends StatelessWidget {
  const _GlassTag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
      ),
    );
  }
}
