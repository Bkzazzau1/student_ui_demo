import CoreVideo
import Flutter
import Foundation

/// Reads values sent from Dart over a standard method channel.
///
/// Dart `int`/`double` arrive as `NSNumber`, `Uint8List` as
/// `FlutterStandardTypedData`, maps as dictionaries with `String` keys.
enum KslasArgs {
  static func dict(_ value: Any?) -> [String: Any] {
    if let map = value as? [String: Any] { return map }
    if let map = value as? [AnyHashable: Any] {
      var out: [String: Any] = [:]
      for (key, item) in map {
        if let key = key as? String { out[key] = item }
      }
      return out
    }
    return [:]
  }

  static func string(_ map: [String: Any], _ key: String, _ fallback: String = "") -> String {
    guard let value = map[key], !(value is NSNull) else { return fallback }
    if let text = value as? String { return text }
    return "\(value)"
  }

  static func int(_ map: [String: Any], _ key: String, _ fallback: Int) -> Int {
    switch map[key] {
    case let value as Int: return value
    case let value as NSNumber: return value.intValue
    case let value as String: return Int(value) ?? fallback
    default: return fallback
    }
  }

  static func double(_ map: [String: Any], _ key: String, _ fallback: Double) -> Double {
    switch map[key] {
    case let value as Double: return value
    case let value as NSNumber: return value.doubleValue
    case let value as String: return Double(value) ?? fallback
    default: return fallback
    }
  }

  static func bool(_ map: [String: Any], _ key: String, _ fallback: Bool) -> Bool {
    switch map[key] {
    case let value as Bool: return value
    case let value as NSNumber: return value.boolValue
    default: return fallback
    }
  }

  static func bytes(_ map: [String: Any], _ key: String) -> Data? {
    if let typed = map[key] as? FlutterStandardTypedData { return typed.data }
    if let data = map[key] as? Data { return data }
    return nil
  }

  static func stringList(_ map: [String: Any], _ key: String, _ fallback: [String]) -> [String] {
    guard let values = map[key] as? [Any] else { return fallback }
    let items = values.compactMap { item -> String? in
      let text = "\(item)".trimmingCharacters(in: .whitespaces)
      return text.isEmpty ? nil : text
    }
    return items.isEmpty ? fallback : items
  }
}

/// Runs channel work off the main thread and answers on the main thread,
/// so face and object models never block the UI.
final class KslasWorker {
  private let queue: DispatchQueue

  init(label: String) {
    queue = DispatchQueue(label: label, qos: .userInitiated)
  }

  func run(_ result: @escaping FlutterResult, _ work: @escaping () -> Any?) {
    queue.async {
      let value = work()
      DispatchQueue.main.async { result(value) }
    }
  }
}

/// A packed 8-bit RGB image (3 bytes per pixel, no row padding).
struct KslasRgbImage {
  let width: Int
  let height: Int
  var pixels: [UInt8]

  init(width: Int, height: Int, pixels: [UInt8]) {
    self.width = width
    self.height = height
    self.pixels = pixels
  }

  /// Packed RGB bytes, as sent by `NativeFaceLandmarkerRuntime.analyseRgb`.
  static func fromPackedRgb(_ data: Data, width: Int, height: Int) -> KslasRgbImage? {
    guard width > 0, height > 0, data.count >= width * height * 3 else { return nil }
    return KslasRgbImage(width: width, height: height, pixels: [UInt8](data.prefix(width * height * 3)))
  }

