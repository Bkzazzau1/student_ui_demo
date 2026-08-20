#include "face_embedding_runtime_channel.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <array>
#include <cmath>
#include <fstream>
#include <memory>
#include <string>
#include <vector>
#include <windows.h>
#include <wincrypt.h>

#ifdef KSLAS_ENABLE_ONNXRUNTIME
#include <onnxruntime_cxx_api.h>
#endif

namespace {
flutter::EncodableValue Key(const char* value) { return std::string(value); }

const flutter::EncodableValue* Find(const flutter::EncodableMap* map,
                                    const char* key) {
  if (!map) return nullptr;
  const auto found = map->find(Key(key));
  return found == map->end() ? nullptr : &found->second;
}

std::string ReadString(const flutter::EncodableMap* map, const char* key) {
  const auto* value = Find(map, key);
  const auto* text = value ? std::get_if<std::string>(value) : nullptr;
  return text ? *text : std::string();
}

bool StoreProtectedTemplate(const flutter::EncodableMap* args) {
  const auto path = ReadString(args, "path");
  const auto value = ReadString(args, "template_json");
  const auto entropy_text = ReadString(args, "entropy");
  if (path.empty() || value.empty() || entropy_text.empty()) return false;
  DATA_BLOB input{static_cast<DWORD>(value.size()),
                  reinterpret_cast<BYTE*>(const_cast<char*>(value.data()))};
  DATA_BLOB entropy{static_cast<DWORD>(entropy_text.size()),
                    reinterpret_cast<BYTE*>(const_cast<char*>(entropy_text.data()))};
  DATA_BLOB encrypted{};
  if (!CryptProtectData(&input, L"K-SLAS face identity template", &entropy,
                        nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN,
                        &encrypted)) {
    return false;
  }
  std::ofstream output(path, std::ios::binary | std::ios::trunc);
  const bool stored = output.good() &&
      static_cast<bool>(output.write(reinterpret_cast<const char*>(encrypted.pbData),
                                     encrypted.cbData));
  output.close();
  LocalFree(encrypted.pbData);
  return stored;
}

flutter::EncodableValue LoadProtectedTemplate(const flutter::EncodableMap* args) {
  const auto path = ReadString(args, "path");
  const auto entropy_text = ReadString(args, "entropy");
  std::ifstream input(path, std::ios::binary | std::ios::ate);
  if (!input.good() || entropy_text.empty()) return flutter::EncodableValue();
  const auto length = input.tellg();
  if (length <= 0 || length > 1024 * 1024) return flutter::EncodableValue();
  input.seekg(0);
  std::vector<BYTE> encrypted(static_cast<size_t>(length));
  if (!input.read(reinterpret_cast<char*>(encrypted.data()), length)) {
    return flutter::EncodableValue();
  }
  DATA_BLOB protected_blob{static_cast<DWORD>(encrypted.size()), encrypted.data()};
  DATA_BLOB entropy{static_cast<DWORD>(entropy_text.size()),
                    reinterpret_cast<BYTE*>(const_cast<char*>(entropy_text.data()))};
  DATA_BLOB clear{};
  if (!CryptUnprotectData(&protected_blob, nullptr, &entropy, nullptr, nullptr,
                          CRYPTPROTECT_UI_FORBIDDEN, &clear)) {
    return flutter::EncodableValue();
  }
  std::string value(reinterpret_cast<const char*>(clear.pbData), clear.cbData);
  LocalFree(clear.pbData);
  return flutter::EncodableValue(value);
}

class FaceEmbeddingEngine {
 public:
  bool Initialize(const flutter::EncodableMap* args) {
#ifdef KSLAS_ENABLE_ONNXRUNTIME
    try {
      const auto path = ReadString(args, "model_path");
      if (path.empty() || !std::ifstream(path, std::ios::binary).good()) {
        last_error_ = "SFace model file was not found";
        return false;
      }
      env_ = std::make_unique<Ort::Env>(ORT_LOGGING_LEVEL_WARNING,
                                        "kslas-face-embedding");
      options_ = std::make_unique<Ort::SessionOptions>();
      options_->SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
      std::wstring wide(path.begin(), path.end());
      session_ = std::make_unique<Ort::Session>(*env_, wide.c_str(), *options_);
      Ort::AllocatorWithDefaultOptions allocator;
      input_name_ = session_->GetInputNameAllocated(0, allocator).get();
      output_name_ = session_->GetOutputNameAllocated(0, allocator).get();
      ready_ = true;
      last_error_.clear();
      return true;
    } catch (const std::exception& error) {
      ready_ = false;
      last_error_ = error.what();
      return false;
    }
#else
    last_error_ = "ONNX Runtime is not compiled into this Windows build";
    return false;
#endif
  }

