# Local patch: raise live object events from optimized vision outputs

This patch connects `OptimizedVisionObjectEventAdapter` to `LiveExamMonitor` so native ONNX/DirectML object outputs can raise the existing policy events:

- `yolo_phone_detected`
- `yolo_extra_screen_detected`
- `yolo_book_or_paper_detected`
- `yolo_calculator_detected`

## 1. Add import

In `lib/proctoring_demo/live_exam_monitor.dart`, near the existing optimized vision import, add:

```dart
import 'optimized_vision_object_event_adapter.dart';
```

## 2. Add field

Inside `_LiveExamMonitorState`, near `_optimizedVision`, add:

```dart
final OptimizedVisionObjectEventAdapter _objectEventAdapter =
    const OptimizedVisionObjectEventAdapter();
```

## 3. Call adapter inside `_handleOptimizedVisionResult`

Inside `_handleOptimizedVisionResult(OptimizedVisionRuntimeResult result)`, after `objects` is created and before multiple-person logic, add:

```dart
final objectEvents = _objectEventAdapter.mapResult(result);
for (final decision in objectEvents) {
  unawaited(
    _raiseEvent(
      eventType: decision.eventType,
      severity: decision.severity,
      message: decision.message,
      metadata: <String, Object?>{
        ...decision.metadata,
        'optimized_vision': result.toJson(),
      },
    ),
  );
}
```

## 4. Student wording

The adapter messages are calm and review-focused. They avoid accusing words and only say that an object was noticed in the camera view.

## 5. Verify locally

Run:

```bash
flutter analyze --no-pub lib\proctoring_demo\optimized_vision_object_event_adapter.dart
flutter test test\optimized_vision_object_event_adapter_test.dart
flutter analyze --no-pub lib\proctoring_demo\live_exam_monitor.dart
```

Then start a live exam with the optimized vision runtime enabled and confirm that object outputs like `cell phone`, `laptop`, `book`, `paper`, or `calculator` produce the matching `yolo_*` event in the live event queue/backend.