  /// A streamed `CameraImage` (`format`, `planes` with `bytes`,
  /// `bytes_per_row`, `bytes_per_pixel`). Supports iOS `bgra8888`, iOS
  /// bi-planar `yuv420` (NV12, video range) and three-plane YUV 4:2:0.
  static func fromCameraPlanes(_ request: [String: Any]) -> KslasRgbImage? {
    let width = KslasArgs.int(request, "width", 0)
    let height = KslasArgs.int(request, "height", 0)
    guard width > 0, height > 0, let rawPlanes = request["planes"] as? [Any], !rawPlanes.isEmpty else {
      return nil
    }
    let planes = rawPlanes.compactMap { KslasPlane(KslasArgs.dict($0), width: width) }
    guard planes.count == rawPlanes.count, let first = planes.first else { return nil }
    let format = KslasArgs.string(request, "format").lowercased()
    var pixels = [UInt8](repeating: 0, count: width * height * 3)

    if format == "rgb888" || format == "rgb" {
      // Packed RGB from OptimizedVisionRuntimeBridge.runRgbFrame (the face
      // pipeline's person check).
      let pixelStride = max(first.pixelStride, 3)
      let stride = max(first.rowStride, width * pixelStride)
      first.bytes.withUnsafeBufferPointer { src in
        for y in 0..<height {
          let row = y * stride
          for x in 0..<width {
            let s = row + x * pixelStride
            guard s + 2 < src.count else { continue }
            let d = (y * width + x) * 3
            pixels[d] = src[s]
            pixels[d + 1] = src[s + 1]
            pixels[d + 2] = src[s + 2]
          }
        }
      }
      return KslasRgbImage(width: width, height: height, pixels: pixels)
    }

    if format.contains("bgra") {
      let stride = max(first.rowStride, width * 4)
      first.bytes.withUnsafeBufferPointer { src in
        for y in 0..<height {
          let row = y * stride
          for x in 0..<width {
            let s = row + x * 4
            guard s + 2 < src.count else { continue }
            let d = (y * width + x) * 3
            pixels[d] = src[s + 2]
            pixels[d + 1] = src[s + 1]
            pixels[d + 2] = src[s]
          }
        }
      }
      return KslasRgbImage(width: width, height: height, pixels: pixels)
    }

    if planes.count == 2 {
      // camera_avfoundation's yuv420 is kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
      // full-resolution luma, then interleaved Cb/Cr at half resolution.
      let yPlane = planes[0]
      let uvPlane = planes[1]
      for y in 0..<height {
        for x in 0..<width {
          let luma = yPlane.byte(y * yPlane.rowStride + x)
          let uvIndex = (y / 2) * uvPlane.rowStride + (x / 2) * 2
          let rgb = KslasYuv.videoRange(y: luma, cb: uvPlane.byte(uvIndex), cr: uvPlane.byte(uvIndex + 1))
          let d = (y * width + x) * 3
          pixels[d] = rgb.0
          pixels[d + 1] = rgb.1
          pixels[d + 2] = rgb.2
        }
      }
      return KslasRgbImage(width: width, height: height, pixels: pixels)
    }

    if planes.count >= 3 {
      let yPlane = planes[0]
      let uPlane = planes[1]
      let vPlane = planes[2]
      for y in 0..<height {
        for x in 0..<width {
          let luma = yPlane.byte(y * yPlane.rowStride + x * yPlane.pixelStride)
          let u = uPlane.byte((y / 2) * uPlane.rowStride + (x / 2) * uPlane.pixelStride)
          let v = vPlane.byte((y / 2) * vPlane.rowStride + (x / 2) * vPlane.pixelStride)
          let rgb = KslasYuv.fullRange(y: luma, cb: u, cr: v)
          let d = (y * width + x) * 3
          pixels[d] = rgb.0
          pixels[d + 1] = rgb.1
          pixels[d + 2] = rgb.2
        }
      }
      return KslasRgbImage(width: width, height: height, pixels: pixels)
    }

    // Luma only.
    for y in 0..<height {
      for x in 0..<width {
        let value = first.byte(y * first.rowStride + x * first.pixelStride)
        let d = (y * width + x) * 3
        pixels[d] = value
        pixels[d + 1] = value
        pixels[d + 2] = value
      }
    }
    return KslasRgbImage(width: width, height: height, pixels: pixels)
  }

  /// Undoes a horizontal mirror (iOS mirrors front-camera stream frames to
  /// match its preview; still photos are not mirrored).
  func mirroredHorizontally() -> KslasRgbImage {
    var out = [UInt8](repeating: 0, count: pixels.count)
    pixels.withUnsafeBufferPointer { src in
      for y in 0..<height {
        let row = y * width
        for x in 0..<width {
          let s = (row + x) * 3
          let d = (row + (width - 1 - x)) * 3
          out[d] = src[s]
          out[d + 1] = src[s + 1]
          out[d + 2] = src[s + 2]
        }
      }
    }
    return KslasRgbImage(width: width, height: height, pixels: out)
  }

