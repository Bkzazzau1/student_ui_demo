import 'package:flutter/material.dart';

import 'demo_exam_models.dart';

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
  bool _submitted = false;

  static const List<String> _topics = <String>[
    'Exam experience',
    'Question clarity',
    'Technical issue',
    'Result concern',
    'Other',
  ];

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  void _submit() {
    if (_message.text.trim().isEmpty) return;
    setState(() => _submitted = true);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Feedback saved. Thank you.')));
  }

  @override
  Widget build(BuildContext context) {
    final assessment = widget.result.assessment;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(title: const Text('Student feedback')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    assessment.course.code,
                    style: const TextStyle(
                      color: Color(0xFFBFDBFE),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    assessment.title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    assessment.course.title,
                    style: const TextStyle(color: Color(0xFFCBD5E1)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Write your feedback',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedTopic,
                    decoration: const InputDecoration(
                      labelText: 'Feedback topic',
                      border: OutlineInputBorder(),
                    ),
                    items: _topics
                        .map(
                          (topic) => DropdownMenuItem<String>(
                            value: topic,
                            child: Text(topic),
                          ),
                        )
                        .toList(),
                    onChanged: _submitted
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _selectedTopic = value);
                            }
                          },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _message,
                    enabled: !_submitted,
                    minLines: 6,
                    maxLines: 10,
                    decoration: const InputDecoration(
                      labelText: 'Your message',
                      hintText:
                          'Write what you want the school to know about this exam or assessment.',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: !_submitted && _message.text.trim().isNotEmpty
                        ? _submit
                        : null,
                    icon: Icon(
                      _submitted
                          ? Icons.check_circle_outline
                          : Icons.send_outlined,
                    ),
                    label: Text(
                      _submitted ? 'Feedback saved' : 'Send feedback',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
