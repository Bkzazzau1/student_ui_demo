# Local patch: wire object model frame gate into LiveExamMonitor

This patch is the only part that did not land through the connector. Apply it locally in `lib/proctoring_demo/live_exam_monitor.dart`.

## Goal

Start the object model frame gate from the existing live camera frame bus. It must not open a second camera controller. It should stay disabled until this asset exists:

```text
assets/models/kslas_object_mvp.onnx
```

`pubspec.yaml` already includes the whole folder:

```yaml
flutter:
  assets:
    - assets/models/
```

## 1. Add state fields

Inside `_LiveExamMonitorState`, near the existing `_frameBus` field, add:

```dart
final ObjectModelFrameGate _objectFrameGate = ObjectModelFrameGate();
```

Near the status fields, add:

```dart
String _objectStatus = 'Object review waiting for model file...';
bool _objectReady = false;
int _objectFramesReady = 0;
```

## 2. Start and stop the gate

In `initState()`, before `_startCamera()`, add:

```dart
unawaited(_startObjectModelGate());
```

In `dispose()`, before releasing the camera lease, add:

```dart
unawaited(_objectFrameGate.stop());
```

## 3. Add the method

Add this method inside `_LiveExamMonitorState`:

```dart
Future<void> _startObjectModelGate() async {
  final status = await _objectFrameGate.start(
    onFrameReady: (frame) {
      _objectFramesReady = frame.sequence;
      if (!mounted) return;
      setState(() {
        _objectReady = true;
        _objectStatus = 'Object review frame ready: ${frame.sequence}';
      });
    },
  );
  if (!mounted) return;
  setState(() {
    _objectReady = status.running;
    _objectStatus = status.assetPresent
        ? 'Object model file found • frame gate active'
        : 'Object review disabled until model file is added';
  });
  await _raiseEvent(
    eventType: status.assetPresent
        ? 'object_model_frame_gate_ready'
        : 'object_model_asset_missing',
    severity: 'info',
    message: status.message,
    metadata: status.toJson(),
  );
}
```

## 4. Show status in the UI

In the status rows, add this before the system status row:

```dart
const SizedBox(height: 8),
_StatusRow(
  label: _objectStatus,
  ready: _objectReady,
  icon: Icons.center_focus_strong_outlined,
),
```

After `Text('Camera frames shared: $_framesPublished'),` add:

```dart
if (_objectFramesReady > 0)
  Text('Object review frames ready: $_objectFramesReady'),
```

## 5. Add the model later

When ready, place the object model here:

```text
assets/models/kslas_object_mvp.onnx
```

Then run:

```bash
flutter clean
flutter pub get
flutter run -d windows
```

The gate will automatically switch from disabled to active when the asset appears in `AssetManifest.json`.
