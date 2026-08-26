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
  });

  final bool supported;
  final bool screenCaptureBlocked;
  final bool clipboardCleared;
  final bool outputMuted;
  final bool microphoneMuted;
  final bool lockTaskActive;

  bool get ready =>
      supported &&
      screenCaptureBlocked &&
      clipboardCleared &&
      !outputMuted &&
      !microphoneMuted;

  String get message {
    if (!supported) return 'Secure mobile exam controls are unavailable.';
    if (microphoneMuted) return 'Unmute microphone access before continuing.';
    if (outputMuted) return 'Turn up device sound before continuing.';
    if (!screenCaptureBlocked) {
      return 'Screen-capture protection could not be enabled.';
    }
    if (!clipboardCleared) return 'Clipboard protection could not be enabled.';
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
    );
  }
}

class ExamLockdownService {
  const ExamLockdownService();

  static const MethodChannel _channel = MethodChannel('kslas.exam_lockdown');

  bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<ExamDeviceReadiness> prepare() async {
    if (!isAndroid) {
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

  Future<ExamDeviceReadiness> enter() async {
    if (!isAndroid) return prepare();
    final result = await _channel.invokeMapMethod<Object?, Object?>('enter');
    return ExamDeviceReadiness.fromMap(result ?? const <Object?, Object?>{});
  }

  Future<void> exit() async {
    if (!isAndroid) return;
    await _channel.invokeMethod<void>('exit');
  }
}
