import 'local_evidence_vault_service.dart';
import 'live_proctoring_event_service.dart';

class LiveEventLocalRecordService {
  const LiveEventLocalRecordService({
    this.vault = const LocalEvidenceVaultService(),
  });

  final LocalEvidenceVaultService vault;

  Future<Map<String, Object?>?> saveEvent(LiveProctoringEvent event) async {
    try {
      final record = await vault.saveJsonEvidence(
        studentId: event.studentId,
        examId: event.examId,
        attemptId: event.attemptId,
        eventType: event.eventType,
        reviewReason: event.message,
        payload: event.toJson(),
        metadata: <String, Object?>{
          'source': 'live_proctoring_event',
          'severity': event.severity,
          'assessment_type': event.assessmentType,
          'review_audience': event.reviewAudience,
        },
      );
      return record.toJson();
    } catch (_) {
      return null;
    }
  }
}
