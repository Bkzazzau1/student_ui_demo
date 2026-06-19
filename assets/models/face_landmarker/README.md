# Face Landmarker model

Place the production MediaPipe Face Landmarker model bundle here:

```text
assets/models/face_landmarker/face_landmarker.task
```

This file is intentionally not committed here because model bundles are binary assets and may need Git LFS or release-asset storage. The Flutter app is now wired to load this asset path and copy it to a local runtime file before invoking the native landmark runtime.

Expected model:

```text
MediaPipe Face Landmarker task bundle
```

The live exam monitor will use the landmark runtime when the model and native method-channel implementation are available. If either is missing, it falls back to the built-in lightweight estimator so exam monitoring continues.
