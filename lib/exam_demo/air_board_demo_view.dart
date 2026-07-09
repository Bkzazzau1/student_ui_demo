import 'dart:math' as math;

import 'package:flutter/material.dart';

const Color _brand = Color(0xFF0F4C81);
const Color _brandDark = Color(0xFF0B1220);
const Color _surface = Colors.white;
const Color _surfaceSoft = Color(0xFFF8FAFC);
const Color _line = Color(0xFFE2E8F0);
const Color _muted = Color(0xFF64748B);
const Color _success = Color(0xFF16A34A);
const Color _warning = Color(0xFFF59E0B);

class AirBoardDemoView extends StatefulWidget {
  const AirBoardDemoView({super.key});

  @override
  State<AirBoardDemoView> createState() => _AirBoardDemoViewState();
}

class _AirBoardDemoViewState extends State<AirBoardDemoView> {
  final List<_AirBoardPage> _pages = <_AirBoardPage>[_AirBoardPage(index: 0)];
  int _activePageIndex = 0;
  _AirBoardTool _tool = _AirBoardTool.pen;
  _BoardBackground _background = _BoardBackground.grid;
  _AirBoardStroke? _activeStroke;
  int _strokeCounter = 0;
  DateTime? _lastActivityAt;

  _AirBoardPage get _activePage => _pages[_activePageIndex];
  bool get _hasWork => _pages.any((page) => page.strokes.isNotEmpty);
  int get _strokeCount => _pages.fold<int>(0, (total, page) => total + page.strokes.length);
  int get _pointCount => _pages.fold<int>(
        0,
        (total, page) => total + page.strokes.fold<int>(0, (sum, stroke) => sum + stroke.points.length),
      );

  void _startStroke(Offset position) {
    final now = DateTime.now();
    final stroke = _AirBoardStroke(
      id: 'stroke-${++_strokeCounter}',
      tool: _tool,
      pageIndex: _activePageIndex,
      points: <_AirBoardPoint>[_AirBoardPoint(position: position, timestamp: now)],
      startedAt: now,
      endedAt: now,
    );
    setState(() {
      _activeStroke = stroke;
      _lastActivityAt = now;
    });
  }

  void _appendPoint(Offset position) {
    final stroke = _activeStroke;
    if (stroke == null) return;
    final now = DateTime.now();
    setState(() {
      stroke.points.add(_AirBoardPoint(position: position, timestamp: now));
      stroke.endedAt = now;
      _lastActivityAt = now;
    });
  }

  void _finishStroke() {
    final stroke = _activeStroke;
    if (stroke == null || stroke.points.length < 2) {
      setState(() => _activeStroke = null);
      return;
    }
    setState(() {
      _activePage.strokes.add(stroke);
      _activeStroke = null;
      _lastActivityAt = DateTime.now();
    });
  }

  void _undo() {
    if (_activePage.strokes.isEmpty) return;
    setState(() {
      _activePage.strokes.removeLast();
      _lastActivityAt = DateTime.now();
    });
  }

  void _clearPage() {
    if (_activePage.strokes.isEmpty) return;
    setState(() {
      _activePage.strokes.clear();
      _lastActivityAt = DateTime.now();
    });
  }

  void _addPage() {
    setState(() {
      _pages.add(_AirBoardPage(index: _pages.length));
      _activePageIndex = _pages.length - 1;
      _lastActivityAt = DateTime.now();
    });
  }

