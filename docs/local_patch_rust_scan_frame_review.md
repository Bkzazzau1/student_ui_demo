# Local patch: wire Rust scan-frame review into the 360 room scan

This patch connects `NativeScanFrameReviewService` to `lib/proctoring_demo/proctoring_demo_home.dart` so every accepted room-scan frame can carry Rust brain object labels into the existing target labels and review manifest.

## 1. Add import

Near the existing scan imports, add:

```dart
import 'native_scan_frame_review_service.dart';
```

## 2. Add service field

Inside `_ProctoringDemoHomeState`, near `_frameSource`, add:

```dart
final NativeScanFrameReviewService _nativeScanReview =
    NativeScanFrameReviewService();
```

## 3. Update `_acceptTargetFrame`

Replace:

```dart
final labels = _labelsFor(frame);
```

with:

```dart
final nativeReview = await _nativeScanReview.analyse(frame);
final labels = _labelsFor(frame, nativeReview);
final lightingScore = nativeReview?.available == true
    ? nativeReview!.lightingScore
    : frame.luma;
```

Then, inside the `setState` block after capture validation, change:

```dart
_lightingScore = frame.luma;
```

so accepted frames later use:

```dart
_lightingScore = lightingScore;
```

In the `DemoCalibrationEntry`, replace:

```dart
lightingScore: frame.luma,
note: 'Accepted after movement check.',
```

with:

```dart
lightingScore: lightingScore,
note: nativeReview?.available == true
    ? 'Accepted after movement and room object check.'
    : 'Accepted after movement check.',
```

## 4. Replace `_labelsFor`

Replace the current `_labelsFor(DemoCameraScanFrame frame)` method with:

```dart
List<String> _labelsFor(
  DemoCameraScanFrame frame,
  NativeScanFrameReviewResult? nativeReview,
) {
  final labels = <String>{};
  final lightingScore = nativeReview?.available == true
      ? nativeReview!.lightingScore
      : frame.luma;

  if (lightingScore < 0.08) labels.add('low light');
  if (lightingScore > 0.82) labels.add('possible glare');
  labels.add('movement checked');

  if (nativeReview?.available == true) {
    labels.add('room object check completed');
    labels.addAll(nativeReview!.objectLabels);
    if (nativeReview.faceCount > 0) {
      labels.add('face count ${nativeReview.faceCount}');
    }
  }

  return labels.toList()..sort();
}
```

## 5. Why this works

`_buildReviewManifest()` already sends target labels, so once `_targets[_currentTargetIndex]` receives the Rust labels, the backend review receives them automatically:

```dart
'labels': target.labels,
```

## 6. Verify

Run:

```bash
flutter analyze --no-pub lib\proctoring_demo\native_scan_frame_review_service.dart
flutter analyze --no-pub lib\proctoring_demo\proctoring_demo_home.dart
```

Then run the pre-exam room scan and inspect the saved manifest. Each target should include normal labels plus Rust labels such as `phone` or `laptop` when the Rust fallback detector sees a rectangular object.
