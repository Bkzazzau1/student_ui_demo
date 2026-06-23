import 'package:flutter/material.dart';

import 'demo_exam_models.dart';

class DemoAssignmentItem {
  const DemoAssignmentItem({
    required this.id,
    required this.course,
    required this.title,
    required this.instructions,
    required this.dueDateIso,
    required this.submissionMode,
    required this.status,
    this.graded = false,
  });

  final String id;
  final DemoCourse course;
  final String title;
  final String instructions;
  final String dueDateIso;
  final String submissionMode;
  final String status;
  final bool graded;

  String get accessLabel => 'Mobile allowed • Submit work';

  String get dueLabel {
    final parsed = DateTime.tryParse(dueDateIso);
    if (parsed == null) return 'Open date';
    return '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
  }
}

class DemoFeedbackItem {
  const DemoFeedbackItem({
    required this.id,
    required this.course,
    required this.title,
    required this.feedback,
    required this.scoreLabel,
    required this.releasedDateIso,
  });

  final String id;
  final DemoCourse course;
  final String title;
  final String feedback;
  final String scoreLabel;
  final String releasedDateIso;

  String get releasedLabel {
    final parsed = DateTime.tryParse(releasedDateIso);
    if (parsed == null) return 'Released';
    return '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
  }
}

class DemoStudentHubExtras {
  const DemoStudentHubExtras._();

  static const DemoCourse _csc305 = DemoCourse(
    code: 'CSC 305',
    title: 'Secure Examination Systems',
    lecturer: 'Dr. A. Bello',
  );

  static const DemoCourse _gst204 = DemoCourse(
    code: 'GST 204',
    title: 'Entrepreneurship and Innovation',
    lecturer: 'Dr. M. Okafor',
  );

  static List<DemoAssignmentItem> assignmentsForDate(DateTime date) {
    final due = DateTime(date.year, date.month, date.day + 3);
    return <DemoAssignmentItem>[
      DemoAssignmentItem(
        id: 'assignment-csc305-report-${date.year}-${date.month}-${date.day}',
        course: _csc305,
        title: 'Short report: secure online assessment workflow',
        instructions:
            'Write a short report explaining how students should prepare before starting a secure online assessment.',
        dueDateIso: _dateIso(due),
        submissionMode: 'Text or PDF upload',
        status: 'Open',
        graded: true,
      ),
      DemoAssignmentItem(
        id: 'assignment-gst204-reflection-${date.year}-${date.month}-${date.day}',
        course: _gst204,
        title: 'Innovation reflection note',
        instructions:
            'Submit a one-page reflection on a digital service that can improve university administration.',
        dueDateIso: _dateIso(due.add(const Duration(days: 2))),
        submissionMode: 'Text response',
        status: 'Open',
      ),
    ];
  }

  static List<DemoFeedbackItem> feedbackForDate(DateTime date) {
    final released = DateTime(date.year, date.month, date.day - 1);
    return <DemoFeedbackItem>[
      DemoFeedbackItem(
        id: 'feedback-gst204-ca-${date.year}-${date.month}-${date.day}',
        course: _gst204,
        title: 'Continuous assessment quiz feedback',
        feedback:
            'Good progress. Review the entrepreneurship funding section before the next graded assessment.',
        scoreLabel: '8 / 10',
        releasedDateIso: _dateIso(released),
      ),
      DemoFeedbackItem(
        id: 'feedback-csc305-readiness-${date.year}-${date.month}-${date.day}',
        course: _csc305,
        title: 'Readiness self-check feedback',
        feedback:
            'Your answers show good readiness. Keep your device, camera, and internet prepared before exam day.',
        scoreLabel: 'Feedback only',
        releasedDateIso: _dateIso(released),
      ),
    ];
  }

  static String _dateIso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class StudentAssessmentHubExtrasPanel extends StatelessWidget {
  const StudentAssessmentHubExtrasPanel({
    super.key,
    required this.assignments,
    required this.feedbackItems,
  });

  final List<DemoAssignmentItem> assignments;
  final List<DemoFeedbackItem> feedbackItems;

  @override
  Widget build(BuildContext context) {
    if (assignments.isEmpty && feedbackItems.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 980;
        final itemWidth = twoColumns
            ? (constraints.maxWidth - 16) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            if (assignments.isNotEmpty)
              SizedBox(
                width: itemWidth,
                child: _HubExtraSection(
                  title: 'Assignments',
                  subtitle: 'Mobile allowed. Submit work from phone, tablet, iPad, or desktop.',
                  icon: Icons.upload_file_outlined,
                  count: assignments.length,
                  children: [
                    for (final item in assignments)
                      _AssignmentCard(item: item),
                  ],
                ),
              ),
            if (feedbackItems.isNotEmpty)
              SizedBox(
                width: itemWidth,
                child: _HubExtraSection(
                  title: 'Feedback',
                  subtitle: 'Lecturer feedback and released assessment comments.',
                  icon: Icons.rate_review_outlined,
                  count: feedbackItems.length,
                  children: [
                    for (final item in feedbackItems)
                      _FeedbackCard(item: item),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _HubExtraSection extends StatelessWidget {
  const _HubExtraSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.count,
    required this.children,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final int count;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xB3FFFFFF),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: const Color(0xFF16A34A)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.2,
                          ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              _ExtraCountPill(count: count),
            ],
          ),
          const SizedBox(height: 14),
          ...children.expand((child) => <Widget>[
                child,
                const SizedBox(height: 12),
              ]),
        ],
      ),
    );
  }
}

class _AssignmentCard extends StatelessWidget {
  const _AssignmentCard({required this.item});

  final DemoAssignmentItem item;

  @override
  Widget build(BuildContext context) {
    return _ExtraItemCard(
      accent: const Color(0xFF16A34A),
      icon: Icons.assignment_outlined,
      title: item.title,
      subtitle: '${item.course.code} - ${item.course.title}',
      body: item.instructions,
      chips: [
        item.graded ? 'Graded assignment' : 'Assignment',
        item.accessLabel,
        'Due ${item.dueLabel}',
        item.submissionMode,
      ],
      actionLabel: 'Open assignment',
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.item});

  final DemoFeedbackItem item;

  @override
  Widget build(BuildContext context) {
    return _ExtraItemCard(
      accent: const Color(0xFF2563EB),
      icon: Icons.chat_bubble_outline,
      title: item.title,
      subtitle: '${item.course.code} - ${item.course.title}',
      body: item.feedback,
      chips: [
        item.scoreLabel,
        'Released ${item.releasedLabel}',
        'Lecturer feedback',
      ],
      actionLabel: 'View feedback',
    );
  }
}

class _ExtraItemCard extends StatelessWidget {
  const _ExtraItemCard({
    required this.accent,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.chips,
    required this.actionLabel,
  });

  final Color accent;
  final IconData icon;
  final String title;
  final String subtitle;
  final String body;
  final List<String> chips;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 5, color: accent),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(icon, color: accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF334155),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF475569), height: 1.35),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final chip in chips) _ExtraInfoPill(label: chip),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.open_in_new_rounded, size: 17),
                    label: Text(actionLabel),
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

class _ExtraCountPill extends StatelessWidget {
  const _ExtraCountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text('$count', style: const TextStyle(fontWeight: FontWeight.w900)),
    );
  }
}

class _ExtraInfoPill extends StatelessWidget {
  const _ExtraInfoPill({required this.label});

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
