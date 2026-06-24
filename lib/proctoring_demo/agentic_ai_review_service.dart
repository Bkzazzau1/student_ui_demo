import 'dart:async';

import 'proctoring_demo_models.dart';

abstract class AgenticAiReviewService {
  Stream<AgenticReviewEvent> review({
    required List<DemoScanTarget> targets,
    required List<DemoCalibrationEntry> calibrationLog,
  });
}

class MockAgenticAiReviewService implements AgenticAiReviewService {
  @override
  Stream<AgenticReviewEvent> review({
    required List<DemoScanTarget> targets,
    required List<DemoCalibrationEntry> calibrationLog,
  }) async* {
    yield const AgenticReviewEvent(
      title: 'Security review started',
      detail: 'Reviewing captured room evidence, scan coverage, and labels.',
      severity: 'info',
    );
    await Future<void>.delayed(const Duration(milliseconds: 650));

    final missing = targets.where((target) => !target.captured).toList();
    if (missing.isEmpty) {
      yield const AgenticReviewEvent(
        title: '360 coverage complete',
        detail:
            'All required room, desk, lap, ceiling, and floor targets were captured.',
        severity: 'success',
      );
    } else {
      yield AgenticReviewEvent(
        title: 'Coverage needs review',
        detail: 'Missing: ${missing.map((target) => target.name).join(', ')}.',
        severity: 'warning',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 650));

    final lowLight = calibrationLog
        .where((entry) => entry.lightingScore < 0.22)
        .map((entry) => entry.target)
        .toSet()
        .toList();
    if (lowLight.isEmpty) {
      yield const AgenticReviewEvent(
        title: 'Lighting accepted',
        detail: 'Recent evidence frames have enough brightness for review.',
        severity: 'success',
      );
    } else {
      yield AgenticReviewEvent(
        title: 'Lighting concern',
        detail: 'Low light appeared in: ${lowLight.take(4).join(', ')}.',
        severity: 'warning',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 650));

    final forbiddenLabels = calibrationLog
        .expand((entry) => entry.labels)
        .where((label) => label.contains('possible') || label.contains('dark'))
        .toSet()
        .toList();
    if (forbiddenLabels.isEmpty) {
      yield const AgenticReviewEvent(
        title: 'No risk labels',
        detail:
            'No simulated unauthorized item or bad environment labels were raised.',
        severity: 'success',
      );
    } else {
      yield AgenticReviewEvent(
        title: 'Risk labels found',
        detail: forbiddenLabels.join(', '),
        severity: 'warning',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 650));

    yield AgenticReviewEvent(
      title: missing.isEmpty && lowLight.isEmpty
          ? 'Decision: ready'
          : 'Decision: pending review',
      detail: missing.isEmpty && lowLight.isEmpty
          ? 'Start approval is required before the exam can begin.'
          : 'The student must fix issues or request human review.',
      severity: missing.isEmpty && lowLight.isEmpty ? 'success' : 'warning',
    );
  }
}
