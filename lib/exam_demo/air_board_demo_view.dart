import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../proctoring_demo/camera_runtime_coordinator.dart';
import '../rust/api/air_board.dart' as rust_air;
import '../rust/api/hand_air_board.dart' as rust_hand;

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
  static const String _cameraOwner = 'air_board_demo';
  static const bool _useNativeAirBoard = bool.fromEnvironment(
    'KSLAS_USE_NATIVE_AIR_BOARD',
    defaultValue: false,
  );
  static const bool _useNativeHandAirBoard = bool.fromEnvironment(
    'KSLAS_USE_NATIVE_HAND_AIR_BOARD',
    defaultValue: false,
  );

  final DateTime _openedAt = DateTime.now();
  final List<_AirBoardPage> _pages = <_AirBoardPage>[_AirBoardPage(index: 0)];
  final CameraRuntimeCoordinator _cameraRuntime = CameraRuntimeCoordinator.instance;

  int _activePageIndex = 0;
  int _strokeCounter = 0;
  _AirBoardTool _tool = _AirBoardTool.pen;
  _BoardBackground _background = _BoardBackground.grid;
  _AirBoardStroke? _activeStroke;
  DateTime? _lastActivityAt;
  late rust_air.AirBoardActivitySummary _rustSummary;
  late rust_hand.HandRegionSignal _handSignal;
  late rust_hand.HandAirBoardDecision _handDecision;
  late String _evidenceManifest;
  CameraController? _camera;
  bool _ownsCameraLease = false;
  bool _openingCamera = false;
  String _cameraStatus = 'Opening camera preview...';

  _AirBoardPage get _activePage => _pages[_activePageIndex];
  List<_AirBoardStroke> get _allStrokes => [
        for (final page in _pages) ...page.strokes,
        if (_activeStroke != null) _activeStroke!,
      ];

  @override
  void initState() {
    super.initState();
    _refreshRustSummary();
    unawaited(_startCameraPreview());
  }

  @override
  void dispose() {
    final camera = _camera;
    _camera = null;
    unawaited(camera?.dispose());
    if (_ownsCameraLease) {
      _cameraRuntime.release(_cameraOwner);
    }
    super.dispose();
  }

  Future<void> _startCameraPreview() async {
    if (_openingCamera) return;
    final lease = _cameraRuntime.tryAcquire(
      owner: _cameraOwner,
      purpose: 'air_board_camera_preview',
    );
    if (lease == null) {
      if (!mounted) return;
      final activeOwner = _cameraRuntime.activeLease?.owner ?? 'live monitor';
      setState(() {
        _cameraStatus =
            'Camera is already active for $activeOwner. Your monitoring camera remains running while you use the board.';
        _refreshRustSummary();
      });
      return;
    }

    _ownsCameraLease = true;
    setState(() {
      _openingCamera = true;
      _cameraStatus = 'Opening camera preview...';
      _refreshRustSummary();
    });

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (!mounted) return;
        setState(() {
          _cameraStatus = 'No camera was found. Connect or enable your webcam, then reopen the board.';
          _refreshRustSummary();
        });
        return;
      }

      final selected = cameras.firstWhere(
        (item) => item.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        selected,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _cameraStatus = 'Camera preview active';
        _refreshRustSummary();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cameraStatus =
            'Camera preview could not open. Close other apps using the camera and try again. $error';
        _refreshRustSummary();
      });
    } finally {
      if (mounted) {
        setState(() {
          _openingCamera = false;
          _refreshRustSummary();
        });
      }
    }
  }

  void _startStroke(Offset position) {
    final now = DateTime.now();
    setState(() {
      _activeStroke = _AirBoardStroke(
        id: 'stroke-${++_strokeCounter}',
        tool: _tool,
        pageIndex: _activePageIndex,
        points: <_AirBoardPoint>[_AirBoardPoint(position: position, timestamp: now)],
        startedAt: now,
        endedAt: now,
      );
      _lastActivityAt = now;
      _refreshRustSummary();
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
      _refreshRustSummary();
    });
  }

  void _finishStroke() {
    final stroke = _activeStroke;
    setState(() {
      if (stroke != null && stroke.points.length >= 2) {
        _activePage.strokes.add(stroke);
        _lastActivityAt = DateTime.now();
      }
      _activeStroke = null;
      _refreshRustSummary();
    });
  }

  void _undo() {
    if (_activePage.strokes.isEmpty) return;
    setState(() {
      _activePage.strokes.removeLast();
      _lastActivityAt = DateTime.now();
      _refreshRustSummary();
    });
  }

  void _clearPage() {
    if (_activePage.strokes.isEmpty) return;
    setState(() {
      _activePage.strokes.clear();
      _lastActivityAt = DateTime.now();
      _refreshRustSummary();
    });
  }

  void _addPage() {
    setState(() {
      _pages.add(_AirBoardPage(index: _pages.length));
      _activePageIndex = _pages.length - 1;
      _lastActivityAt = DateTime.now();
      _refreshRustSummary();
    });
  }

  void _selectPage(int index) {
    setState(() {
      _activePageIndex = index;
      _lastActivityAt = DateTime.now();
      _refreshRustSummary();
    });
  }

  void _refreshRustSummary() {
    _rustSummary = _analyzeWithRust();
    _handSignal = _buildHandSignal(DateTime.now());
    _handDecision = _analyzeHandAirBoard();
    _evidenceManifest = _buildManifest(_rustSummary);
  }

  rust_air.AirBoardActivitySummary _analyzeWithRust() {
    final now = DateTime.now();
    final context = rust_air.AirBoardContext(
      isOpen: true,
      activePageIndex: _activePageIndex,
      pageCount: _pages.length,
      strokes: _allStrokes.map(_toRustStroke).toList(growable: false),
      lastActivityAtMs: (_lastActivityAt ?? _openedAt).millisecondsSinceEpoch,
      openedAtMs: _openedAt.millisecondsSinceEpoch,
      nowMs: now.millisecondsSinceEpoch,
    );
    if (!_useNativeAirBoard) return _analyzeWithDart(context);
    try {
      return rust_air.analyzeAirBoardContext(context: context);
    } catch (_) {
      return _analyzeWithDart(context);
    }
  }

  rust_hand.HandRegionSignal _buildHandSignal(DateTime now) {
    final cameraReady = _camera != null && _camera!.value.isInitialized;
    final monitoringCameraAlreadyActive = _cameraStatus.contains('already active');
    final writingNow = _rustSummary.currentlyWriting || _activeStroke != null;
    final hasRoughWork = _rustSummary.totalPoints > 0;

    return rust_hand.HandRegionSignal(
      handVisible: cameraReady || monitoringCameraAlreadyActive,
      handCount: cameraReady || monitoringCameraAlreadyActive ? 1 : 0,
      primaryHandX: writingNow ? 0.56 : 0.50,
      primaryHandY: writingNow ? 0.78 : 0.72,
      handConfidence: cameraReady
          ? 0.70
          : monitoringCameraAlreadyActive
              ? 0.55
              : 0.20,
      nearKeyboard: !writingNow && hasRoughWork,
      nearMouseOrStylusArea: writingNow,
      nearFace: false,
      belowDeskLine: false,
      timestampMs: now.millisecondsSinceEpoch,
    );
  }

  rust_hand.HandAirBoardDecision _analyzeHandAirBoard() {
    final context = rust_hand.HandAirBoardContext(
      airBoard: _rustSummary,
      hand: _handSignal,
      gazeZone: _rustSummary.currentlyWriting ? 'air_board' : 'answer_area',
      screenZone: 'air_board',
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );

    if (_useNativeHandAirBoard) {
      try {
        return rust_hand.analyzeHandAirBoardContext(context: context);
      } catch (_) {}
    }
    return _analyzeHandAirBoardWithDart(context);
  }

  rust_hand.HandAirBoardDecision _analyzeHandAirBoardWithDart(
    rust_hand.HandAirBoardContext context,
  ) {
    final handReliable = context.hand.handVisible && context.hand.handConfidence >= 0.45;
    final handInExpectedWorkArea = context.hand.nearKeyboard || context.hand.nearMouseOrStylusArea;
    final airBoardWriting = context.airBoard.currentlyWriting;

    if (airBoardWriting && handReliable && handInExpectedWorkArea && !context.hand.nearFace && !context.hand.belowDeskLine) {
      return const rust_hand.HandAirBoardDecision(
        behaviourLabel: 'hand_matches_rough_work',
        attentionLevel: 'normal',
        handMatchesAirBoard: true,
        reviewRequired: false,
        studentMessage: 'Your rough-work board is active. Please continue solving inside the exam screen.',
        reviewerSummary: 'Camera hand signal matches active rough-work activity on the Air Board.',
      );
    }

    if (airBoardWriting && !handReliable) {
      return const rust_hand.HandAirBoardDecision(
        behaviourLabel: 'rough_work_active_hand_not_clear',
        attentionLevel: 'medium_attention_required',
        handMatchesAirBoard: false,
        reviewRequired: true,
        studentMessage: 'Please keep your hands and writing area clearly visible while using the rough-work board.',
        reviewerSummary: 'Air Board writing was active, but the camera hand signal was not reliable enough.',
      );
    }

    if (airBoardWriting && context.hand.belowDeskLine) {
      return const rust_hand.HandAirBoardDecision(
        behaviourLabel: 'rough_work_active_hand_below_desk',
        attentionLevel: 'high_attention_required',
        handMatchesAirBoard: false,
        reviewRequired: true,
        studentMessage: 'Please keep your hands visible and continue inside the exam screen.',
        reviewerSummary: 'Air Board writing was active while the hand appeared below the desk line. Human review is recommended.',
      );
    }

    if (context.airBoard.active && handReliable && handInExpectedWorkArea) {
      return const rust_hand.HandAirBoardDecision(
        behaviourLabel: 'hand_ready_for_rough_work',
        attentionLevel: 'normal',
        handMatchesAirBoard: true,
        reviewRequired: false,
        studentMessage: 'Your rough-work board is ready. You may continue solving inside the exam screen.',
        reviewerSummary: 'Hand activity is within the expected keyboard, mouse, stylus, or writing area.',
      );
    }

    return const rust_hand.HandAirBoardDecision(
      behaviourLabel: 'hand_air_board_neutral',
      attentionLevel: 'normal',
      handMatchesAirBoard: false,
      reviewRequired: false,
      studentMessage: 'Please continue your exam carefully.',
      reviewerSummary: 'No hand and Air Board concern was detected from the available signals.',
    );
  }

  String _buildManifest(rust_air.AirBoardActivitySummary summary) {
    final handPart = ':hand=${_handDecision.behaviourLabel}:hand_attention=${_handDecision.attentionLevel}';
    if (_useNativeAirBoard) {
      try {
        return rust_air.buildAirBoardEvidenceManifest(
              sessionId: 'student-air-board-demo',
              attemptId: 'attempt-${_openedAt.millisecondsSinceEpoch}',
              summary: summary,
            ) +
            handPart;
      } catch (_) {}
    }
    return 'air_board:student-air-board-demo:attempt-${_openedAt.millisecondsSinceEpoch}:'
        'active=${summary.active}:strokes=${summary.strokeCount}:'
        'points=${summary.totalPoints}:duration_ms=${summary.activeDurationMs}:'
        'attention=${summary.attentionLevel}$handPart';
  }

  rust_air.AirBoardActivitySummary _analyzeWithDart(
    rust_air.AirBoardContext context,
  ) {
    final strokeCount = context.strokes.length;
    final totalPoints = context.strokes.fold<int>(
      0,
      (count, stroke) => count + stroke.points.length,
    );
    final activeDurationMs = context.isOpen && context.openedAtMs > 0
        ? (context.nowMs - context.openedAtMs).clamp(0, 1 << 62).toInt()
        : 0;
    final idleDurationMs = context.lastActivityAtMs > 0
        ? (context.nowMs - context.lastActivityAtMs).clamp(0, 1 << 62).toInt()
        : activeDurationMs;
    final currentlyWriting = context.isOpen && idleDurationMs <= 4000 && totalPoints > 0;

    late final String attentionLevel;
    late final String reason;
    if (!context.isOpen) {
      attentionLevel = 'normal';
      reason = 'rough-work board is closed';
    } else if (currentlyWriting) {
      attentionLevel = 'normal';
      reason = 'rough-work board is active and writing is in progress';
    } else if (totalPoints == 0 && activeDurationMs > 60000) {
      attentionLevel = 'medium_attention_required';
      reason = 'rough-work board has been open without writing activity';
    } else if (idleDurationMs > 120000) {
      attentionLevel = 'medium_attention_required';
      reason = 'rough-work board is open but has been idle for a long time';
    } else {
      attentionLevel = 'normal';
      reason = 'rough-work board activity is within expected range';
    }

    return rust_air.AirBoardActivitySummary(
      active: context.isOpen,
      currentlyWriting: currentlyWriting,
      strokeCount: strokeCount,
      pageCount: context.pageCount < 0 ? 0 : context.pageCount,
      activePageIndex: context.activePageIndex < 0 ? 0 : context.activePageIndex,
      totalPoints: totalPoints,
      activeDurationMs: activeDurationMs,
      idleDurationMs: idleDurationMs,
      attentionLevel: attentionLevel,
      reason: reason,
    );
  }

  rust_air.AirBoardStroke _toRustStroke(_AirBoardStroke stroke) {
    return rust_air.AirBoardStroke(
      strokeId: stroke.id,
      pageIndex: stroke.pageIndex,
      tool: stroke.tool.name,
      points: stroke.points.map(_toRustPoint).toList(growable: false),
      startedAtMs: stroke.startedAt.millisecondsSinceEpoch,
      endedAtMs: stroke.endedAt.millisecondsSinceEpoch,
    );
  }

  rust_air.AirBoardStrokePoint _toRustPoint(_AirBoardPoint point) {
    return rust_air.AirBoardStrokePoint(
      x: point.position.dx,
      y: point.position.dy,
      pressure: 1,
      timestampMs: point.timestamp.millisecondsSinceEpoch,
    );
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
                    _AirBoardIntroCard(summary: _rustSummary, handDecision: _handDecision),
                    const SizedBox(height: 14),
                    _AirBoardCameraPanel(
                      controller: _camera,
                      status: _cameraStatus,
                      opening: _openingCamera,
                      handSignal: _handSignal,
                      handDecision: _handDecision,
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
                          const SizedBox(height: 12),
                          _RustEvidenceCard(
                            summary: _rustSummary,
                            manifest: _evidenceManifest,
                            handDecision: _handDecision,
                            handSignal: _handSignal,
                          ),
                        ],
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 315,
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
                                _RustEvidenceCard(
                                  summary: _rustSummary,
                                  manifest: _evidenceManifest,
                                  handDecision: _handDecision,
                                  handSignal: _handSignal,
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
  const _AirBoardIntroCard({required this.summary, required this.handDecision});

  final rust_air.AirBoardActivitySummary summary;
  final rust_hand.HandAirBoardDecision handDecision;

  @override
  Widget build(BuildContext context) {
    final activeLabel = summary.active ? 'Active' : 'Ready';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_brandDark, Color(0xFF113A63), _brand],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: Color(0x160F172A), blurRadius: 22, offset: Offset(0, 12))],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 680;
          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [_WhiteTag('Exam area'), _WhiteTag('Camera hand check'), _WhiteTag('Rust brain_core')],
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
                'Your writing strokes and camera hand signal are converted into Rust context so the AI engine can understand whether hand activity matches rough work.',
                style: TextStyle(color: Color(0xFFE2E8F0), height: 1.45, fontWeight: FontWeight.w600),
              ),
            ],
          );
          final stats = Container(
            width: wide ? 260 : double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HeaderStat(label: 'Status', value: activeLabel),
                const SizedBox(height: 8),
                _HeaderStat(label: 'Strokes', value: '${summary.strokeCount}'),
                const SizedBox(height: 8),
                _HeaderStat(label: 'Air Board', value: _friendlyLevel(summary.attentionLevel)),
                const SizedBox(height: 8),
                _HeaderStat(label: 'Hand match', value: handDecision.handMatchesAirBoard ? 'Matched' : 'Watching'),
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

class _AirBoardCameraPanel extends StatelessWidget {
  const _AirBoardCameraPanel({
    required this.controller,
    required this.status,
    required this.opening,
    required this.handSignal,
    required this.handDecision,
  });

  final CameraController? controller;
  final String status;
  final bool opening;
  final rust_hand.HandRegionSignal handSignal;
  final rust_hand.HandAirBoardDecision handDecision;

  @override
  Widget build(BuildContext context) {
    final camera = controller;
    final ready = camera != null && camera.value.isInitialized;
    return _PanelCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 150,
              height: 94,
              color: _brandDark,
              child: ready
                  ? FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: camera.value.previewSize?.height ?? 150,
                        height: camera.value.previewSize?.width ?? 94,
                        child: CameraPreview(camera),
                      ),
                    )
                  : Icon(
                      opening ? Icons.hourglass_top_rounded : Icons.videocam_off_outlined,
                      color: Colors.white,
                      size: 30,
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _PanelTitle(icon: Icons.photo_camera_front_outlined, title: 'Camera hand monitor'),
                const SizedBox(height: 8),
                Text(status, style: const TextStyle(color: _muted, fontWeight: FontWeight.w700, height: 1.4)),
                const SizedBox(height: 8),
                _EvidenceLine(label: 'Hand signal', value: handSignal.handVisible ? 'Visible' : 'Not clear'),
                _EvidenceLine(label: 'Hand confidence', value: '${(handSignal.handConfidence * 100).round()}%'),
                _EvidenceLine(label: 'Hand/Air Board', value: _friendlyLevel(handDecision.attentionLevel)),
                Text(
                  handDecision.studentMessage,
                  style: const TextStyle(color: _brandDark, height: 1.4, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Note: this currently uses the camera availability and board activity as the hand signal source. Real hand landmark detection will replace this placeholder.',
                  style: TextStyle(color: _muted, fontSize: 12, height: 1.35, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
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
              Expanded(child: OutlinedButton.icon(onPressed: onUndo, icon: const Icon(Icons.undo_rounded), label: const Text('Undo'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(onPressed: onClear, icon: const Icon(Icons.delete_outline_rounded), label: const Text('Clear'))),
            ],
          ),
        ],
      ),
    );
  }
}

