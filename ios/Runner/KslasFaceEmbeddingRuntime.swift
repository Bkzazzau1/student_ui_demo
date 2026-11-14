import CryptoKit
import Flutter
import Foundation
import Security
import onnxruntime_objc

/// iOS counterpart to `AndroidFaceEmbeddingChannel.kt` on the
/// `kslas.face_embedding` channel.
///
/// Same wire protocol (`initialize`, `health`, `embedAlignedRgb`,
/// `storeProtectedTemplate`, `loadProtectedTemplate`) and the same SFace
/// preprocessing: 112x112 RGB, raw 0..255 values (the model normalizes
/// internally), NCHW, L2-normalized 128-D output. ONNX Runtime runs on the
/// CPU, as on Android, so templates match across devices.
///
/// Protected storage: AES-256-GCM. The key is generated on the device and kept
/// in the Keychain as "this device only, after first unlock", so it is not
/// copied to backups or other devices. The `entropy` string is the GCM
/// associated data, which binds each file to the student, purpose and path it
/// was written for. Files are also excluded from backup.
final class KslasFaceEmbeddingRuntime {
  static let modelId = "kslas-sface-2021dec-v1"
  private static let side = 112
  private static let fileMagic = Data("KSLAS-GCM1".utf8)
  private static let keyService = "kslas.identity.template-key"
  private static let keyAccount = "aes-256-gcm-v1"

  private let worker = KslasWorker(label: "kslas.face_embedding")
  private var env: ORTEnv?
  private var session: ORTSession?
  private var inputName = ""
  private var outputName = ""
  private var ready = false
  private var lastError = "Face embedding runtime has not been initialized."

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = KslasArgs.dict(call.arguments)
    switch call.method {
    case "initialize":
      worker.run(result) { self.initialize(args) }
    case "health":
      worker.run(result) { self.health() }
    case "embedAlignedRgb":
      worker.run(result) { self.embedAlignedRgb(args) }
    case "storeProtectedTemplate":
      worker.run(result) { self.storeProtected(args) }
    case "loadProtectedTemplate":
      worker.run(result) { self.loadProtected(args) }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func initialize(_ args: [String: Any]) -> Bool {
    let modelPath = KslasArgs.string(args, "model_path")
    guard !modelPath.isEmpty, FileManager.default.fileExists(atPath: modelPath) else {
      lastError = "SFace model file was not found"
      ready = false
      return false
    }
    do {
      let environment = try ORTEnv(loggingLevel: .warning)
      let options = try ORTSessionOptions()
      try options.setGraphOptimizationLevel(.all)
      try options.setIntraOpNumThreads(2)
      let created = try ORTSession(env: environment, modelPath: modelPath, sessionOptions: options)
      guard let input = try created.inputNames().first, let output = try created.outputNames().first else {
        throw KslasError("SFace model has no input or output")
      }
      env = environment
      session = created
      inputName = input
      outputName = output
      ready = true
      lastError = ""
      return true
    } catch {
      ready = false
      session = nil
      lastError = error.localizedDescription
      return false
    }
  }

  private func health() -> [String: Any] {
    [
      "ready": ready,
      "model_id": Self.modelId,
      "embedding_dimension": 128,
      "production_enforcement": false,
      "error": lastError,
    ]
  }

  private func embedAlignedRgb(_ args: [String: Any]) -> [String: Any]? {
    guard ready, let session else { return nil }
    let side = Self.side
    guard let bytes = KslasArgs.bytes(args, "rgb_bytes"), bytes.count == side * side * 3 else {
      lastError = "embedAlignedRgb requires exactly 112x112 RGB bytes"
      return nil
    }
    do {
      let plane = side * side
      var input = [Float](repeating: 0, count: 3 * plane)
      bytes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
        let rgb = raw.bindMemory(to: UInt8.self)
        for pixel in 0..<plane {
          // SFace normalizes inside the graph and expects RGB 0..255.
          input[pixel] = Float(rgb[pixel * 3])
          input[plane + pixel] = Float(rgb[pixel * 3 + 1])
          input[2 * plane + pixel] = Float(rgb[pixel * 3 + 2])
        }
      }
      let tensorData = input.withUnsafeBufferPointer { buffer in
        NSMutableData(bytes: buffer.baseAddress!, length: buffer.count * MemoryLayout<Float>.stride)
      }
      let tensor = try ORTValue(
        tensorData: tensorData, elementType: .float,
        shape: [1, 3, NSNumber(value: side), NSNumber(value: side)])
      let outputs = try session.run(
        withInputs: [inputName: tensor], outputNames: [outputName], runOptions: nil)
      guard let output = outputs[outputName] else {
        lastError = "SFace returned no output"
        return nil
      }
      let data = try output.tensorData() as Data
      let count = data.count / MemoryLayout<Float>.stride
      guard count == 128 else {
        lastError = "SFace returned an unexpected embedding dimension"
        return nil
      }
      let values: [Float] = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
      let norm = sqrt(values.reduce(0.0) { $0 + Double($1) * Double($1) })
      guard norm.isFinite, norm >= 1e-6 else { return nil }
      return [
        "model_id": Self.modelId,
        "embedding": values.map { Double($0) / norm },
        "normalized": true,
        "production_enforcement": false,
      ]
    } catch {
      lastError = error.localizedDescription
      return nil
    }
  }

