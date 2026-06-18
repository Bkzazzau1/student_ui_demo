import 'package:flutter/material.dart';

import 'demo_exam_models.dart';

class DemoExamResultView extends StatelessWidget {
  const DemoExamResultView({super.key, required this.result});

  final DemoExamResult result;

  @override
  Widget build(BuildContext context) {
    final duration = result.endedAt.difference(result.startedAt);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(title: const Text('Exam result')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.assessment.title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${result.assessment.course.code} - ${result.assessment.course.title}',
                    style: const TextStyle(color: Color(0xFFCBD5E1)),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '${result.percent}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 54,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '${result.scoredMarks} of ${result.totalMarks} marks',
                    style: const TextStyle(color: Color(0xFFCBD5E1)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _ResultCard(
              title: 'Submission summary',
              rows: [
                ('Started', result.startedAt.toLocal().toString()),
                ('Ended', result.endedAt.toLocal().toString()),
                (
                  'Duration used',
                  '${duration.inMinutes} min ${duration.inSeconds % 60} sec',
                ),
                ('Face ID status', _faceIdLabel(result.agentDecision)),
                ('Proctoring status', _proctoringLabel(result.agentDecision)),
                (
                  'Evidence manifest',
                  result.proctoringManifestPath ?? 'Not required',
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: () =>
                      Navigator.of(context).popUntil((route) => route.isFirst),
                  icon: const Icon(Icons.home_outlined),
                  label: const Text('Back to assessments'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _faceIdLabel(String decision) {
    if (decision == 'agentic_proctoring_ready' ||
        decision == 'face_id_verified') {
      return 'Verified for demo attempt';
    }
    return 'Not required for this assessment';
  }

  String _proctoringLabel(String decision) {
    return decision == 'agentic_proctoring_ready'
        ? 'Agentic pre-exam review approved'
        : 'Not required for this assessment';
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.title, required this.rows});

  final String title;
  final List<(String, String)> rows;

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
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          ...rows.map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 160,
                    child: Text(
                      row.$1,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Expanded(child: Text(row.$2)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
