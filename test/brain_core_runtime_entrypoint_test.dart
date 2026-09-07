import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/rust/brain_core_runtime.dart';
import 'package:students_ui_demo/rust/frb_generated.dart';

void main() {
  test('handwritten runtime wrapper targets the generated FRB entrypoint', () {
    // Compile-time guard: both tear-offs must resolve without initializing the
    // native library in the Flutter test process.
    expect(BrainCoreRuntime.ensureInitialized, isA<Function>());
    expect(RustLib.init, isA<Function>());
  });
}
