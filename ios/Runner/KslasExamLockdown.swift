import AVFoundation
import Flutter
import UIKit

/// iPad exam controls on the `kslas.exam_lockdown` channel.
///
/// iPadOS does not let an ordinary app lock itself to the screen. The exam
/// therefore uses **Guided Access**: the student turns it on (triple-click the
/// top or Home button) and the app checks that it is on before the questions
/// open. On school-managed (supervised) iPads with Autonomous Single App Mode
/// allowed for K-SLAS, `enter` turns it on by itself.
///
/// Readiness keys match Android's (`supported`, `screen_capture_blocked`,
/// `clipboard_cleared`, `output_muted`, `microphone_muted`,
/// `lock_task_active`). iOS cannot block screenshots outright, so
/// `screen_capture_blocked` means "not being recorded or mirrored now"; with
/// Guided Access on, the hardware buttons used for screenshots are disabled by
/// default. Changes during the exam are sent to Dart as `onLockdownEvent`:
/// `guided_access_changed`, `screen_capture_changed`, `screenshot_taken`.
final class KslasExamLockdown {
  private let channel: FlutterMethodChannel
  private var observers: [NSObjectProtocol] = []

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "kslas.exam_lockdown", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    observe()
  }

  deinit {
    observers.forEach { NotificationCenter.default.removeObserver($0) }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "prepare":
      result(prepare())
    case "status":
      result(readiness())
    case "enter":
      enter(result)
    case "exit":
      exit(result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func prepare() -> [String: Any] {
    UIPasteboard.general.items = []
    return readiness()
  }

  private func enter(_ result: @escaping FlutterResult) {
    _ = prepare()
    if UIAccessibility.isGuidedAccessEnabled {
      result(readiness())
      return
    }
    // Only succeeds on supervised iPads where the school's MDM allows
    // Autonomous Single App Mode for this app. Elsewhere it fails at once and
    // the student turns Guided Access on themselves.
    UIAccessibility.requestGuidedAccessSession(enabled: true) { [weak self] _ in
      DispatchQueue.main.async {
        result(self?.readiness() ?? [:])
      }
    }
  }

  private func exit(_ result: @escaping FlutterResult) {
    // A self-started Guided Access session can only be ended by the student
    // (triple-click and passcode). Only an MDM-started session is ended here.
    if UIAccessibility.isGuidedAccessEnabled {
      UIAccessibility.requestGuidedAccessSession(enabled: false) { _ in
        DispatchQueue.main.async { result(nil) }
      }
    } else {
      result(nil)
    }
  }

  private func readiness() -> [String: Any] {
    let captured = Self.screenIsCaptured()
    return [
      "supported": true,
      "platform": "ios",
      "screen_capture_blocked": !captured,
      "screen_capture_active": captured,
      "clipboard_cleared": !(UIPasteboard.general.hasStrings || UIPasteboard.general.hasImages
        || UIPasteboard.general.hasURLs),
      "output_muted": AVAudioSession.sharedInstance().outputVolume <= 0.0,
      "microphone_muted": Self.microphoneDenied(),
      "lock_task_active": UIAccessibility.isGuidedAccessEnabled,
      "guided_access_required": true,
      "lock_mode": "guided_access",
    ]
  }

  private func observe() {
    let center = NotificationCenter.default
    observers.append(
      center.addObserver(
        forName: UIAccessibility.guidedAccessStatusDidChangeNotification, object: nil, queue: .main
      ) { [weak self] _ in
        self?.send("guided_access_changed", ["enabled": UIAccessibility.isGuidedAccessEnabled])
      })
    observers.append(
      center.addObserver(forName: UIScreen.capturedDidChangeNotification, object: nil, queue: .main) {
        [weak self] _ in
        self?.send("screen_capture_changed", ["captured": Self.screenIsCaptured()])
      })
    observers.append(
      center.addObserver(
        forName: UIApplication.userDidTakeScreenshotNotification, object: nil, queue: .main
      ) { [weak self] _ in
        self?.send("screenshot_taken", [:])
      })
  }

  private func send(_ type: String, _ details: [String: Any]) {
    var event = details
    event["type"] = type
    event["timestamp_ms"] = Int(Date().timeIntervalSince1970 * 1000)
    event["readiness"] = readiness()
    channel.invokeMethod("onLockdownEvent", arguments: event)
  }

  /// True while the screen is recorded, mirrored (AirPlay or cable) or shared.
  private static func screenIsCaptured() -> Bool {
    let screens = UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.screen }
    if screens.isEmpty { return UIScreen.main.isCaptured }
    return screens.contains { $0.isCaptured }
  }

  private static func microphoneDenied() -> Bool {
    if #available(iOS 17.0, *) {
      return AVAudioApplication.shared.recordPermission == .denied
    }
    return AVAudioSession.sharedInstance().recordPermission == .denied
  }
}
