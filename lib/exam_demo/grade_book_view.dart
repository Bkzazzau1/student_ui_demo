import 'package:flutter/material.dart';

import 'demo_exam_models.dart';

const Color _brand = Color(0xFF0F4C81);
const Color _brandDark = Color(0xFF0B1220);
const Color _surface = Colors.white;
const Color _line = Color(0xFFE2E8F0);
const Color _muted = Color(0xFF64748B);
const Color _success = Color(0xFF16A34A);
const Color _danger = Color(0xFFDC2626);

class GradeBookView extends StatelessWidget {
  const GradeBookView({super.key});

  static const _records = <ExamAttendanceRecord>[
    ExamAttendanceRecord(
      course: DemoCourse(
        code: 'CSC 305',
        title: 'Secure Examination Systems',
        lecturer: 'Dr. A. Bello',
      ),
      examTitle: 'Sample supervised exam for today',
      examType: 'Supervised examination',
      dateLabel: '29/06/2026',
      startTimeLabel: '18:30',
      endTimeLabel: '18:52',
      status: ExamAttendanceStatus.submitted,
      note: 'Submitted by the student.',
    ),
    ExamAttendanceRecord(
      course: DemoCourse(
        code: 'GST 204',
        title: 'Entrepreneurship and Innovation',
        lecturer: 'Dr. M. Okafor',
      ),
      examTitle: 'Continuous assessment quiz',
      examType: 'Assessment quiz',
      dateLabel: '26/06/2026',
      startTimeLabel: '10:00',
      endTimeLabel: '10:28',
      status: ExamAttendanceStatus.submitted,
      note: 'Submitted by the student.',
    ),
    ExamAttendanceRecord(
      course: DemoCourse(
        code: 'CSC 305',
        title: 'Secure Examination Systems',
        lecturer: 'Dr. A. Bello',
      ),
      examTitle: 'First semester supervised examination',
      examType: 'Supervised examination',
      dateLabel: '19/06/2026',
      startTimeLabel: '09:00',
      endTimeLabel: '11:00',
      status: ExamAttendanceStatus.submitted,
      note: 'Submitted by the student.',
    ),
    ExamAttendanceRecord(
      course: DemoCourse(
        code: 'MAT 221',
        title: 'Linear Algebra for Computing',
        lecturer: 'Dr. S. Musa',
      ),
      examTitle: 'Second semester examination',
      examType: 'Supervised examination',
      dateLabel: 'Pending date',
      startTimeLabel: 'Not opened',
      endTimeLabel: 'Closed',
      status: ExamAttendanceStatus.closed,
      note: 'Closed because the student did not write the exam.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final submitted = _records
        .where((record) => record.status == ExamAttendanceStatus.submitted)
        .length;
    final closed = _records
        .where((record) => record.status == ExamAttendanceStatus.closed)
        .length;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        title: const Text(
          'Exam Attendance',
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
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 90),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1080),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _AttendanceHero(
                        total: _records.length,
                        submitted: submitted,
                        closed: closed,
                      ),
                      const SizedBox(height: 14),
                      _AttendanceSummaryStrip(
                        submitted: submitted,
                        closed: closed,
                      ),
                      const SizedBox(height: 14),
                      _AttendanceRecordsPanel(records: _records),
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

class ExamAttendanceRecord {
  const ExamAttendanceRecord({
    required this.course,
    required this.examTitle,
    required this.examType,
    required this.dateLabel,
    required this.startTimeLabel,
    required this.endTimeLabel,
    required this.status,
    required this.note,
  });

  final DemoCourse course;
  final String examTitle;
  final String examType;
  final String dateLabel;
  final String startTimeLabel;
  final String endTimeLabel;
  final ExamAttendanceStatus status;
  final String note;
}

enum ExamAttendanceStatus { submitted, closed }

class _AttendanceHero extends StatelessWidget {
  const _AttendanceHero({
    required this.total,
    required this.submitted,
    required this.closed,
  });

  final int total;
  final int submitted;
  final int closed;

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
                    _GlassTag(icon: Icons.fact_check_outlined, text: 'Exam attendance'),
                    _GlassTag(icon: Icons.history_rounded, text: 'Historical record'),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Exam Attendance Record',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'A simple record of exams scheduled for the student, showing only date, time, and attendance status.',
                  style: TextStyle(
                    color: Color(0xFFE2E8F0),
                    fontSize: 15,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            );
            final status = _HeroStatus(
              total: total,
              submitted: submitted,
              closed: closed,
            );
            if (!wide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [details, const SizedBox(height: 16), status],
              );
            }
            return Row(
              children: [
                Expanded(child: details),
                const SizedBox(width: 22),
                SizedBox(width: 250, child: status),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HeroStatus extends StatelessWidget {
  const _HeroStatus({
    required this.total,
    required this.submitted,
    required this.closed,
  });

  final int total;
  final int submitted;
  final int closed;

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
          const Icon(Icons.event_available_outlined, color: Color(0xFF93C5FD), size: 28),
          const SizedBox(height: 10),
          Text(
            '$total exams',
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            '$submitted submitted • $closed closed',
            style: const TextStyle(
              color: Color(0xFFCBD5E1),
              height: 1.35,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceSummaryStrip extends StatelessWidget {
  const _AttendanceSummaryStrip({required this.submitted, required this.closed});

  final int submitted;
  final int closed;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final width = compact ? constraints.maxWidth : (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: width,
              child: _SummaryTile(
                label: 'Submitted exams',
                value: '$submitted',
                color: _success,
                icon: Icons.check_circle_outline,
              ),
            ),
            SizedBox(
              width: width,
              child: _SummaryTile(
                label: 'Closed exams',
                value: '$closed',
                color: _danger,
                icon: Icons.cancel_outlined,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

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
        boxShadow: const [
          BoxShadow(color: Color(0x060F172A), blurRadius: 14, offset: Offset(0, 8)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(color: _brandDark, fontSize: 22, fontWeight: FontWeight.w900),
                ),
                Text(
                  label,
                  style: const TextStyle(color: _muted, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceRecordsPanel extends StatelessWidget {
  const _AttendanceRecordsPanel({required this.records});

  final List<ExamAttendanceRecord> records;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(color: Color(0x080F172A), blurRadius: 18, offset: Offset(0, 10)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 5, color: _brand),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.list_alt_rounded, color: _brand),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Exam history',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: _brandDark,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                _SmallCount(count: records.length),
              ],
            ),
          ),
          const Divider(height: 1, color: _line),
          for (var index = 0; index < records.length; index++) ...[
            if (index > 0) const Divider(height: 1, color: _line),
            _AttendanceRecordRow(record: records[index]),
          ],
        ],
      ),
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
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        border: Border.all(color: const Color(0xFFBFDBFE)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text('$count', style: const TextStyle(color: _brand, fontWeight: FontWeight.w900)),
    );
  }
}

class _AttendanceRecordRow extends StatelessWidget {
  const _AttendanceRecordRow({required this.record});

  final ExamAttendanceRecord record;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(record.status);
    return Container(
      color: color.withValues(alpha: 0.025),
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final main = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(width: 4, height: 58, color: color),
              const SizedBox(width: 12),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(_statusIcon(record.status), color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          record.course.code,
                          style: const TextStyle(color: _brand, fontWeight: FontWeight.w900),
                        ),
                        _StatusPill(label: _statusLabel(record.status), color: color),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      record.examTitle,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: _brandDark,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      record.course.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      record.note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF334155), fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          );
          final dateTime = _DateTimeBox(record: record, color: color);
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [main, const SizedBox(height: 12), dateTime],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: main),
              const SizedBox(width: 16),
              SizedBox(width: 340, child: dateTime),
            ],
          );
        },
      ),
    );
  }
}

class _DateTimeBox extends StatelessWidget {
  const _DateTimeBox({required this.record, required this.color});

  final ExamAttendanceRecord record;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        _InfoPill(label: record.examType, color: _brand),
        _InfoPill(label: record.dateLabel, color: _muted),
        _InfoPill(label: 'Start: ${record.startTimeLabel}', color: color),
        _InfoPill(label: 'End: ${record.endTimeLabel}', color: color),
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
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 7),
          Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
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
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12)),
    );
  }
}

Color _statusColor(ExamAttendanceStatus status) {
  switch (status) {
    case ExamAttendanceStatus.submitted:
      return _success;
    case ExamAttendanceStatus.closed:
      return _danger;
  }
}

IconData _statusIcon(ExamAttendanceStatus status) {
  switch (status) {
    case ExamAttendanceStatus.submitted:
      return Icons.check_circle_outline;
    case ExamAttendanceStatus.closed:
      return Icons.cancel_outlined;
  }
}

String _statusLabel(ExamAttendanceStatus status) {
  switch (status) {
    case ExamAttendanceStatus.submitted:
      return 'Submitted';
    case ExamAttendanceStatus.closed:
      return 'Closed';
  }
}
