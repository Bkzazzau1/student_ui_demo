import 'dart:async';
import 'dart:convert';
import 'dart:io';

class SystemSecurityReviewResult {
  const SystemSecurityReviewResult({
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

  bool get hasWarnings => warningFindings.isNotEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'ready': ready,
    'platform_supported': platformSupported,
    'bluetooth_detected': bluetoothDetected,
    'external_audio_detected': externalAudioDetected,
    'usb_risk_detected': usbRiskDetected,
    'virtualization_detected': virtualizationDetected,
    'virtualization_warning_detected': virtualizationWarningDetected,
    'container_detected': containerDetected,
    'virtual_camera_detected': virtualCameraDetected,
    'unknown_device_state': unknownDeviceState,
    'findings': findings,
    'hard_findings': hardFindings,
    'warning_findings': warningFindings,
    'message': message,
  };
}

class SystemSecurityReviewService {
  Future<SystemSecurityReviewResult> check() async {
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return const SystemSecurityReviewResult(
        ready: false,
        platformSupported: false,
        bluetoothDetected: false,
        externalAudioDetected: false,
        usbRiskDetected: false,
        virtualizationDetected: false,
        virtualizationWarningDetected: false,
        containerDetected: false,
        virtualCameraDetected: false,
        unknownDeviceState: true,
        findings: <String>[
          'Unsupported platform. Use Windows, macOS, or Linux desktop app.',
        ],
        hardFindings: <String>[
          'Unsupported platform. Use Windows, macOS, or Linux desktop app.',
        ],
        warningFindings: <String>[],
        message:
            'Desktop system review is required before this exam can start.',
      );
    }

    try {
      if (Platform.isWindows) return await _checkWindows();
      if (Platform.isMacOS) return await _checkMacOS();
      return await _checkLinux();
    } catch (e) {
      return SystemSecurityReviewResult(
        ready: false,
        platformSupported: true,
        bluetoothDetected: false,
        externalAudioDetected: false,
        usbRiskDetected: false,
        virtualizationDetected: false,
        virtualizationWarningDetected: false,
        containerDetected: false,
        virtualCameraDetected: false,
        unknownDeviceState: true,
        findings: <String>['System devices could not be verified: $e'],
        hardFindings: <String>['System devices could not be verified: $e'],
        warningFindings: const <String>[],
        message:
            'System review could not verify connected devices. Contact the invigilator.',
      );
    }
  }

  Future<SystemSecurityReviewResult> _checkWindows() async {
    final output = await _run('powershell', <String>[
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      r'''
$devices = Get-PnpDevice -PresentOnly | Where-Object {
  $_.Status -eq 'OK' -and (
    $_.Class -match 'Bluetooth|AudioEndpoint|Media|USB|Camera|Image' -or
    $_.FriendlyName -match 'Bluetooth|Headset|Headphone|Earbud|AirPods|Hands-Free|Microphone|Mic|Audio|Wireless|USB|Capture|Camera'
  )
} | Select-Object Class,FriendlyName,Status,InstanceId
$computer = Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer,Model,HypervisorPresent
$bios = Get-CimInstance Win32_BIOS | Select-Object Manufacturer,SerialNumber,Version
$camera = Get-PnpDevice -PresentOnly | Where-Object {
  $_.Class -match 'Camera|Image|Media' -or
  $_.FriendlyName -match 'Camera|Webcam|Virtual|OBS|ManyCam|DroidCam|Snap|XSplit|NDI|SplitCam|Camo|EpocCam|iVCam'
} | Select-Object Class,FriendlyName,InstanceId,Status
[ordered]@{
  devices = $devices
  computer = $computer
  bios = $bios
  camera = $camera
} | ConvertTo-Json -Compress -Depth 4
''',
    ]);
    return _analyseOutput(output, platformName: 'Windows');
  }

  Future<SystemSecurityReviewResult> _checkMacOS() async {
    final output = await _run('sh', <String>[
      '-c',
      'system_profiler SPBluetoothDataType SPAudioDataType SPUSBDataType SPCameraDataType 2>/dev/null',
    ]);
    return _analyseOutput(output, platformName: 'macOS');
  }

  Future<SystemSecurityReviewResult> _checkLinux() async {
    final output = await _run('sh', <String>[
      '-c',
      '''
(
  bluetoothctl devices Connected 2>/dev/null
  pactl list short sources 2>/dev/null
  arecord -l 2>/dev/null
  lsusb 2>/dev/null
  systemd-detect-virt 2>/dev/null || true
  test -f /.dockerenv && echo dockerenv_present || true
  cat /proc/1/cgroup 2>/dev/null
  cat /sys/class/dmi/id/product_name 2>/dev/null
  cat /sys/class/dmi/id/sys_vendor 2>/dev/null
  lsmod 2>/dev/null | grep -Ei "v4l2loopback|akvcam|virtual" || true
  v4l2-ctl --list-devices 2>/dev/null || true
) | tr "\n" " "
''',
    ]);
    return _analyseOutput(output, platformName: 'Linux');
  }

  Future<String> _run(String executable, List<String> arguments) async {
    final ProcessResult result;
    try {
      result = await Process.run(
        executable,
        arguments,
      ).timeout(const Duration(seconds: 7));
    } on TimeoutException {
      throw StateError('device report timed out after 7 seconds');
    }
    final stdout = result.stdout?.toString() ?? '';
    final stderr = result.stderr?.toString() ?? '';
    final combined = '$stdout\n$stderr'.trim();
    if (combined.isEmpty) {
      throw StateError('empty device report');
    }
    return combined;
  }