  void _selectPage(int index) {
    setState(() {
      _activePageIndex = index;
      _lastActivityAt = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Rough-work board', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('Close'),
            ),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: _line),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _AirBoardIntroCard(
                      strokeCount: _strokeCount,
                      pointCount: _pointCount,
                      pageCount: _pages.length,
                      hasWork: _hasWork,
                    ),
                    const SizedBox(height: 14),
                    if (compact)
                      Column(
                        children: [
                          _AirBoardToolbar(
                            tool: _tool,
                            background: _background,
                            onToolChanged: (tool) => setState(() => _tool = tool),
                            onBackgroundChanged: (background) => setState(() => _background = background),
                            onUndo: _undo,
                            onClear: _clearPage,
                          ),
                          const SizedBox(height: 12),
                          _BoardPageTabs(
                            pages: _pages,
                            activePageIndex: _activePageIndex,
                            onSelect: _selectPage,
                            onAdd: _addPage,
                          ),
                          const SizedBox(height: 12),
                          _BoardCanvasCard(
                            page: _activePage,
                            activeStroke: _activeStroke,
                            background: _background,
                            tool: _tool,
                            onStart: _startStroke,
                            onMove: _appendPoint,
                            onEnd: _finishStroke,
                          ),
                        ],
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 300,
                            child: Column(
                              children: [
                                _AirBoardToolbar(
                                  tool: _tool,
                                  background: _background,
                                  onToolChanged: (tool) => setState(() => _tool = tool),
                                  onBackgroundChanged: (background) => setState(() => _background = background),
                                  onUndo: _undo,
                                  onClear: _clearPage,
                                ),
                                const SizedBox(height: 12),
                                _BoardPageTabs(
                                  pages: _pages,
                                  activePageIndex: _activePageIndex,
                                  onSelect: _selectPage,
                                  onAdd: _addPage,
                                ),
                                const SizedBox(height: 12),
                                _AirBoardEvidenceCard(
                                  lastActivityAt: _lastActivityAt,
                                  strokeCount: _strokeCount,
                                  pointCount: _pointCount,
                                  activePageIndex: _activePageIndex,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _BoardCanvasCard(
                              page: _activePage,
                              activeStroke: _activeStroke,
                              background: _background,
                              tool: _tool,
                              onStart: _startStroke,
                              onMove: _appendPoint,
                              onEnd: _finishStroke,
                            ),
                          ),
                        ],
                      ),
                    if (compact) ...[
                      const SizedBox(height: 12),
                      _AirBoardEvidenceCard(
                        lastActivityAt: _lastActivityAt,
                        strokeCount: _strokeCount,
                        pointCount: _pointCount,
                        activePageIndex: _activePageIndex,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AirBoardIntroCard extends StatelessWidget {
  const _AirBoardIntroCard({
    required this.strokeCount,
    required this.pointCount,
    required this.pageCount,
    required this.hasWork,
  });

  final int strokeCount;
  final int pointCount;
  final int pageCount;
  final bool hasWork;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_brandDark, Color(0xFF113A63), _brand],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(color: Color(0x160F172A), blurRadius: 22, offset: Offset(0, 12)),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 680;
          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  _WhiteTag('Exam area'),
                  _WhiteTag('Rough work'),
                  _WhiteTag('Saved for review'),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Solve naturally inside the exam screen',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Use this board for calculations, graphs, and notes. Your rough work stays inside the approved exam area so camera and attention checks can understand your activity fairly.',
                style: TextStyle(color: Color(0xFFE2E8F0), height: 1.45, fontWeight: FontWeight.w600),
              ),
            ],
          );
          final stats = Container(
            width: wide ? 250 : double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HeaderStat(label: 'Status', value: hasWork ? 'Active' : 'Ready'),
                const SizedBox(height: 8),
                _HeaderStat(label: 'Pages', value: '$pageCount'),
                const SizedBox(height: 8),
                _HeaderStat(label: 'Strokes', value: '$strokeCount'),
                const SizedBox(height: 8),
                _HeaderStat(label: 'Points', value: '$pointCount'),
              ],
            ),
          );
          if (!wide) return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, const SizedBox(height: 14), stats]);
          return Row(children: [Expanded(child: title), const SizedBox(width: 16), stats]);
        },
      ),
    );
  }
}

class _AirBoardToolbar extends StatelessWidget {
  const _AirBoardToolbar({
    required this.tool,
    required this.background,
    required this.onToolChanged,
    required this.onBackgroundChanged,
    required this.onUndo,
    required this.onClear,
  });

