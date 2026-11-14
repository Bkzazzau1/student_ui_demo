import Flutter
import Foundation
import MediaPipeTasksVision

/// iOS counterpart to `AndroidFaceLandmarkerChannel.kt` on the
/// `kslas.face_landmarker` channel.
///
/// Uses the same MediaPipe Tasks Face Landmarker and the same
/// `face_landmarker.task` model as Android, and returns the same payload, so
/// the Dart side (liveness, alignment, gaze) treats both platforms alike.
///
/// `analyseFrame` takes a streamed camera frame. `rotation_degrees` turns it
/// upright (clockwise) and `mirror_horizontal` undoes the mirroring iOS
/// applies to front-camera stream frames, so landmarks are always reported in
/// an upright, unmirrored image, the same as still photos.
final class KslasFaceLandmarkerRuntime {
  private let worker = KslasWorker(label: "kslas.face_landmarker")
  private var landmarker: FaceLandmarker?
  private var lastError = "Face landmarker has not been initialized."

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = KslasArgs.dict(call.arguments)
    switch call.method {
    case "initialize":
      worker.run(result) { self.initialize(args) }
    case "analyseFrame":
      worker.run(result) { self.analyseFrame(args) }
    case "analyseRgb":
      worker.run(result) { self.analyseRgb(args) }
    case "status":
      worker.run(result) {
        ["ready": self.landmarker != nil, "last_error": self.lastError] as [String: Any]
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func initialize(_ args: [String: Any]) -> Bool {
    let modelPath = KslasArgs.string(args, "model_path")
    guard !modelPath.isEmpty, FileManager.default.fileExists(atPath: modelPath) else {
      lastError = "model_path is required and must exist"
      landmarker = nil
      return false
    }
    do {
      let options = FaceLandmarkerOptions()
      options.baseOptions.modelAssetPath = modelPath
      options.runningMode = .image
      options.numFaces = 1
      options.minFaceDetectionConfidence = 0.55
      options.minFacePresenceConfidence = 0.55
      options.minTrackingConfidence = 0.50
      landmarker = try FaceLandmarker(options: options)
      lastError = ""
      return true
    } catch {
      landmarker = nil
      lastError = error.localizedDescription
      return false
    }
  }

  private func analyseFrame(_ args: [String: Any]) -> [String: Any]? {
    guard var image = KslasRgbImage.fromCameraPlanes(args) else { return nil }
    if KslasArgs.bool(args, "mirror_horizontal", false) {
      image = image.mirroredHorizontally()
    }
    let rotation = KslasArgs.int(args, "rotation_degrees", 0)
    if rotation % 360 != 0 {
      image = image.rotatedClockwise(rotation)
    }
    return process(image)
  }

  /// Still-photo path used by Face ID registration and verification.
  private func analyseRgb(_ args: [String: Any]) -> [String: Any]? {
    let width = KslasArgs.int(args, "width", 0)
    let height = KslasArgs.int(args, "height", 0)
    guard let bytes = KslasArgs.bytes(args, "rgb_bytes"),
      let image = KslasRgbImage.fromPackedRgb(bytes, width: width, height: height)
    else { return nil }
    return process(image)
  }

  private func process(_ image: KslasRgbImage) -> [String: Any]? {
    guard let landmarker else { return nil }
    do {
      guard let buffer = image.makeBgraPixelBuffer() else {
        lastError = "Could not create a pixel buffer for the frame"
        return nil
      }
      let result = try landmarker.detect(image: try MPImage(pixelBuffer: buffer))
      guard let face = result.faceLandmarks.first, !face.isEmpty else { return nil }
      var landmarks: [[String: Any]] = []
      landmarks.reserveCapacity(face.count)
      for (index, point) in face.enumerated() {
        landmarks.append([
          "index": index,
          "x": Double(point.x),
          "y": Double(point.y),
          "z": Double(point.z),
        ])
      }
      return [
        "label": "mediapipe_face_landmarker",
        "confidence": 0.92,
        "looking_away": false,
        "stable_head_pose": true,
        "gaze_vector": Self.irisRelativeGaze(landmarks),
        "head_pose": ["yaw": 0.0, "pitch": 0.0, "roll": 0.0],
        "landmarks": Self.withNamedReferencePoints(landmarks),
        "face_landmarks": landmarks,
        "landmark_count": landmarks.count,
        "image_width": image.width,
        "image_height": image.height,
      ]
    } catch {
      lastError = error.localizedDescription
      return nil
    }
  }

  private static func coordinate(_ points: [[String: Any]], _ index: Int, _ axis: String) -> Double? {
    guard index >= 0, index < points.count else { return nil }
    return points[index][axis] as? Double
  }

  private static func irisRelativeGaze(_ points: [[String: Any]]) -> [String: Double] {
    func normalized(_ iris: Int, _ inner: Int, _ outer: Int, _ axis: String) -> Double? {
      guard let value = coordinate(points, iris, axis),
        let a = coordinate(points, inner, axis),
        let b = coordinate(points, outer, axis)
      else { return nil }
      let span = abs(b - a)
      if span < 0.0001 { return nil }
      return min(1.0, max(0.0, (value - min(a, b)) / span))
    }
    // MediaPipe Face Landmarker iris centres: 468 (right), 473 (left).
    let xs = [normalized(468, 33, 133, "x"), normalized(473, 362, 263, "x")].compactMap { $0 }
    let ys = [normalized(468, 159, 145, "y"), normalized(473, 386, 374, "y")].compactMap { $0 }
    let x = xs.isEmpty ? 0.5 : xs.reduce(0, +) / Double(xs.count)
    let y = ys.isEmpty ? 0.5 : ys.reduce(0, +) / Double(ys.count)
    return [
      "x": min(1.0, max(-1.0, (x - 0.5) * 2.0)),
      "y": min(1.0, max(-1.0, (y - 0.5) * 2.0)),
      "z": 1.0,
    ]
  }

  private static func withNamedReferencePoints(_ points: [[String: Any]]) -> [[String: Any]] {
    var named = points
    for (index, name) in [(33, "left_eye"), (263, "right_eye"), (1, "nose_tip"), (13, "mouth_center")] {
      guard index < points.count else { continue }
      var point = points[index]
      point["name"] = name
      named.append(point)
    }
    return named
  }
}
