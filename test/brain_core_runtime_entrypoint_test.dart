import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/live_exam_monitor.dart';
import 'package:students_ui_demo/proctoring_demo/native_model_event_memory_sink.dart';
import 'package:students_ui_demo/rust/brain_core_runtime.dart';
import 'package:students_ui_demo/rust/frb_generated.dart';

void main() {
  test('handwritten runtime wrapper targets the generated FRB entrypoint', () {
    // Compile-time guard: these references must resolve without initializing
    // camera or the native library in the Flutter test process.
    expect(BrainCoreRuntime.ensureInitialized, isA<Function>());
    expect(RustLib.init, isA<Function>());
    expect(const NativeModelEventMemorySink(), isNotNull);
    expect(LiveExamMonitor.new, isA<Function>());
  });
}
