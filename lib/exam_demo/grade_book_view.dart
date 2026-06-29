import 'package:flutter/material.dart';

import 'demo_exam_models.dart';
import 'exam_attendance_view.dart';

const Color _brand = Color(0xFF0F4C81);
const Color _brandDark = Color(0xFF0B1220);
const Color _surface = Colors.white;
const Color _line = Color(0xFFE2E8F0);
const Color _muted = Color(0xFF64748B);
const Color _success = Color(0xFF16A34A);
const Color _warning = Color(0xFFF59E0B);
const Color _danger = Color(0xFFDC2626);
const Color _purple = Color(0xFF7C3AED);

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
      recordType: 'Examination',
      dateLabel: 'Current demo',
      scoreLabel: 'Waiting release',
      gradeLabel: 'Pending',
      creditUnits: 3,
      gradePoint: null,
      status: GradeBookStatus.pendingRelease,
      note: 'Result will appear here when released by the school.',
    ),
    GradeBookRecord(
      course: DemoCourse(
        code: 'GST 204',
        title: 'Entrepreneurship and Innovation',
        lecturer: 'Dr. M. Okafor',
      ),
      assessmentTitle: 'Continuous assessment quiz',
      recordType: 'Graded assessment',
      dateLabel: '26/06/2026',
      scoreLabel: '8 / 10',
      gradeLabel: 'A',
      creditUnits: 2,
      gradePoint: 5.0,
      status: GradeBookStatus.passed,
      note: 'Passed. Lecturer feedback is available.',
    ),
    GradeBookRecord(
      course: DemoCourse(
        code: 'CSC 305',
        title: 'Secure Examination Systems',
        lecturer: 'Dr. A. Bello',
      ),
      assessmentTitle: 'First semester supervised examination',
      recordType: 'Examination',
      dateLabel: '19/06/2026',
      scoreLabel: '72%',
      gradeLabel: 'B',
      creditUnits: 3,
      gradePoint: 4.0,
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
      recordType: 'Examination',
      dateLabel: 'Pending',
      scoreLabel: 'Carryover',
      gradeLabel: 'CO',
      creditUnits: 3,
      gradePoint: 0.0,
      status: GradeBookStatus.carryover,
      note: 'Register and sit for the next available examination.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final passed = _records.where((record) => record.status == GradeBookStatus.passed).length;
    final pending = _records.where((record) => record.status == GradeBookStatus.pendingRelease).length;
    final carryover = _records.where((record) => record.status == GradeBookStatus.carryover).length;
    final cgpa = _calculateCgpa(_records);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        title: const Text(
          'Grade Book',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ExamAttendanceView()),
              ),
              icon: const Icon(Icons.fact_check_outlined, size: 18),
              label: const Text('Exam attendance'),
            ),
          ),
        ],
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
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 90),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1080),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _GradeBookHero(
                        cgpa: cgpa,
                        passed: passed,
                        pending: pending,
                        carryover: carryover,
                      ),
                      const SizedBox(height: 14),
                      _StatusSummaryStrip(
                        passed: passed,
                        pending: pending,
                        carryover: carryover,
                      ),
                      const SizedBox(height: 14),
                      _RecordsPanel(records: _records),
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

  static double _calculateCgpa(List<GradeBookRecord> records) {
    var totalUnits = 0;
    var totalPoints = 0.0;
    for (final record in records) {
      final point = record.gradePoint;
      if (point == null || record.status == GradeBookStatus.pendingRelease) continue;
      totalUnits += record.creditUnits;
      totalPoints += point * record.creditUnits;
    }
    if (totalUnits == 0) return 0;
    return totalPoints / totalUnits;
  }
}

class GradeBookRecord {
  const GradeBookRecord({
    required this.course,
    required this.assessmentTitle,
    required this.recordType,
    required this.dateLabel,
    required this.scoreLabel,
    required this.gradeLabel,
    required this.creditUnits,
    required this.gradePoint,
    required this.status,
    required this.note,
  });

  final DemoCourse course;
  final String assessmentTitle;
  final String recordType;
  final String dateLabel;
  final String scoreLabel;
  final String gradeLabel;
  final int creditUnits;
  final double? gradePoint;
  final GradeBookStatus status;
  final String note;
}

enum GradeBookStatus { passed, pendingRelease, carryover }

class _GradeBookHero extends StatelessWidget {
  const _GradeBookHero({
    required this.cgpa,
    required this.passed,
    required this.pending,
    required this.carryover,
  });

  final double cgpa;
  final int passed;
  final int pending;
  final int carryover;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(color: Color(0x1F0F172A), blurRadius: 24, offset: Offset(0, 14)),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(22),
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
                const Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _GlassTag(icon: Icons.school_outlined, text: 'KASU DLI'),
                    _GlassTag(icon: Icons.workspace_premium_outlined, text: 'Academic results'),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Grade Book',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Released grades, pending results, carryover records, and CGPA summary.',
                  style: TextStyle(
                    color: Color(0xFFE2E8F0),
                    fontSize: 15,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            );
            final status = _CgpaBox(cgpa: cgpa, passed: passed, pending: pending, carryover: carryover);
            if (!wide) {
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [details, const SizedBox(height: 16), status]);
            }
            return Row(children: [Expanded(child: details), const SizedBox(width: 22), SizedBox(width: 250, child: status)]);
          },
        ),
      ),
    );
  }
}

class _CgpaBox extends StatelessWidget {
  const _CgpaBox({required this.cgpa, required this.passed, required this.pending, required this.carryover});