class _BoardPageTabs extends StatelessWidget {
  const _BoardPageTabs({required this.pages, required this.activePageIndex, required this.onSelect, required this.onAdd});

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
              OutlinedButton.icon(onPressed: onAdd, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add')),
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
        boxShadow: const [BoxShadow(color: Color(0x080F172A), blurRadius: 18, offset: Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(14)),
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
              child: Listener(
                onPointerDown: (event) => onStart(event.localPosition),
                onPointerMove: (event) => onMove(event.localPosition),
                onPointerUp: (_) => onEnd(),
                onPointerCancel: (_) => onEnd(),
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _AirBoardPainter(page: page, activeStroke: activeStroke, background: background),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RustEvidenceCard extends StatelessWidget {
  const _RustEvidenceCard({
    required this.summary,
    required this.manifest,
    required this.handDecision,
    required this.handSignal,
  });

  final rust_air.AirBoardActivitySummary summary;
  final String manifest;
  final rust_hand.HandAirBoardDecision handDecision;
  final rust_hand.HandRegionSignal handSignal;

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle(icon: Icons.memory_outlined, title: 'Rust Air Board result'),
          const SizedBox(height: 12),
          _EvidenceLine(label: 'Currently writing', value: summary.currentlyWriting ? 'Yes' : 'No'),
          _EvidenceLine(label: 'Active page', value: 'Page ${summary.activePageIndex + 1}'),
          _EvidenceLine(label: 'Strokes', value: '${summary.strokeCount}'),
          _EvidenceLine(label: 'Points', value: '${summary.totalPoints}'),
          _EvidenceLine(label: 'Air Board', value: _friendlyLevel(summary.attentionLevel)),
          const Divider(height: 20, color: _line),
          _EvidenceLine(label: 'Hand visible', value: handSignal.handVisible ? 'Yes' : 'No'),
          _EvidenceLine(label: 'Hand match', value: handDecision.handMatchesAirBoard ? 'Matched' : 'Not confirmed'),
          _EvidenceLine(label: 'Hand review', value: handDecision.reviewRequired ? 'Review' : 'Normal'),
          _EvidenceLine(label: 'Hand level', value: _friendlyLevel(handDecision.attentionLevel)),
          const SizedBox(height: 10),
          Text(summary.reason, style: const TextStyle(color: _muted, height: 1.4, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(handDecision.reviewerSummary, style: const TextStyle(color: _muted, height: 1.4, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          SelectableText(
            manifest,
            style: const TextStyle(color: _brandDark, fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _AirBoardPainter extends CustomPainter {
  const _AirBoardPainter({required this.page, required this.activeStroke, required this.background});

  final _AirBoardPage page;
  final _AirBoardStroke? activeStroke;
  final _BoardBackground background;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
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
    for (var y = 32.0; y < size.height; y += 32) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
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
  bool shouldRepaint(covariant _AirBoardPainter oldDelegate) => true;
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
        boxShadow: const [BoxShadow(color: Color(0x080F172A), blurRadius: 18, offset: Offset(0, 10))],
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
        Expanded(child: Text(title, style: const TextStyle(color: _brandDark, fontWeight: FontWeight.w900, fontSize: 16))),
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
      decoration: BoxDecoration(color: _warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: const TextStyle(color: Color(0xFF92400E), fontWeight: FontWeight.w900, fontSize: 12)),
    );
  }
}

String _friendlyLevel(String value) {
  switch (value) {
    case 'normal':
      return 'Normal';
    case 'medium_attention_required':
      return 'Attention needed';
    case 'high_attention_required':
      return 'Review needed';
    case 'urgent_review_required':
      return 'Urgent review';
    default:
      return value.replaceAll('_', ' ');
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