  final _AirBoardTool tool;
  final _BoardBackground background;
  final ValueChanged<_AirBoardTool> onToolChanged;
  final ValueChanged<_BoardBackground> onBackgroundChanged;
  final VoidCallback onUndo;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle(icon: Icons.draw_outlined, title: 'Board tools'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ToolChip(label: 'Pen', icon: Icons.edit_outlined, selected: tool == _AirBoardTool.pen, onTap: () => onToolChanged(_AirBoardTool.pen)),
              _ToolChip(label: 'Eraser', icon: Icons.cleaning_services_outlined, selected: tool == _AirBoardTool.eraser, onTap: () => onToolChanged(_AirBoardTool.eraser)),
            ],
          ),
          const SizedBox(height: 14),
          const Text('Paper style', style: TextStyle(color: _muted, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ToolChip(label: 'Grid', icon: Icons.grid_4x4_outlined, selected: background == _BoardBackground.grid, onTap: () => onBackgroundChanged(_BoardBackground.grid)),
              _ToolChip(label: 'Lined', icon: Icons.horizontal_rule_rounded, selected: background == _BoardBackground.lined, onTap: () => onBackgroundChanged(_BoardBackground.lined)),
              _ToolChip(label: 'Plain', icon: Icons.crop_square_rounded, selected: background == _BoardBackground.plain, onTap: () => onBackgroundChanged(_BoardBackground.plain)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onUndo,
                  icon: const Icon(Icons.undo_rounded),
                  label: const Text('Undo'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Clear'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BoardPageTabs extends StatelessWidget {
  const _BoardPageTabs({
    required this.pages,
    required this.activePageIndex,
    required this.onSelect,
    required this.onAdd,
  });

  final List<_AirBoardPage> pages;
  final int activePageIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle(icon: Icons.sticky_note_2_outlined, title: 'Rough-work pages'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final page in pages)
                _PageButton(
                  label: 'Page ${page.index + 1}',
                  selected: activePageIndex == page.index,
                  hasWork: page.strokes.isNotEmpty,
                  onTap: () => onSelect(page.index),
                ),
              OutlinedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BoardCanvasCard extends StatelessWidget {
  const _BoardCanvasCard({
    required this.page,
    required this.activeStroke,
    required this.background,
    required this.tool,
    required this.onStart,
    required this.onMove,
    required this.onEnd,
  });

  final _AirBoardPage page;
  final _AirBoardStroke? activeStroke;
  final _BoardBackground background;
  final _AirBoardTool tool;
  final ValueChanged<Offset> onStart;
  final ValueChanged<Offset> onMove;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(color: Color(0x080F172A), blurRadius: 18, offset: Offset(0, 10)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.border_color_outlined, color: _brand),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Digital rough work', style: TextStyle(color: _brandDark, fontWeight: FontWeight.w900, fontSize: 17)),
                    SizedBox(height: 2),
                    Text('Write with mouse, touchscreen, or stylus.', style: TextStyle(color: _muted, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              _SmallStatus(label: tool == _AirBoardTool.pen ? 'Pen' : 'Eraser'),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Listener(
                    onPointerDown: (event) => onStart(event.localPosition),
                    onPointerMove: (event) => onMove(event.localPosition),
                    onPointerUp: (_) => onEnd(),
                    onPointerCancel: (_) => onEnd(),
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _AirBoardPainter(
                          page: page,
                          activeStroke: activeStroke,
                          background: background,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AirBoardEvidenceCard extends StatelessWidget {
  const _AirBoardEvidenceCard({
    required this.lastActivityAt,
    required this.strokeCount,
    required this.pointCount,
    required this.activePageIndex,
  });

  final DateTime? lastActivityAt;
  final int strokeCount;
  final int pointCount;
  final int activePageIndex;

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle(icon: Icons.fact_check_outlined, title: 'Saved rough-work record'),
          const SizedBox(height: 12),
          _EvidenceLine(label: 'Active page', value: 'Page ${activePageIndex + 1}'),
          _EvidenceLine(label: 'Strokes', value: '$strokeCount'),
          _EvidenceLine(label: 'Points', value: '$pointCount'),
          _EvidenceLine(label: 'Last activity', value: lastActivityAt == null ? 'Not started' : _formatClock(lastActivityAt!)),
          const SizedBox(height: 10),
          const Text(
            'Next step: connect this activity summary to the Rust Air Board API so gaze and rough-work behaviour can be understood together.',
            style: TextStyle(color: _muted, height: 1.4, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  static String _formatClock(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }
}

class _AirBoardPainter extends CustomPainter {
  const _AirBoardPainter({
    required this.page,
    required this.activeStroke,
    required this.background,
  });

  final _AirBoardPage page;
  final _AirBoardStroke? activeStroke;
  final _BoardBackground background;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = Colors.white;
    canvas.drawRect(Offset.zero & size, bg);
    _drawBackground(canvas, size);
    for (final stroke in page.strokes) {
      _drawStroke(canvas, stroke);
    }
    final current = activeStroke;
    if (current != null) _drawStroke(canvas, current);
  }

  void _drawBackground(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1;
    if (background == _BoardBackground.plain) return;
    if (background == _BoardBackground.lined || background == _BoardBackground.grid) {
      for (var y = 32.0; y < size.height; y += 32) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
    }
    if (background == _BoardBackground.grid) {
      for (var x = 32.0; x < size.width; x += 32) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
    }
  }

  void _drawStroke(Canvas canvas, _AirBoardStroke stroke) {
    if (stroke.points.length < 2) return;
    final paint = Paint()
      ..color = stroke.tool == _AirBoardTool.eraser ? Colors.white : _brandDark
      ..strokeWidth = stroke.tool == _AirBoardTool.eraser ? 18 : 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(stroke.points.first.position.dx, stroke.points.first.position.dy);
    for (var i = 1; i < stroke.points.length; i++) {
      final previous = stroke.points[i - 1].position;
      final current = stroke.points[i].position;
      final midpoint = Offset((previous.dx + current.dx) / 2, (previous.dy + current.dy) / 2);
      path.quadraticBezierTo(previous.dx, previous.dy, midpoint.dx, midpoint.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _AirBoardPainter oldDelegate) {
    return oldDelegate.page != page || oldDelegate.activeStroke != activeStroke || oldDelegate.background != background;
  }
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x080F172A), blurRadius: 18, offset: Offset(0, 10)),
        ],
      ),
      child: child,
    );
  }
}

class _PanelTitle extends StatelessWidget {
  const _PanelTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: _brand, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title, style: const TextStyle(color: _brandDark, fontWeight: FontWeight.w900, fontSize: 16)),
        ),
      ],
    );
  }
}

class _ToolChip extends StatelessWidget {
  const _ToolChip({required this.label, required this.icon, required this.selected, required this.onTap});

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => onTap(),
      avatar: Icon(icon, size: 17, color: selected ? Colors.white : _brand),
      label: Text(label, style: TextStyle(fontWeight: FontWeight.w900, color: selected ? Colors.white : _brandDark)),
      selectedColor: _brand,
      backgroundColor: _surfaceSoft,
      side: BorderSide(color: selected ? _brand : _line),
      showCheckmark: false,
    );
  }
}