  flutter::EncodableValue Health() const {
    flutter::EncodableMap value;
    value[Key("ready")] = ready_;
    value[Key("model_id")] = std::string("kslas-sface-2021dec-v1");
    value[Key("embedding_dimension")] = int32_t{128};
    value[Key("production_enforcement")] = false;
    value[Key("error")] = last_error_;
    return value;
  }

  flutter::EncodableValue Embed(const flutter::EncodableMap* args) {
#ifdef KSLAS_ENABLE_ONNXRUNTIME
    if (!ready_ || !session_) return flutter::EncodableValue();
    const auto* raw = Find(args, "rgb_bytes");
    const auto* bytes = raw ? std::get_if<std::vector<uint8_t>>(raw) : nullptr;
    constexpr size_t side = 112;
    if (!bytes || bytes->size() != side * side * 3) {
      last_error_ = "embedAlignedRgb requires exactly 112x112 RGB bytes";
      return flutter::EncodableValue();
    }
    try {
      std::vector<float> input(3 * side * side);
      for (size_t pixel = 0; pixel < side * side; ++pixel) {
        input[pixel] = (static_cast<float>((*bytes)[pixel * 3 + 2]) - 127.5f) / 128.0f;
        input[side * side + pixel] =
            (static_cast<float>((*bytes)[pixel * 3 + 1]) - 127.5f) / 128.0f;
        input[2 * side * side + pixel] =
            (static_cast<float>((*bytes)[pixel * 3]) - 127.5f) / 128.0f;
      }
      std::array<int64_t, 4> shape{1, 3, 112, 112};
      auto memory = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
      auto tensor = Ort::Value::CreateTensor<float>(memory, input.data(), input.size(),
                                                     shape.data(), shape.size());
      const char* inputs[] = {input_name_.c_str()};
      const char* outputs[] = {output_name_.c_str()};
      auto result = session_->Run(Ort::RunOptions{nullptr}, inputs, &tensor, 1,
                                  outputs, 1);
      if (result.empty() || !result[0].IsTensor()) return flutter::EncodableValue();
      const auto count = result[0].GetTensorTypeAndShapeInfo().GetElementCount();
      if (count != 128) {
        last_error_ = "SFace returned an unexpected embedding dimension";
        return flutter::EncodableValue();
      }
      const float* data = result[0].GetTensorData<float>();
      double norm = 0.0;
      for (size_t i = 0; i < count; ++i) norm += data[i] * data[i];
      norm = std::sqrt(norm);
      if (!std::isfinite(norm) || norm < 1e-6) return flutter::EncodableValue();
      flutter::EncodableList embedding;
      embedding.reserve(count);
      for (size_t i = 0; i < count; ++i) {
        embedding.emplace_back(static_cast<double>(data[i] / norm));
      }
      flutter::EncodableMap response;
      response[Key("model_id")] = std::string("kslas-sface-2021dec-v1");
      response[Key("embedding")] = embedding;
      response[Key("normalized")] = true;
      response[Key("production_enforcement")] = false;
      return response;
    } catch (const std::exception& error) {
      last_error_ = error.what();
      return flutter::EncodableValue();
    }
#else
    return flutter::EncodableValue();
#endif
  }

 private:
  bool ready_ = false;
  std::string last_error_;
#ifdef KSLAS_ENABLE_ONNXRUNTIME
  std::unique_ptr<Ort::Env> env_;
  std::unique_ptr<Ort::SessionOptions> options_;
  std::unique_ptr<Ort::Session> session_;
  std::string input_name_;
  std::string output_name_;
#endif
};
}  // namespace

void RegisterFaceEmbeddingRuntimeChannel(flutter::BinaryMessenger* messenger) {
  static FaceEmbeddingEngine engine;
  static auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "kslas.face_embedding",
          &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([](const auto& call, auto result) {
    const auto* args = call.arguments()
                           ? std::get_if<flutter::EncodableMap>(call.arguments())
                           : nullptr;
    if (call.method_name() == "initialize") {
      result->Success(engine.Initialize(args));
    } else if (call.method_name() == "health") {
      result->Success(engine.Health());
    } else if (call.method_name() == "embedAlignedRgb") {
      result->Success(engine.Embed(args));
    } else if (call.method_name() == "storeProtectedTemplate") {
      result->Success(StoreProtectedTemplate(args));
    } else if (call.method_name() == "loadProtectedTemplate") {
      result->Success(LoadProtectedTemplate(args));
    } else {
      result->NotImplemented();
    }
  });
}