  final double cgpa;
  final int passed;
  final int pending;
  final int carryover;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bar_chart_rounded, color: Color(0xFF93C5FD), size: 28),
          const SizedBox(height: 10),
          Text(cgpa.toStringAsFixed(2), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          const Text('Current CGPA', style: TextStyle(color: Color(0xFFCBD5E1), fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Text('$passed passed • $pending pending • $carryover carryover', style: const TextStyle(color: Color(0xFFCBD5E1), height: 1.35, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _StatusSummaryStrip extends StatelessWidget {
  const _StatusSummaryStrip({required this.passed, required this.pending, required this.carryover});

  final int passed;
  final int pending;
  final int carryover;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final width = compact ? constraints.maxWidth : (constraints.maxWidth - 24) / 3;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(width: width, child: _SummaryTile(label: 'Passed', value: '$passed', color: _success, icon: Icons.check_circle_outline)),
            SizedBox(width: width, child: _SummaryTile(label: 'Waiting release', value: '$pending', color: _warning, icon: Icons.hourglass_empty_outlined)),
            SizedBox(width: width, child: _SummaryTile(label: 'Carryover', value: '$carryover', color: _danger, icon: Icons.replay_circle_filled_outlined)),
          ],
        );
      },
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.label, required this.value, required this.color, required this.icon});

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Color(0x060F172A), blurRadius: 14, offset: Offset(0, 8))],
      ),
      child: Row(
        children: [
          Container(width: 42, height: 42, decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: color, size: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: const TextStyle(color: _brandDark, fontSize: 22, fontWeight: FontWeight.w900)),
              Text(label, style: const TextStyle(color: _muted, fontWeight: FontWeight.w800)),
            ]),
          ),
        ],
      ),
    );
  }
}

class _RecordsPanel extends StatelessWidget {
  const _RecordsPanel({required this.records});

  final List<GradeBookRecord> records;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: Color(0x080F172A), blurRadius: 18, offset: Offset(0, 10))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(height: 5, color: _brand),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
          child: Row(children: [
            Container(width: 42, height: 42, decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.list_alt_rounded, color: _brand)),
            const SizedBox(width: 12),
            Expanded(child: Text('Academic records', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: _brandDark, fontWeight: FontWeight.w900))),
            _SmallCount(count: records.length),
          ]),
        ),
        const Divider(height: 1, color: _line),
        for (var index = 0; index < records.length; index++) ...[
          if (index > 0) const Divider(height: 1, color: _line),
          _GradeRecordRow(record: records[index]),
        ],
      ]),
    );
  }
}

class _SmallCount extends StatelessWidget {
  const _SmallCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: const Color(0xFFEFF6FF), border: Border.all(color: const Color(0xFFBFDBFE)), borderRadius: BorderRadius.circular(999)),
      child: Text('$count', style: const TextStyle(color: _brand, fontWeight: FontWeight.w900)),
    );
  }
}

class _GradeRecordRow extends StatelessWidget {
  const _GradeRecordRow({required this.record});

  final GradeBookRecord record;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(record.status);
    return Container(
      color: color.withValues(alpha: 0.025),
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final main = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 4, height: 58, color: color),
            const SizedBox(width: 12),
            Container(width: 44, height: 44, decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)), child: Icon(_statusIcon(record.status), color: color)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(record.course.code, style: const TextStyle(color: _brand, fontWeight: FontWeight.w900)),
                _StatusPill(label: _statusLabel(record.status), color: color),
              ]),
              const SizedBox(height: 4),
              Text(record.assessmentTitle, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: _brandDark, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(record.course.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              Text(record.note, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF334155), fontWeight: FontWeight.w600)),
            ])),
          ]);
          final result = _GradeResultBox(record: record, color: color);
          if (compact) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [main, const SizedBox(height: 12), result]);
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: main), const SizedBox(width: 16), SizedBox(width: 330, child: result)]);
        },
      ),
    );
  }
}

class _GradeResultBox extends StatelessWidget {
  const _GradeResultBox({required this.record, required this.color});

  final GradeBookRecord record;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        _InfoPill(label: record.recordType, color: _brand),
        _InfoPill(label: record.dateLabel, color: _muted),
        _InfoPill(label: 'Score: ${record.scoreLabel}', color: color),
        _InfoPill(label: 'Grade: ${record.gradeLabel}', color: color),
        _InfoPill(label: '${record.creditUnits} units', color: _purple),
      ],
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
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), border: Border.all(color: Colors.white.withValues(alpha: 0.16)), borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: Colors.white, size: 16), const SizedBox(width: 7), Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900))]),
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(999), border: Border.all(color: color.withValues(alpha: 0.24))),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12)),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(999), border: Border.all(color: color.withValues(alpha: 0.18))),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12)),
    );
  }
}

Color _statusColor(GradeBookStatus status) {
  switch (status) {
    case GradeBookStatus.passed:
      return _success;
    case GradeBookStatus.pendingRelease:
      return _warning;
    case GradeBookStatus.carryover:
      return _danger;
  }
}

IconData _statusIcon(GradeBookStatus status) {
  switch (status) {
    case GradeBookStatus.passed:
      return Icons.check_circle_outline;
    case GradeBookStatus.pendingRelease:
      return Icons.hourglass_empty_outlined;
    case GradeBookStatus.carryover:
      return Icons.replay_circle_filled_outlined;
  }
}

String _statusLabel(GradeBookStatus status) {
  switch (status) {
    case GradeBookStatus.passed:
      return 'Passed';
    case GradeBookStatus.pendingRelease:
      return 'Waiting release';
    case GradeBookStatus.carryover:
      return 'Carryover';
  }
}
