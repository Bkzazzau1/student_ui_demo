/// Engineering guardrails for the pre-YOLO revision.
///
/// YOLO should be added only after these runtime guarantees are stable:
/// 1. Live events are queued locally when the backend is unavailable.
/// 2. Every event uses the shared risk policy.
/// 3. Release builds cannot use exam-start override flags for strict exams.
/// 4. Evidence paths are attached to important events instead of saving
///    continuous raw video for every clean student.
/// 5. Camera usage is kept lightweight enough for low-cost student laptops.
class PreYoloReviewNotes {
  const PreYoloReviewNotes._();

  static const List<String> requiredBeforeYolo = <String>[
    'event_queue',
    'risk_policy',
    'release_override_guard',
    'selective_evidence',
    'single_camera_runtime',
  ];
}