  /// Rotates clockwise by `degrees` (0, 90, 180 or 270), the same convention
  /// as `Matrix.postRotate` on Android: the frame is turned upright.
  func rotatedClockwise(_ degrees: Int) -> KslasRgbImage {
    let normalized = ((degrees % 360) + 360) % 360
    guard normalized == 90 || normalized == 180 || normalized == 270 else { return self }
    let outWidth = normalized == 180 ? width : height
    let outHeight = normalized == 180 ? height : width
    var out = [UInt8](repeating: 0, count: pixels.count)
    pixels.withUnsafeBufferPointer { src in
      for y in 0..<height {
        for x in 0..<width {
          let ox: Int
          let oy: Int
          switch normalized {
          case 90:
            ox = height - 1 - y
            oy = x
          case 180:
            ox = width - 1 - x
            oy = height - 1 - y
          default:
            ox = y
            oy = width - 1 - x
          }
          let s = (y * width + x) * 3
          let d = (oy * outWidth + ox) * 3
          out[d] = src[s]
          out[d + 1] = src[s + 1]
          out[d + 2] = src[s + 2]
        }
      }
    }
    return KslasRgbImage(width: outWidth, height: outHeight, pixels: out)
  }

  /// A 32BGRA pixel buffer, the format MediaPipe Tasks expects.
  func makeBgraPixelBuffer() -> CVPixelBuffer? {
    var created: CVPixelBuffer?
    let attributes: [CFString: Any] = [
      kCVPixelBufferIOSurfacePropertiesKey: [String: Any](),
      kCVPixelBufferCGImageCompatibilityKey: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey: true,
    ]
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
      attributes as CFDictionary, &created)
    guard status == kCVReturnSuccess, let buffer = created else { return nil }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    let dst = base.assumingMemoryBound(to: UInt8.self)
    pixels.withUnsafeBufferPointer { src in
      for y in 0..<height {
        let row = y * stride
        for x in 0..<width {
          let s = (y * width + x) * 3
          let d = row + x * 4
          dst[d] = src[s + 2]
          dst[d + 1] = src[s + 1]
          dst[d + 2] = src[s]
          dst[d + 3] = 255
        }
      }
    }
    return buffer
  }
}

struct KslasPlane {
  let bytes: [UInt8]
  let rowStride: Int
  let pixelStride: Int

  init?(_ map: [String: Any], width: Int) {
    guard let data = KslasArgs.bytes(map, "bytes") else { return nil }
    bytes = [UInt8](data)
    rowStride = max(1, KslasArgs.int(map, "bytes_per_row", width))
    pixelStride = max(1, KslasArgs.int(map, "bytes_per_pixel", 1))
  }

  func byte(_ index: Int) -> UInt8 {
    guard index >= 0, index < bytes.count else { return 0 }
    return bytes[index]
  }
}

enum KslasYuv {
  /// BT.601 full range (JFIF), matching the Android conversion.
  static func fullRange(y: UInt8, cb: UInt8, cr: UInt8) -> (UInt8, UInt8, UInt8) {
    let yy = Double(y)
    let u = Double(cb) - 128.0
    let v = Double(cr) - 128.0
    return (clamp(yy + 1.402 * v), clamp(yy - 0.344136 * u - 0.714136 * v), clamp(yy + 1.772 * u))
  }

  /// BT.601 video range (luma 16-235), used by iOS bi-planar camera frames.
  static func videoRange(y: UInt8, cb: UInt8, cr: UInt8) -> (UInt8, UInt8, UInt8) {
    let yy = 1.164383 * (Double(y) - 16.0)
    let u = Double(cb) - 128.0
    let v = Double(cr) - 128.0
    return (clamp(yy + 1.596027 * v), clamp(yy - 0.391762 * u - 0.812968 * v), clamp(yy + 2.017232 * u))
  }

  private static func clamp(_ value: Double) -> UInt8 {
    UInt8(max(0.0, min(255.0, value.rounded())))
  }
}

struct KslasError: LocalizedError {
  let message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
}
