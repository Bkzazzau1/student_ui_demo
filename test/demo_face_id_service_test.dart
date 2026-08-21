import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:students_ui_demo/face_demo/demo_face_id_service.dart';

Future<(DemoFaceIdService, Directory)> _service(String container) async {
  final dir = Directory.systemTemp.createTempSync('face_id_test_$container');
  final storage = GetStorage(container, dir.path);
  await storage.initStorage;
  return (DemoFaceIdService(storage: storage), dir);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  // GetStorage unconditionally probes path_provider even when an explicit
  // path is supplied; `flutter test` never registers the real plugin, so it
  // must be stubbed here purely to satisfy that probe.
  binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => Directory.systemTemp.path,
  );

  test('a fresh student has not enrolled and is not locked', () async {
    final (service, _) = await _service('fresh_student');
    final snapshot = service.load();

    expect(snapshot.locked, isFalse);
    expect(snapshot.isComplete, isFalse);
    expect(snapshot.capturedSamples, 0);
  });

  test('local development approval locks the identity immediately', () async {
    final (service, _) = await _service('dev_approval');

    final approved = await service.approveLocalDevelopmentEnrollment(
      enrollmentId: 'local-1',
      qualityScore: 0.82,
    );

    expect(approved.locked, isTrue);
    expect(approved.backendSynced, isTrue);
    expect(approved.capturedSamples, DemoFaceIdService.requiredSamples);
    expect(approved.isComplete, isTrue);
  });

  test('a locked identity is durably persisted to disk, surviving a restart', () async {
    // GetStorage caches one in-memory instance per container name for the
    // life of the process, so a second in-process construction cannot
    // exercise a genuine "cold start reads from disk" path. What actually
    // makes the identity survive an app restart is that the locked state is
    // flushed to the on-disk `.gs` file, so this verifies that file directly
    // instead of only re-reading the same cached in-memory instance.
    final container = 'restart_durability';
    final (service, dir) = await _service(container);
    await service.approveLocalDevelopmentEnrollment(
      enrollmentId: 'local-restart',
      qualityScore: 0.8,
    );

    final file = dir
        .listSync()
        .whereType<File>()
        .firstWhere((entry) => entry.path.endsWith('$container.gs'));
    // get_storage's flush lock on Windows can outlive the Future returned by
    // `write()` by a few milliseconds, so give the OS a moment to release it
    // before reading the file back directly.
    Map persisted = const {};
    for (var attempt = 0; attempt < 20; attempt++) {
      try {
        persisted = jsonDecode(await file.readAsString()) as Map;
        break;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    expect(persisted['demo_face_id_locked'], isTrue);
    expect(persisted['demo_face_id_enrollment_id'], 'local-restart');
    expect(persisted['demo_face_id_status'], 'dev_local_approved');
  });

  test('a locked identity cannot be overwritten by the normal capture flow', () async {
    final (service, _) = await _service('locked_cannot_overwrite');
    await service.approveLocalDevelopmentEnrollment(
      enrollmentId: 'local-locked',
      qualityScore: 0.9,
    );

    final afterAddSample = await service.addSample(qualityScore: 0.95);
    final afterReset = await service.resetLocalDraftOnly();

    expect(afterAddSample.locked, isTrue);
    expect(afterAddSample.enrollmentId, 'local-locked');
    expect(afterReset.locked, isTrue);
    expect(afterReset.enrollmentId, 'local-locked');
  });

  test('beginDeviceEnrollment (used by the debug reset) requires enrollment again', () async {
    final (service, _) = await _service('debug_reset_requires_enrollment');
    await service.approveLocalDevelopmentEnrollment(
      enrollmentId: 'local-before-reset',
      qualityScore: 0.9,
    );

    final afterReset = await service.beginDeviceEnrollment();

    expect(afterReset.locked, isFalse);
    expect(afterReset.capturedSamples, 0);
    expect(afterReset.isComplete, isFalse);
  });
}