  SystemSecurityReviewResult _analyseOutput(
    String output, {
    required String platformName,
  }) {
    final text = _normalise(output);
    final hardFindings = <String>[];
    final warningFindings = <String>[];

    final bluetoothDetected = _containsAny(text, const <String>[
      'bluetooth',
      'hands-free',
      'handsfree',
      'airpods',
      'earbuds',
      'wireless headset',
      'wireless headphone',
      'bt audio',
    ]);

    final externalAudioDetected = _containsAny(text, const <String>[
      'headset',
      'headphone',
      'earphone',
      'earbud',
      'airpods',
      'hands-free',
      'handsfree',
      'usb audio',
      'usb microphone',
      'external microphone',
      'external mic',
      'wireless microphone',
      'wireless mic',
      'audio capture',
      'capture card',
      'webcam microphone',
      'camera microphone',
    ]);

    final usbRiskDetected = _containsAny(text, const <String>[
      'usb microphone',
      'usb audio',
      'usb headset',
      'usb headphones',
      'usb camera',
      'usb capture',
      'capture card',
      'elgato',
      'aver media',
      'avermedia',
    ]);

    final virtualizationWarningDetected = Platform.isWindows &&
        _containsAny(text, const <String>[
          'hypervisorpresent: true',
          'hypervisorpresent=true',
        ]);

    final virtualizationDetected = _containsAny(text, const <String>[
      'vmware',
      'virtualbox',
      'oracle vm',
      'qemu',
      'kvm',
      'xen',
      'parallels',
      'virtio',
      'hyper-v virtual machine',
      'microsoft corporation virtual machine',
      'virtual machine platform device',
    ]);

    final containerDetected = _containsAny(text, const <String>[
      'docker',
      'containerd',
      'kubepods',
      'podman',
      'lxc',
      'wsl',
      'moby',
      'dockerenv_present',
    ]);

    final virtualCameraDetected = _containsAny(text, const <String>[
      'obs virtual camera',
      'virtual camera',
      'virtual webcam',
      'manycam',
      'snap camera',
      'droidcam',
      'xsplit',
      'ndi webcam',
      'splitcam',
      'camo',
      'epoccam',
      'ivcam',
      'v4l2loopback',
      'akvcam',
      'webcamoid',
    ]);

    final knownSafeAudio = _containsAny(text, const <String>[
      'microphone array',
      'internal microphone',
      'built-in microphone',
      'integrated microphone',
      'realtek',
      'intel smart sound',
      'high definition audio',
      'default source',
    ]);

    final audioMentioned = _containsAny(text, const <String>[
      'microphone',
      ' mic ',
      'audio',
      'source',
      'capture',
    ]);

    final unknownDeviceState =
        audioMentioned &&
        !knownSafeAudio &&
        !externalAudioDetected &&
        !usbRiskDetected &&
        !bluetoothDetected;

    if (bluetoothDetected) {
      hardFindings.add(
        'Bluetooth or wireless device detected. Turn off Bluetooth and disconnect wireless audio before exam startup.',
      );
    }
    if (externalAudioDetected) {
      hardFindings.add(
        'External audio device detected. Use only the built-in microphone and speaker.',
      );
    }
    if (usbRiskDetected) {
      hardFindings.add(
        'USB audio, camera, or capture device risk detected. Remove external exam-risk devices.',
      );
    }
    if (virtualizationDetected) {
      hardFindings.add(
        'Real virtual machine environment detected. Use a physical desktop device for this exam.',
      );
    }
    if (containerDetected) {
      hardFindings.add(
        'Container, WSL, or sandbox environment detected. Close it before this exam.',
      );
    }
    if (virtualCameraDetected) {
      hardFindings.add(
        'Virtual camera software detected. Disable virtual camera drivers and use a physical webcam.',
      );
    }
    if (unknownDeviceState) {
      hardFindings.add(
        'Connected audio device state is unclear. Invigilator confirmation is required.',
      );
    }
    if (virtualizationWarningDetected && !virtualizationDetected) {
      warningFindings.add(
        'Windows hypervisor security feature detected. This can happen on normal Windows 11 devices using Hyper-V, WSL2, Docker Desktop, or Core Isolation. It is recorded for review but does not block by itself.',
      );
    }

    if (hardFindings.isEmpty && warningFindings.isEmpty) {
      hardFindings.add(
        '$platformName device review passed. No Bluetooth, external audio, USB, virtual camera, VM, or sandbox risk was detected.',
      );
    }

    final ready =
        !bluetoothDetected &&
        !externalAudioDetected &&
        !usbRiskDetected &&
        !virtualizationDetected &&
        !containerDetected &&
        !virtualCameraDetected &&
        !unknownDeviceState;

    final findings = <String>[
      ...hardFindings,
      ...warningFindings,
    ];

    return SystemSecurityReviewResult(
      ready: ready,
      platformSupported: true,
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
      message: ready
          ? warningFindings.isEmpty
              ? 'System review passed. Continue to the exam setup.'
              : 'System review passed with review note. Continue to the exam setup.'
          : 'System review failed. Resolve blocking issues and check again.',
    );
  }

  String _normalise(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded.toString().toLowerCase();
    } catch (_) {
      return value.toLowerCase();
    }
  }

  bool _containsAny(String value, List<String> terms) {
    return terms.any(value.contains);
  }
}
