import 'package:flutter/material.dart';

import 'demo_exam_models.dart';

class GradeBookView extends StatelessWidget {
  const GradeBookView({super.key});

  static const _records = <GradeBookRecord>[
    GradeBookRecord(
      course: DemoCourse(
        code: 'CSC 305',
        title: 'Secure Examination Systems',
        lecturer: 'Dr. A. Bello',
      ),
      assessmentTitle: 'Sample supervised exam for today',
      assessmentType: 'Examination',
      dateLabel: 'Current demo',
      scoreLabel: 'Available',
      gradeLabel: 'Ready',
      status: GradeBookStatus.available,
      note: 'Open this sample exam anytime for testing.',
    ),
    GradeBookRecord(
      course: DemoCourse(
        code: 'GST 204',
        title: 'Entrepreneurship and Innovation',
        lecturer: 'Dr. M. Okafor',
      ),
      assessmentTitle: 'Continuous assessment quiz',
      assessmentType: 'Graded assessment',
      dateLabel: '26/06/2026',
      scoreLabel: '8 / 10',
      gradeLabel: 'A',
      status: GradeBookStatus.passed,
      note: 'Good progress. Review the lecturer feedback.',
    ),
    GradeBookRecord(
      course: DemoCourse(
        code: 'CSC 305',
        title: 'Secure Examination Systems',
        lecturer: 'Dr. A. Bello',
      ),
      assessmentTitle: 'First semester supervised examination',
      assessmentType: 'Examination',
      dateLabel: '19/06/2026',
      scoreLabel: '72%',
      gradeLabel: 'B',
      status: GradeBookStatus.passed,
      note: 'Passed.',
    ),
    GradeBookRecord(
      course: DemoCourse(
        code: 'MAT 221',
        title: 'Linear Algebra for Computing',
        lecturer: 'Dr. S. Musa',
      ),
      assessmentTitle: 'Second semester examination',
      assessmentType: 'Examination',
      dateLabel: 'Pending',
      scoreLabel: 'Carryover',
      gradeLabel: 'CO',
      status: GradeBookStatus.carryover,
      note: 'Register and sit for the next available examination.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final passed = _records
        .where((record) => record.status == GradeBookStatus.passed)
        .length;
    final carryover = _records
        .where((record) => record.status == GradeBookStatus.carryover)
        .length;
    final available = _records
        .where((record) => record.status == GradeBookStatus.available)
        .length;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        title: const Text('Grade Book'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _GradeBookHeader(
              passed: passed,
              carryover: carryover,
              available: available,
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final twoColumns = constraints.maxWidth >= 960;
                final itemWidth = twoColumns
                    ? (constraints.maxWidth - 16) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (final record in _records)
                      SizedBox(
                        width: itemWidth,
                        child: _GradeRecordCard(record: record),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class GradeBookRecord {
  const GradeBookRecord({
    required this.course,
    required this.assessmentTitle,
    required this.assessmentType,
    required this.dateLabel,
    required this.scoreLabel,
    required this.gradeLabel,
    required this.status,
    required this.note,
  });

  final DemoCourse course;
  final String assessmentTitle;
  final String assessmentType;
  final String dateLabel;
  final String scoreLabel;
  final String gradeLabel;
  final GradeBookStatus status;
  final String note;
}

enum GradeBookStatus { available, passed, pending, carryover }

class _GradeBookHeader extends StatelessWidget {
  const _GradeBookHeader({
    required this.passed,
    required this.carryover,
    required this.available,
  });

  final int passed;
  final int carryover;
  final int available;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeaderChip(icon: Icons.school_outlined, label: 'KASU DLI'),
              _HeaderChip(
                icon: Icons.workspace_premium_outlined,
                label: 'Student records',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Grade Book',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'View exam history, released results, passed courses, and carryover records.',
            style: TextStyle(
              color: Color(0xFFCBD5E1),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _HeaderStat(value: '$passed', label: 'Passed'),
              _HeaderStat(value: '$carryover', label: 'Carryover'),
              _HeaderStat(value: '$available', label: 'Available demo'),
            ],
          ),
        ],
      ),
    );
  }
}

class _GradeRecordCard extends StatelessWidget {
  const _GradeRecordCard({required this.record});

  final GradeBookRecord record;

  @override
  Widget build(BuildContext context) {
    final accent = _statusColor(record.status);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D0F172A),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
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
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(_statusIcon(record.status), color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.course.code,
                      style: const TextStyle(
                        color: Color(0xFF1E3A8A),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      record.assessmentTitle,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
              ),
              _StatusPill(label: _statusLabel(record.status), color: accent),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            record.course.title,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoPill(label: record.assessmentType),
              _InfoPill(label: record.dateLabel),
              _InfoPill(label: 'Score: ${record.scoreLabel}'),
              _InfoPill(label: 'Grade: ${record.gradeLabel}'),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            record.note,
            style: const TextStyle(
              color: Color(0xFF334155),
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  static Color _statusColor(GradeBookStatus status) {
    switch (status) {
      case GradeBookStatus.available:
        return const Color(0xFF2563EB);
      case GradeBookStatus.passed:
        return const Color(0xFF16A34A);
      case GradeBookStatus.pending:
        return const Color(0xFFF59E0B);
      case GradeBookStatus.carryover:
        return const Color(0xFFDC2626);
    }
  }

  static IconData _statusIcon(GradeBookStatus status) {
    switch (status) {
      case GradeBookStatus.available:
        return Icons.play_circle_outline;
      case GradeBookStatus.passed:
        return Icons.check_circle_outline;
      case GradeBookStatus.pending:
        return Icons.hourglass_empty_outlined;
      case GradeBookStatus.carryover:
        return Icons.replay_circle_filled_outlined;
    }
  }

  static String _statusLabel(GradeBookStatus status) {
    switch (status) {
      case GradeBookStatus.available:
        return 'Available';
      case GradeBookStatus.passed:
        return 'Passed';
      case GradeBookStatus.pending:
        return 'Pending';
      case GradeBookStatus.carryover:
        return 'Carryover';
    }
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x2EFFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  const _HeaderStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 130,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x2EFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFCBD5E1),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label});

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
          color: Color(0xFF334155),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
