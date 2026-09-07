from pathlib import Path

PATH = Path('lib/proctoring_demo/live_exam_monitor.dart')


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one anchor, found {count}')
    return source.replace(old, new, 1)


source = PATH.read_text(encoding='utf-8')

source = replace_once(
    source,
    "import 'native_edge_ai_action_authorizer.dart';\n",
    "import 'native_edge_ai_action_authorizer.dart';\n"
    "import 'native_model_event_memory_bridge.dart';\n",
    'native memory import',
)

source = replace_once(
    source,
    "  final OptimizedVisionObjectEventAdapter _objectEventAdapter =\n"
    "      const OptimizedVisionObjectEventAdapter();\n",
    "  final OptimizedVisionObjectEventAdapter _objectEventAdapter =\n"
    "      const OptimizedVisionObjectEventAdapter();\n"
    "  final NativeModelEventMemoryBridge _modelEventMemory =\n"
    "      NativeModelEventMemoryBridge();\n",
    'native memory field',
)

source = replace_once(
    source,
    "    unawaited(_objectFrameGate.stop());\n"
    "    _microphone.dispose();\n",
    "    unawaited(_objectFrameGate.stop());\n"
    "    unawaited(_modelEventMemory.clear(widget.attemptId));\n"
    "    _microphone.dispose();\n",
    'native memory lifecycle clear',
)

source = replace_once(
    source,
    "    unawaited(_analyseCameraImage(image, started));\n",
    "    unawaited(_analyseCameraImage(frame, started));\n",
    'frame provenance handoff',
)

source = replace_once(
    source,
    "  Future<void> _analyseCameraImage(CameraImage image, DateTime started) async {\n"
    "    try {\n"
    "      _handleFrameQuality(image);\n",
    "  Future<void> _analyseCameraImage(\n"
    "    LiveCameraFrame frame,\n"
    "    DateTime started,\n"
    "  ) async {\n"
    "    final image = frame.image;\n"
    "    try {\n"
    "      _handleFrameQuality(image);\n",
    'analysis frame signature',
)

source = replace_once(
    source,
    "      final optimized = await _optimizedVision.runFrame(\n"
    "        image: image,\n"
    "        tasks: const <String>[\n"
    "          'person_detector',\n"
    "          'object_reflection_shadow_detector',\n"
    "        ],\n"
    "      );\n",
    "      final optimized = await _optimizedVision.runFrame(\n"
    "        image: image,\n"
    "        tasks: const <String>[\n"
    "          'person_detector',\n"
    "          'object_reflection_shadow_detector',\n"
    "        ],\n"
    "        sourceFrameId: frame.sequence,\n"
    "        captureTimestampNs: frame.captureTimestampNs,\n"
    "      );\n",
    'optimized inference provenance',
)

source = replace_once(
    source,
    "  void _handleOptimizedVisionResult(OptimizedVisionRuntimeResult result) {\n"
    "    final objects = (result.outputs['objects'] as List? ?? const <Object?>[])\n",
    "  void _handleOptimizedVisionResult(OptimizedVisionRuntimeResult result) {\n"
    "    final modelEvents = _objectEventAdapter.mapModelEvents(\n"
    "      result,\n"
    "      sessionId: widget.attemptId,\n"
    "    );\n"
    "    for (final modelEvent in modelEvents) {\n"
    "      unawaited(_modelEventMemory.ingest(modelEvent));\n"
    "    }\n\n"
    "    final objects = (result.outputs['objects'] as List? ?? const <Object?>[])\n",
    'formal E1 memory ingress',
)

PATH.write_text(source, encoding='utf-8')
print('E1 live ModelEventV1 -> Rust memory wiring applied successfully.')
