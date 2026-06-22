class EvidenceAttachment {
  const EvidenceAttachment({
    required this.kind,
    required this.localPath,
    required this.createdAt,
    this.durationSeconds,
  });

  final String kind;
  final String localPath;
  final DateTime createdAt;
  final int? durationSeconds;

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind,
        'local_path': localPath,
        'created_at': createdAt.toUtc().toIso8601String(),
        if (durationSeconds != null) 'duration_seconds': durationSeconds,
      };
}

class EvidenceEventRecord {
  const EvidenceEventRecord({
    required this.eventType,
    required this.studentId,
    required this.examId,
    required this.attemptId,
    required this.createdAt,
    required this.attachments,
    this.metadata = const <String, Object?>{},
  });

  final String eventType;
  final String studentId;
  final String examId;
  final String attemptId;
  final DateTime createdAt;
  final List<EvidenceAttachment> attachments;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() => <String, Object?>{
        'event_type': eventType,
        'student_id': studentId,
        'exam_id': examId,
        'attempt_id': attemptId,
        'created_at': createdAt.toUtc().toIso8601String(),
        'attachments': attachments.map((item) => item.toJson()).toList(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };
}
