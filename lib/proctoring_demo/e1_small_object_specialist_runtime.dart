import 'e1_small_object_specialist.dart';
import 'e1_specialist_frame.dart';

/// Executable live-runtime boundary for a local E1 small-object specialist.
///
/// Unlike the planner-only request contract, this interface receives the real
/// local frame envelope. Implementations must not call cloud inference or
/// external foundation models during an exam.
abstract interface class E1SmallObjectSpecialistRuntime {
  Future<List<E1SmallObjectSpecialistObservation>> infer({
    required E1SmallObjectSpecialistRequest request,
    required E1SpecialistFrameInput frame,
  });
}

/// Safe production fallback while no validated specialist model is installed.
///
/// Returning an empty list means "no specialist evidence available". It must
/// never synthesize detections from planner requests or base-model labels.
class UnavailableE1SmallObjectSpecialistRuntime
    implements E1SmallObjectSpecialistRuntime {
  const UnavailableE1SmallObjectSpecialistRuntime();

  @override
  Future<List<E1SmallObjectSpecialistObservation>> infer({
    required E1SmallObjectSpecialistRequest request,
    required E1SpecialistFrameInput frame,
  }) async {
    return const <E1SmallObjectSpecialistObservation>[];
  }
}

class E1SpecialistRuntimeGuard {
  const E1SpecialistRuntimeGuard();

  bool canInfer({
    required E1SmallObjectSpecialistRequest request,
    required E1SpecialistFrameInput frame,
  }) {
    return request.isValid && frame.matchesRequest(request);
  }

  List<E1SmallObjectSpecialistObservation> retainValidObservations(
    Iterable<E1SmallObjectSpecialistObservation> observations,
  ) {
    return List<E1SmallObjectSpecialistObservation>.unmodifiable(
      observations.where((observation) => observation.isValid),
    );
  }
}
