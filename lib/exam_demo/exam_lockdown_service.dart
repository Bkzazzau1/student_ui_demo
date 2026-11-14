import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ExamDeviceReadiness {
  const ExamDeviceReadiness({
    required this.supported,
    required this.screenCaptureBlocked,
    required this.clipboardCleared,
    required this.outputMuted,
    required this.microphoneMuted,
    required this.lockTaskActive,
    this.screenCaptureActive = false,
    this.lockMode = '',
  });

  final bool supported;
  final bool screenCaptureBlocked;
  final bool clipboardCleared;
  final bool outputMuted;
  final bool microphoneMuted;

  /// Android screen pinning, or Guided Access on iPad.
  final bool lockTaskActive;

  /// iPad: the screen is being recorded, mirrored or shared right now.
  final bool screenCaptureActive;

  /// `guided_access` on iPad; empty elsewhere.
  final String lockMode;

  bool get usesGuidedAccess => lockMode == 'guided_access';

  bool get ready =>
      supported &&
      screenCaptureBlocked &&
      clipboardCleared &&
      !outputMuted &&
      !microphoneMuted;

  String get message {
    if (!supported) return 'Secure mobile exam controls are unavailable.';
    if (microphoneMuted) {
      return usesGuidedAccess
          ? 'Allow microphone access for K-SLAS in Settings before continuing.'
          : 'Unmute microphone access before continuing.';
    }
    if (outputMuted) return 'Turn up device sound before continuing.';
    if (screenCaptureActive) {
      return 'Stop screen recording or screen mirroring before continuing.';
    }
    if (!screenCaptureBlocked) {
      return 'Screen-capture protection could not be enabled.';
    }
    if (!clipboardCleared) return 'Clipboard protection could not be enabled.';
    if (usesGuidedAccess && !lockTaskActive) {
      return 'Turn on Guided Access to start the exam.';
    }
    return 'Sound, screen-capture protection, and clipboard controls are ready.';
  }

  factory ExamDeviceReadiness.fromMap(Map<Object?, Object?> map) {
    return ExamDeviceReadiness(
      supported: map['supported'] == true,
      screenCaptureBlocked: map['screen_capture_blocked'] == true,
      clipboardCleared: map['clipboard_cleared'] == true,
      outputMuted: map['output_muted'] == true,
      microphoneMuted: map['microphone_muted'] == true,
      lockTaskActive: map['lock_task_active'] == true,
      screenCaptureActive: map['screen_capture_active'] == true,
      lockMode: map['lock_mode']?.toString() ?? '',
    );
  }
}

/// A lockdown change reported by the device while an exam is open (iPad).
class ExamLockdownEvent {
  const ExamLockdownEvent({
    required this.type,
    required this.details,
    required this.readiness,
  });

  /// `guided_access_changed`, `screen_capture_changed` or `screenshot_taken`.
  final String type;
  final Map<String, Object?> details;
  final ExamDeviceReadiness readiness;

  bool get guidedAccessEnded =>
      type == 'guided_access_changed' && details['enabled'] != true;
  bool get guidedAccessStarted =>
      type == 'guided_access_changed' && details['enabled'] == true;
  bool get screenCaptureStarted =>
      type == 'screen_capture_changed' && details['captured'] == true;
  bool get screenCaptureStopped =>
      type == 'screen_capture_changed' && details['captured'] != true;
  bool get screenshotTaken => type == 'screenshot_taken';

  factory ExamLockdownEvent.fromMap(Map<Object?, Object?> map) {
    final details = <String, Object?>{};
    for (final entry in map.entries) {
      final key = entry.key?.toString();
      if (key == null || key == 'readiness') continue;
      details[key] = entry.value;
    }
    return ExamLockdownEvent(
      type: map['type']?.toString() ?? '',
      details: details,
      readiness: ExamDeviceReadiness.fromMap(
        map['readiness'] as Map<Object?, Object?>? ??
            const <Object?, Object?>{},
      ),
    );
  }
}

class ExamLockdownService {
  const ExamLockdownService();

  static const MethodChannel _channel = MethodChannel('kslas.exam_lockdown');
  static final StreamController<ExamLockdownEvent> _events =
      StreamController<ExamLockdownEvent>.broadcast();
  static bool _listening = false;

  bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  bool get _native => isAndroid || isIOS;

  /// Whether a graded exam may only start once the device is locked to the
  /// app: Android screen pinning, or Guided Access on iPad.
  bool get requiresLockTask => isAndroid || isIOS;

  /// Lockdown changes while an exam is open. Only iPad reports them now:
  /// Guided Access turned off or on, screen recording or mirroring, and
  /// screenshots.
  Stream<ExamLockdownEvent> get events {
    if (isIOS && !_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onLockdownEvent' && call.arguments is Map) {
          _events.add(
            ExamLockdownEvent.fromMap(
              Map<Object?, Object?>.from(call.arguments as Map),
            ),
          );
        }
        return null;
      });
    }
    return _events.stream;
  }

  /// Clears the clipboard and reports readiness.
  Future<ExamDeviceReadiness> prepare() async {
    if (!_native) {
      return const ExamDeviceReadiness(
        supported: true,
        screenCaptureBlocked: true,
        clipboardCleared: true,
        outputMuted: false,
        microphoneMuted: false,
        lockTaskActive: false,
      );
    }
    final result = await _channel.invokeMapMethod<Object?, Object?>('prepare');
    return ExamDeviceReadiness.fromMap(result ?? const <Object?, Object?>{});
  }

  /// Reports readiness without changing anything (iPad), for waiting until
  /// the student turns Guided Access on.
  Future<ExamDeviceReadiness> status() async {
    if (!isIOS) return prepare();
    final result = await _channel.invokeMapMethod<Object?, Object?>('status');
    return ExamDeviceReadiness.fromMap(result ?? const <Object?, Object?>{});
  }

  /// Locks the device to the exam where the platform allows it: Android asks
  /// to pin the screen; a school-managed iPad starts Guided Access itself.
  /// Elsewhere on iPad the student turns Guided Access on.
  Future<ExamDeviceReadiness> enter() async {
    if (!_native) return prepare();
    final result = await _channel.invokeMapMethod<Object?, Object?>('enter');
    return ExamDeviceReadiness.fromMap(result ?? const <Object?, Object?>{});
  }

  Future<void> exit() async {
    if (!_native) return;
    await _channel.invokeMethod<void>('exit');
  }
}