  private func storeProtected(_ args: [String: Any]) -> Bool {
    let path = KslasArgs.string(args, "path")
    let value = KslasArgs.string(args, "template_json")
    let entropy = KslasArgs.string(args, "entropy")
    guard !path.isEmpty, !value.isEmpty, !entropy.isEmpty else { return false }
    do {
      let key = try Self.protectionKey()
      let sealed = try AES.GCM.seal(Data(value.utf8), using: key, authenticating: Data(entropy.utf8))
      guard let combined = sealed.combined else { throw KslasError("AES-GCM produced no output") }
      var file = Self.fileMagic
      file.append(combined)
      var url = URL(fileURLWithPath: path)
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try file.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try? url.setResourceValues(values)
      return true
    } catch {
      lastError = error.localizedDescription
      return false
    }
  }

  private func loadProtected(_ args: [String: Any]) -> String? {
    let path = KslasArgs.string(args, "path")
    let entropy = KslasArgs.string(args, "entropy")
    guard !path.isEmpty, !entropy.isEmpty, FileManager.default.fileExists(atPath: path) else {
      return nil
    }
    do {
      let file = try Data(contentsOf: URL(fileURLWithPath: path))
      guard file.count > Self.fileMagic.count, file.prefix(Self.fileMagic.count) == Self.fileMagic else {
        return nil
      }
      let box = try AES.GCM.SealedBox(combined: file.dropFirst(Self.fileMagic.count))
      let plain = try AES.GCM.open(box, using: try Self.protectionKey(), authenticating: Data(entropy.utf8))
      return String(data: plain, encoding: .utf8)
    } catch {
      // Wrong entropy, a moved file or tampering: never return partial data.
      lastError = error.localizedDescription
      return nil
    }
  }

  private static func protectionKey() throws -> SymmetricKey {
    let base: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keyService,
      kSecAttrAccount as String: keyAccount,
    ]
    var query = base
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecSuccess, let data = item as? Data, data.count == 32 {
      return SymmetricKey(data: data)
    }
    guard status == errSecItemNotFound else {
      throw KslasError("Keychain read failed (\(status))")
    }
    let key = SymmetricKey(size: .bits256)
    var add = base
    add[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let addStatus = SecItemAdd(add as CFDictionary, nil)
    if addStatus == errSecDuplicateItem {
      // Another call created it first; use that one.
      var again: CFTypeRef?
      if SecItemCopyMatching(query as CFDictionary, &again) == errSecSuccess,
        let data = again as? Data, data.count == 32
      {
        return SymmetricKey(data: data)
      }
    }
    guard addStatus == errSecSuccess else {
      throw KslasError("Keychain write failed (\(addStatus))")
    }
    return key
  }
}
