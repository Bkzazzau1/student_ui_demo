import '../rust/api/system_security.dart' as native_system_security;
import '../rust/frb_generated.dart';
import 'system_security_review_service.dart';

class NativeSystemSecurityReviewSnapshot {
  const NativeSystemSecurityReviewSnapshot({
    required this.ready,
    required this.platformSupported,
    required this.bluetoothDetected,
    required this.externalAudioDetected,
    required this.usbRiskDetected,
    required this.virtualizationDetected,
    required this.virtualizationWarningDetected,
    required this.containerDetected,
    required this.virtualCameraDetected,
    required this.unknownDeviceState,
    required this.findings,
    required this.hardFindings,
    required this.warningFindings,
    required this.message,
  });

  final bool ready;
  final bool platformSupported;
  final bool bluetoothDetected;
  final bool externalAudioDetected;
  final bool usbRiskDetected;
  final bool virtualizationDetected;
  final bool virtualizationWarningDetected;
  final bool containerDetected;
  final bool virtualCameraDetected;
  final bool unknownDeviceState;
  final List<String> findings;
  final List<String> hardFindings;
  final List<String> warningFindings;
  final String message;

  SystemSecurityReviewResult toSystemSecurityReviewResult() {
    return SystemSecurityReviewResult(
      ready: ready,
      platformSupported: platformSupported,
      bluetoothDetected: bluetoothDetected,
      externalAudioDetected: externalAudioDetected,
      usbRiskDetected: usbRiskDetected,
      virtualizationDetected: virtualizationDetected,
      virtualizationWarningDetected: virtualizationWarningDetected,
      containerDetected: containerDetected,
      virtualCameraDetected: virtualCameraDetected,
      unknownDeviceState: unknownDeviceState,
      findings: findings,
      hardFindings: hardFindings,
      warningFindings: warningFindings,
      message: message,
    );
  }

  factory NativeSystemSecurityReviewSnapshot.fromJson(
    Map<String, Object?> json,
  ) {
    return NativeSystemSecurityReviewSnapshot(
      ready: json['ready'] == true,
      platformSupported: json['platform_supported'] == true,
      bluetoothDetected: json['bluetooth_detected'] == true,
      externalAudioDetected: json['external_audio_detected'] == true,
      usbRiskDetected: json['usb_risk_detected'] == true,
      virtualizationDetected: json['virtualization_detected'] == true,
      virtualizationWarningDetected:
          json['virtualization_warning_detected'] == true,
      containerDetected: json['container_detected'] == true,
      virtualCameraDetected: json['virtual_camera_detected'] == true,
      unknownDeviceState: json['unknown_device_state'] == true,
      findings: _stringList(json['findings']),
      hardFindings: _stringList(json['hard_findings']),
      warningFindings: _stringList(json['warning_findings']),
      message: json['message']?.toString() ?? 'System review completed.',
    );
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const <String>[];
    return value.map((item) => item.toString()).toList(growable: false);
  }
}

abstract class NativeSystemSecurityReviewBridge {
  Future<NativeSystemSecurityReviewSnapshot?> check();
}

class DisabledNativeSystemSecurityReviewBridge
    implements NativeSystemSecurityReviewBridge {
  const DisabledNativeSystemSecurityReviewBridge();

  @override
  Future<NativeSystemSecurityReviewSnapshot?> check() async => null;
}

class GeneratedNativeSystemSecurityReviewBridge
    implements NativeSystemSecurityReviewBridge {
  const GeneratedNativeSystemSecurityReviewBridge();

  static Future<bool>? _nativeReady;

  @override
  Future<NativeSystemSecurityReviewSnapshot?> check() async {
    if (!await _ensureNativeReady()) return null;
    try {
      final result = await native_system_security.runSystemSecurityReview(
        platformName: 'auto',
      );
      return NativeSystemSecurityReviewSnapshot(
        ready: result.ready,
        platformSupported: result.platformSupported,
        bluetoothDetected: result.bluetoothDetected,
        externalAudioDetected: result.externalAudioDetected,
        usbRiskDetected: result.usbRiskDetected,
        virtualizationDetected: result.virtualizationDetected,
        virtualizationWarningDetected: result.virtualizationWarningDetected,
        containerDetected: result.containerDetected,
        virtualCameraDetected: result.virtualCameraDetected,
        unknownDeviceState: result.unknownDeviceState,
        findings: result.findings,
        hardFindings: result.hardFindings,
        warningFindings: result.warningFindings,
        message: result.message,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _ensureNativeReady() {
    return _nativeReady ??= () async {
      try {
        await BrainCoreApi.init();
        return true;
      } catch (_) {
        return false;
      }
    }();
  }
}
