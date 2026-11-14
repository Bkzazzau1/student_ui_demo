import Flutter
import Foundation
import onnxruntime_objc

/// iOS counterpart to `AndroidOptimizedVisionRuntimeEngine` (MainActivity.kt)
/// on the `kslas.optimized_vision_runtime` channel.
///
/// Runs the manifest's YOLOv8 model with ONNX Runtime on the CPU, using the
/// same contract as Android and Windows: letterboxed (or stretched) RGB in
/// [0, 1] with grey (114) padding, nearest-neighbour sampling, strict
/// `[1, 4 + C, N]` / `[1, N, 4 + C]` decoding, class-aware NMS, boxes in
/// normalized source-frame coordinates. A model whose output does not match
/// the manifest produces no detections.
final class KslasOptimizedVisionRuntime {
  private static let maxDetections = 50

  private let worker = KslasWorker(label: "kslas.optimized_vision")
  private var env: ORTEnv?
  private var session: ORTSession?
  private var inputName = ""
  private var outputNames: [String] = []
  private var inputWidth = 416
  private var inputHeight = 416
  private var inputChannels = 3
  private var modelPath = ""
  private var backend = "not_available"
  private var precision = "not_available"
  private var outputLayout = "channels_first_yolov8"
  private var inputPreprocessing = "letterbox_rgb01"
  private var confidenceThreshold = 0.45
  private var iouThreshold = 0.45
  private var classNames: [String] = KslasOptimizedVisionRuntime.cocoClassNames
  private var lastInferenceMs = 0.0
  private var lastError = "iOS ONNX Runtime has not been initialized."

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = KslasArgs.dict(call.arguments)
    switch call.method {
    case "initialize":
      worker.run(result) { self.initialize(args) }
    case "runFrame":
      worker.run(result) { self.runFrame(args) }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func initialize(_ policy: [String: Any]) -> Bool {
    backend = KslasArgs.string(policy, "backend", "onnxRuntimeCpu")
    precision = KslasArgs.string(policy, "precision", "int8")
    outputLayout = KslasArgs.string(policy, "output_layout", "channels_first_yolov8")
    inputPreprocessing = KslasArgs.string(policy, "input_preprocessing", "letterbox_rgb01")
    confidenceThreshold = KslasArgs.double(policy, "confidence_threshold", 0.45)
    iouThreshold = KslasArgs.double(policy, "iou_threshold", 0.45)
    classNames = KslasArgs.stringList(policy, "class_names", Self.cocoClassNames)
    inputWidth = max(1, KslasArgs.int(policy, "input_width", KslasArgs.int(policy, "max_input_width", 416)))
    inputHeight = max(1, KslasArgs.int(policy, "input_height", KslasArgs.int(policy, "max_input_height", 416)))
    inputChannels = max(1, min(4, KslasArgs.int(policy, "input_channels", 3)))
    // The validated manifest defines the model contract; refuse unknown
    // preprocessing or layouts instead of guessing them.
    guard inputPreprocessing == "letterbox_rgb01" || inputPreprocessing == "stretch_rgb01" else {
      session = nil
      lastError = "Unsupported input_preprocessing in the model manifest: \(inputPreprocessing)"
      return false
    }
    guard outputLayout == "channels_first_yolov8" || outputLayout == "rows_yolov8" else {
      session = nil
      lastError = "Unsupported output_layout in the model manifest: \(outputLayout)"
      return false
    }
    do {
      let assetPath = resolveAssetPath(policy)
      guard let filePath = Self.bundlePath(forFlutterAsset: assetPath) else {
        throw KslasError("YOLO model asset was not found: \(assetPath)")
      }
      let environment = try ORTEnv(loggingLevel: .warning)
      let options = try ORTSessionOptions()
      try options.setGraphOptimizationLevel(.all)
      try options.setIntraOpNumThreads(2)
      let created = try ORTSession(env: environment, modelPath: filePath, sessionOptions: options)
      guard let input = try created.inputNames().first else {
        throw KslasError("YOLO model has no input")
      }
      let outputs = try created.outputNames()
      guard !outputs.isEmpty else { throw KslasError("YOLO model has no outputs") }
      env = environment
      session = created
      inputName = input
      outputNames = outputs
      modelPath = assetPath
      lastError = ""
      return true
    } catch {
      session = nil
      lastError = error.localizedDescription
      return false
    }
  }

  private func runFrame(_ request: [String: Any]) -> [String: Any] {
    guard let session else { return notAvailable(lastError) }
    let started = Date()
    do {
      guard var frame = KslasRgbImage.fromCameraPlanes(request) else {
        throw KslasError("Camera frame is invalid")
      }
      // iOS stream frames are already upright (rotation 0); honour the
      // request like Android so boxes are always in the upright frame.
      let rotation = KslasArgs.int(request, "rotation_degrees", 0)
      if rotation % 360 != 0 {
        frame = frame.rotatedClockwise(rotation)
      }
      let geometry = InputGeometry(
        preprocessing: inputPreprocessing, sourceWidth: frame.width, sourceHeight: frame.height,
        inputWidth: inputWidth, inputHeight: inputHeight)
      let tensor = try ORTValue(
        tensorData: buildInput(frame, geometry), elementType: .float,
        shape: [1, NSNumber(value: inputChannels), NSNumber(value: inputHeight), NSNumber(value: inputWidth)])
      let outputs = try session.run(
        withInputs: [inputName: tensor], outputNames: Set(outputNames), runOptions: nil)
      lastInferenceMs = Date().timeIntervalSince(started) * 1000.0
      var response = try availableResponse(outputs, request: request, geometry: geometry)
      response["inference_ms"] = lastInferenceMs
      return response
    } catch {
      lastError = error.localizedDescription
      return notAvailable(lastError)
    }
  }

  private func resolveAssetPath(_ policy: [String: Any]) -> String {
    let explicit = KslasArgs.string(policy, "model_path")
    if !explicit.isEmpty { return explicit }
    let onnx = KslasArgs.string(policy, "onnx_path")
    if !onnx.isEmpty { return onnx }
    let file: String
    switch precision {
    case "fp16": file = "yolo_exam_review.fp16.onnx"
    case "fp32Fallback": file = "yolo_exam_review.fp32.onnx"
    default: file = "yolo_exam_review.int8.onnx"
    }
    return "assets/models/yolo_exam_review/\(file)"
  }

  /// A Flutter asset key (for example `assets/models/...`) inside the app
  /// bundle, or an absolute path that already exists.
  static func bundlePath(forFlutterAsset asset: String) -> String? {
    if asset.hasPrefix("/"), FileManager.default.fileExists(atPath: asset) { return asset }
    let key = FlutterDartProject.lookupKey(forAsset: asset)
    if let path = Bundle.main.path(forResource: key, ofType: nil) { return path }
    let candidate = Bundle.main.bundleURL.appendingPathComponent(key).path
    return FileManager.default.fileExists(atPath: candidate) ? candidate : nil
  }

  struct InputGeometry {
    let inputWidth: Int
    let inputHeight: Int
    let sourceWidth: Int
    let sourceHeight: Int
    let contentWidth: Int
    let contentHeight: Int
    let scaleX: Double
    let scaleY: Double
    let padX: Int
    let padY: Int

    /// Same placement as Ultralytics LetterBox, the Android engine and
    /// `ai_runtime` `letterbox_nn_rgb01`.
    init(preprocessing: String, sourceWidth: Int, sourceHeight: Int, inputWidth: Int, inputHeight: Int) {
      var contentWidth = inputWidth
      var contentHeight = inputHeight
      if preprocessing == "letterbox_rgb01" {
        let ratio = min(Double(inputWidth) / Double(sourceWidth), Double(inputHeight) / Double(sourceHeight))
        contentWidth = min(max(Int(floor(Double(sourceWidth) * ratio + 0.5)), 1), inputWidth)
        contentHeight = min(max(Int(floor(Double(sourceHeight) * ratio + 0.5)), 1), inputHeight)
      }
      self.inputWidth = inputWidth
      self.inputHeight = inputHeight
      self.sourceWidth = sourceWidth
      self.sourceHeight = sourceHeight
      self.contentWidth = contentWidth
      self.contentHeight = contentHeight
      scaleX = Double(contentWidth) / Double(sourceWidth)
      scaleY = Double(contentHeight) / Double(sourceHeight)
      padX = (inputWidth - contentWidth) / 2
      padY = (inputHeight - contentHeight) / 2
    }
  }

  private func buildInput(_ frame: KslasRgbImage, _ geometry: InputGeometry) -> NSMutableData {
    let width = geometry.inputWidth
    let height = geometry.inputHeight
    let channels = inputChannels
    let plane = width * height
    var tensor = [Float](repeating: 114.0 / 255.0, count: plane * channels)
    frame.pixels.withUnsafeBufferPointer { src in
      for y in 0..<height {
        let contentY = y - geometry.padY
        if contentY < 0 || contentY >= geometry.contentHeight { continue }
        let srcY = min(frame.height - 1, contentY * frame.height / geometry.contentHeight)
        for x in 0..<width {
          let contentX = x - geometry.padX
          if contentX < 0 || contentX >= geometry.contentWidth { continue }
          let srcX = min(frame.width - 1, contentX * frame.width / geometry.contentWidth)
          let s = (srcY * frame.width + srcX) * 3
          for channel in 0..<channels {
            let value = src[s + min(channel, 2)]
            tensor[channel * plane + y * width + x] = Float(value) / 255.0
          }
        }
      }
    }
    return tensor.withUnsafeBufferPointer { buffer in
      NSMutableData(bytes: buffer.baseAddress!, length: buffer.count * MemoryLayout<Float>.stride)
    }
  }

  private struct Detection {
    let x1: Double
    let y1: Double
    let x2: Double
    let y2: Double
    let confidence: Double
    let classId: Int
    let label: String

    var map: [String: Any] {
      [
        "label": label,
        "class_id": classId,
        "confidence": min(1.0, max(0.0, confidence)),
        "box": ["x1": x1, "y1": y1, "x2": x2, "y2": y2],
      ]
    }

    func iou(_ other: Detection) -> Double {
      let overlapX = max(0.0, min(x2, other.x2) - max(x1, other.x1))
      let overlapY = max(0.0, min(y2, other.y2) - max(y1, other.y1))
      let overlap = overlapX * overlapY
      let area = (x2 - x1) * (y2 - y1) + (other.x2 - other.x1) * (other.y2 - other.y1) - overlap
      return area > 0.0 ? overlap / area : 0.0
    }
  }

  private struct FloatTensor {
    let shape: [Int]
    let values: [Float]
  }

  private func floatTensor(_ value: ORTValue) -> FloatTensor? {
    guard let info = try? value.tensorTypeAndShapeInfo(), info.elementType == .float,
      let data = try? value.tensorData() as Data
    else { return nil }
    let values: [Float] = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    return FloatTensor(shape: info.shape.map { $0.intValue }, values: values)
  }

  private func availableResponse(
    _ outputs: [String: ORTValue], request: [String: Any], geometry: InputGeometry
  ) throws -> [String: Any] {
    var summaries: [[String: Any]] = []
    var detections: [Detection]?
    var raw: FloatTensor?
    for (index, name) in outputNames.enumerated() {
      guard let value = outputs[name] else { continue }
      let tensor = floatTensor(value)
      summaries.append([
        "name": "output_\(index)",
        "shape": tensor?.shape ?? [],
        "element_count": tensor?.values.count ?? 0,
        "sample": tensor.map { Array($0.values.prefix(16)).map { Double($0) } } ?? [],
      ])
      if detections == nil, let tensor {
        detections = decodeYoloV8(tensor, geometry)
        if detections != nil { raw = tensor }
      }
    }
    // Fail closed: a model whose output does not match its manifest must not
    // produce detections.
    let decoded = detections ?? []
    let personCount = decoded.filter { $0.label.contains("person") && $0.confidence >= 0.40 }.count
    var outputMap: [String: Any] = [
      "objects": decoded.map { $0.map },
      "person_count": personCount,
      "multiple_people_likely": personCount >= 2,
      "screen_glow": decoded.contains { Self.isPhoneLike($0.label) },
      "mirror_reflection": decoded.contains { Self.isMirrorLike($0.label) },
      "offscreen_interaction": decoded.contains { Self.isOffscreenLike($0.label) },
      "runtime": backend,
      "precision": precision,
      "inference_ms": lastInferenceMs,
      "model_path": modelPath,
      "model_family": "yolo",
      "raw_outputs": summaries,
      "class_names": classNames,
      "num_classes": classNames.count,
      "layout": outputLayout,
      "output_layout": outputLayout,
      "confidence_threshold": confidenceThreshold,
      "iou_threshold": iouThreshold,
      "image_width": geometry.sourceWidth,
      "image_height": geometry.sourceHeight,
      "input_width": geometry.inputWidth,
      "input_height": geometry.inputHeight,
      "input_preprocessing": inputPreprocessing,
      "letterbox_scale_x": geometry.scaleX,
      "letterbox_scale_y": geometry.scaleY,
      "letterbox_pad_x": Double(geometry.padX),
      "letterbox_pad_y": Double(geometry.padY),
      "input_format": KslasArgs.string(request, "format"),
      "input_conversion": inputPreprocessing,
      "requires_rust_decode": true,
    ]
    if let raw {
      outputMap["yolo_output"] = raw.values.map { Double($0) }
      outputMap["num_predictions"] = predictionCount(raw)
    } else {
      outputMap["message"] =
        "YOLO output does not match the model manifest (expected [1, \(4 + classNames.count), N] for \(outputLayout))."
    }
    return [
      "available": detections != nil && raw != nil,
      "backend": backend,
      "precision": precision,
      "inference_ms": lastInferenceMs,
      "outputs": outputMap,
    ]
  }

  private func predictionCount(_ tensor: FloatTensor) -> Int {
    let attributes = 4 + classNames.count
    guard tensor.shape.count == 3 else { return tensor.values.count / max(1, attributes) }
    return outputLayout == "channels_first_yolov8" ? tensor.shape[2] : tensor.shape[1]
  }

  /// Strict YOLOv8 decode against the manifest contract.
  private func decodeYoloV8(_ tensor: FloatTensor, _ geometry: InputGeometry) -> [Detection]? {
    let numClasses = classNames.count
    let attributes = 4 + numClasses
    let shape = tensor.shape
    guard numClasses > 0, shape.count == 3, shape[0] == 1,
      geometry.contentWidth > 0, geometry.contentHeight > 0
    else { return nil }
    let channelsFirst = outputLayout == "channels_first_yolov8"
    let predictions = channelsFirst ? shape[2] : shape[1]
    let reportedAttributes = channelsFirst ? shape[1] : shape[2]
    guard reportedAttributes == attributes, predictions > 0,
      tensor.values.count == attributes * predictions
    else { return nil }
    let data = tensor.values
    func at(_ prediction: Int, _ attribute: Int) -> Double {
      Double(data[channelsFirst ? attribute * predictions + prediction : prediction * attributes + attribute])
    }

    var candidates: [Detection] = []
    for prediction in 0..<predictions {
      var bestClass = -1
      var bestScore = 0.0
      for classIndex in 0..<numClasses {
        let score = at(prediction, 4 + classIndex)
        if score > bestScore {
          bestScore = score
          bestClass = classIndex
        }
      }
      if bestClass < 0 || bestScore < confidenceThreshold { continue }
      let cx = at(prediction, 0)
      let cy = at(prediction, 1)
      let w = abs(at(prediction, 2))
      let h = abs(at(prediction, 3))
      let cw = Double(geometry.contentWidth)
      let ch = Double(geometry.contentHeight)
      let px = Double(geometry.padX)
      let py = Double(geometry.padY)
      let x1 = Self.unit((cx - w / 2.0 - px) / cw)
      let y1 = Self.unit((cy - h / 2.0 - py) / ch)
      let x2 = Self.unit((cx + w / 2.0 - px) / cw)
      let y2 = Self.unit((cy + h / 2.0 - py) / ch)
      if !(x2 > x1) || !(y2 > y1) { continue }
      candidates.append(
        Detection(
          x1: x1, y1: y1, x2: x2, y2: y2, confidence: Self.unit(bestScore),
          classId: bestClass, label: classNames[bestClass]))
    }
    var kept: [Detection] = []
    for candidate in candidates.sorted(by: { $0.confidence > $1.confidence }) {
      if kept.contains(where: { $0.classId == candidate.classId && $0.iou(candidate) > iouThreshold }) {
        continue
      }
      kept.append(candidate)
      if kept.count >= Self.maxDetections { break }
    }
    return kept
  }

  private func notAvailable(_ message: String) -> [String: Any] {
    [
      "available": false,
      "backend": backend,
      "precision": precision,
      "inference_ms": lastInferenceMs,
      "outputs": [
        "message": message,
        "model_path": modelPath,
        "model_family": "yolo",
        "requires_real_model": true,
        "class_names": classNames,
        "num_classes": classNames.count,
        "layout": outputLayout,
      ] as [String: Any],
    ]
  }

  private static func unit(_ value: Double) -> Double { min(1.0, max(0.0, value)) }

  // Exact labels, not substrings: "handbag" is not a hand and "wine glass"
  // is not a mirror.
  private static let phoneLikeLabels: Set<String> = [
    "cell phone", "phone", "mobile phone", "smartphone", "remote",
  ]
  private static let mirrorLikeLabels: Set<String> = ["mirror", "reflection"]
  private static let offscreenLikeLabels: Set<String> = [
    "hand", "offscreen interaction", "offscreen_interaction",
  ]

  private static func normalized(_ label: String) -> String {
    label.trimmingCharacters(in: .whitespaces).lowercased()
  }

  private static func isPhoneLike(_ label: String) -> Bool {
    phoneLikeLabels.contains(normalized(label))
  }

  private static func isMirrorLike(_ label: String) -> Bool {
    mirrorLikeLabels.contains(normalized(label))
  }

  private static func isOffscreenLike(_ label: String) -> Bool {
    offscreenLikeLabels.contains(normalized(label))
  }

  static let cocoClassNames: [String] = [
    "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck", "boat",
    "traffic light", "fire hydrant", "stop sign", "parking meter", "bench", "bird", "cat", "dog",
    "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe", "backpack", "umbrella",
    "handbag", "tie", "suitcase", "frisbee", "skis", "snowboard", "sports ball", "kite",
    "baseball bat", "baseball glove", "skateboard", "surfboard", "tennis racket", "bottle",
    "wine glass", "cup", "fork", "knife", "spoon", "bowl", "banana", "apple", "sandwich",
    "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair", "couch",
    "potted plant", "bed", "dining table", "toilet", "tv", "laptop", "mouse", "remote",
    "keyboard", "cell phone", "microwave", "oven", "toaster", "sink", "refrigerator", "book",
    "clock", "vase", "scissors", "teddy bear", "hair drier", "toothbrush",
  ]
}