class _PageButton extends StatelessWidget {
  const _PageButton({required this.label, required this.selected, required this.hasWork, required this.onTap});

  final String label;
  final bool selected;
  final bool hasWork;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? const Color(0xFFEFF6FF) : Colors.white,
        side: BorderSide(color: selected ? _brand : _line),
      ),
      icon: Icon(hasWork ? Icons.check_circle : Icons.note_outlined, size: 18, color: hasWork ? _success : _brand),
      label: Text(label),
    );
  }
}

class _WhiteTag extends StatelessWidget {
  const _WhiteTag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  const _HeaderStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(color: Color(0xFFCBD5E1), fontWeight: FontWeight.w700))),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
      ],
    );
  }
}

class _EvidenceLine extends StatelessWidget {
  const _EvidenceLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: _muted, fontWeight: FontWeight.w700))),
          Text(value, style: const TextStyle(color: _brandDark, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _SmallStatus extends StatelessWidget {
  const _SmallStatus({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: const TextStyle(color: Color(0xFF92400E), fontWeight: FontWeight.w900, fontSize: 12)),
    );
  }
}

enum _AirBoardTool { pen, eraser }
enum _BoardBackground { grid, lined, plain }

class _AirBoardPage {
  _AirBoardPage({required this.index});
  final int index;
  final List<_AirBoardStroke> strokes = <_AirBoardStroke>[];
}

class _AirBoardStroke {
  _AirBoardStroke({
    required this.id,
    required this.tool,
    required this.pageIndex,
    required this.points,
    required this.startedAt,
    required this.endedAt,
  });

  final String id;
  final _AirBoardTool tool;
  final int pageIndex;
  final List<_AirBoardPoint> points;
  final DateTime startedAt;
  DateTime endedAt;
}

class _AirBoardPoint {
  const _AirBoardPoint({required this.position, required this.timestamp});
  final Offset position;
  final DateTime timestamp;
}
