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

class FeedbackDetailView extends StatelessWidget {
  const FeedbackDetailView({
    super.key,
    required this.feedbackItem,
  });

  final DemoFeedbackItem feedbackItem;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        title: const Text(
          'Lecturer feedback',
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
                      _FeedbackHero(item: feedbackItem),
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth >= 900;
                          final feedback = _FeedbackMessageCard(item: feedbackItem);
                          final side = _FeedbackSidePanel(item: feedbackItem);
                          if (!wide) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [feedback, const SizedBox(height: 14), side],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 6, child: feedback),
                              const SizedBox(width: 14),
                              Expanded(flex: 4, child: side),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      const _NextStepsCard(),
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
  const _FeedbackHero({required this.item});

  final DemoFeedbackItem item;

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
            final wide = constraints.maxWidth >= 760;
            final details = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _HeroTag(icon: Icons.school_outlined, text: item.course.code),
                    _HeroTag(icon: Icons.rate_review_outlined, text: 'Lecturer feedback'),
                    _HeroTag(icon: Icons.event_available_outlined, text: 'Released ${item.releasedLabel}'),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  item.title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                ),
                const SizedBox(height: 7),
                Text(
                  '${item.course.title} • Lecturer: ${item.course.lecturer}',
                  style: const TextStyle(
                    color: Color(0xFFE2E8F0),
                    fontSize: 15,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            );

            final summary = _HeroSummary(item: item);
            if (!wide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [details, const SizedBox(height: 16), summary],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: details),
                const SizedBox(width: 22),
                SizedBox(width: 250, child: summary),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HeroSummary extends StatelessWidget {
  const _HeroSummary({required this.item});

  final DemoFeedbackItem item;

  @override
  Widget build(BuildContext context) {
    final feedbackOnly = item.scoreLabel.toLowerCase().contains('feedback');
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
          Icon(
            feedbackOnly ? Icons.forum_outlined : Icons.workspace_premium_outlined,
            color: const Color(0xFF93C5FD),
            size: 28,
          ),
          const SizedBox(height: 10),
          Text(
            item.scoreLabel,
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          const Text(
            'Released feedback',
            style: TextStyle(color: Color(0xFFCBD5E1), fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            item.releasedLabel,
            style: const TextStyle(color: Color(0xFFCBD5E1), height: 1.35, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _FeedbackMessageCard extends StatelessWidget {
  const _FeedbackMessageCard({required this.item});

  final DemoFeedbackItem item;

  @override
  Widget build(BuildContext context) {
    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            icon: Icons.rate_review_outlined,
            title: 'Feedback from lecturer',
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _surfaceSoft,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _line),
            ),
            child: Text(
              item.feedback,
              style: const TextStyle(
                color: Color(0xFF334155),
                height: 1.6,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(label: item.scoreLabel, color: _brand),
              const _InfoChip(label: 'Lecturer comment', color: _success),
              _InfoChip(label: 'Released ${item.releasedLabel}', color: _purple),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeedbackSidePanel extends StatelessWidget {
  const _FeedbackSidePanel({required this.item});

  final DemoFeedbackItem item;

  @override
  Widget build(BuildContext context) {
    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            icon: Icons.assignment_outlined,
            title: 'Assessment details',
          ),
          const SizedBox(height: 14),
          _DetailRow(label: 'Course', value: '${item.course.code} - ${item.course.title}'),
          _DetailRow(label: 'Lecturer', value: item.course.lecturer),
          _DetailRow(label: 'Released', value: item.releasedLabel),
          _DetailRow(label: 'Record', value: item.scoreLabel),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: _brand, size: 21),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'This page is for reading lecturer comments. Official grades remain in the Grade Book.',
                    style: TextStyle(
                      color: Color(0xFF1E3A8A),
                      height: 1.4,
                      fontWeight: FontWeight.w800,
                    ),
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

class _NextStepsCard extends StatelessWidget {
  const _NextStepsCard();

  @override
  Widget build(BuildContext context) {
    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _SectionTitle(
            icon: Icons.checklist_outlined,
            title: 'Next steps',
          ),
          SizedBox(height: 12),
          _GuidanceLine(
            icon: Icons.menu_book_outlined,
            text: 'Review the feedback and revise the weak areas before the next assessment.',
          ),
          SizedBox(height: 8),
          _GuidanceLine(
            icon: Icons.question_answer_outlined,
            text: 'Ask your lecturer for clarification if any comment is not clear.',
          ),
          SizedBox(height: 8),
          _GuidanceLine(
            icon: Icons.trending_up_outlined,
            text: 'Use the feedback to improve your next submission or exam preparation.',
          ),
        ],
      ),
    );
  }
}

class _GuidanceLine extends StatelessWidget {
  const _GuidanceLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _success, size: 19),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Color(0xFF475569), height: 1.45, fontWeight: FontWeight.w700),
          ),
        ),
      ],
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
      child: child,
    );
  }
}

class _HeroTag extends StatelessWidget {
  const _HeroTag({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
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
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: _brand),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: _brandDark,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.color});

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
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: const TextStyle(color: _muted, fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: _brandDark, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
