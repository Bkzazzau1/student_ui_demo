#include "face_landmarker_runtime_channel.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <fstream>
#include <memory>
#include <string>
#include <vector>

#ifdef KSLAS_ENABLE_ONNXRUNTIME
#include <onnxruntime_cxx_api.h>
#endif

namespace {
flutter::EncodableValue Key(const char* value) { return std::string(value); }
const flutter::EncodableValue* Find(const flutter::EncodableMap* map, const char* key) {
  if (!map) return nullptr;
  const auto found = map->find(Key(key));
  return found == map->end() ? nullptr : &found->second;
}
int ReadInt(const flutter::EncodableMap* map, const char* key) {
  const auto* value = Find(map, key);
  if (const auto* v = value ? std::get_if<int32_t>(value) : nullptr) return *v;
  if (const auto* v = value ? std::get_if<int64_t>(value) : nullptr) return static_cast<int>(*v);
  return 0;
}
std::string ReadString(const flutter::EncodableMap* map, const char* key) {
  const auto* value = Find(map, key);
  if (const auto* v = value ? std::get_if<std::string>(value) : nullptr) return *v;
  return {};
}

class FaceLandmarkerEngine {
 public:
  bool Initialize(const flutter::EncodableMap* args) {
#ifdef KSLAS_ENABLE_ONNXRUNTIME
    try {
      const auto path = ReadString(args, "model_path");
      if (path.empty() || !std::ifstream(path, std::ios::binary).good()) return false;
      env_ = std::make_unique<Ort::Env>(ORT_LOGGING_LEVEL_WARNING, "kslas-face-landmarks");
      options_ = std::make_unique<Ort::SessionOptions>();
      options_->SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
      std::wstring wide(path.begin(), path.end());
      session_ = std::make_unique<Ort::Session>(*env_, wide.c_str(), *options_);
      Ort::AllocatorWithDefaultOptions allocator;
      input_name_ = session_->GetInputNameAllocated(0, allocator).get();
      output_names_.clear();
      for (size_t i = 0; i < session_->GetOutputCount(); ++i) {
        output_names_.push_back(session_->GetOutputNameAllocated(i, allocator).get());
      }
      ready_ = true;
      return true;
    } catch (...) { ready_ = false; return false; }
#else
    return false;
#endif
  }

  flutter::EncodableValue Analyze(const flutter::EncodableMap* args) {
#ifdef KSLAS_ENABLE_ONNXRUNTIME
    if (!ready_ || !session_) return flutter::EncodableValue();
    const int width = ReadInt(args, "width");
    const int height = ReadInt(args, "height");
    const auto* bytes_value = Find(args, "rgb_bytes");
    const auto* bytes = bytes_value ? std::get_if<std::vector<uint8_t>>(bytes_value) : nullptr;
    if (!bytes || width <= 0 || height <= 0 || bytes->size() < static_cast<size_t>(width * height * 3)) {
      return flutter::EncodableValue();
    }
    try {
      constexpr int side = 256;
      std::vector<float> input(side * side * 3);
      for (int y = 0; y < side; ++y) {
        const int source_y = std::min(height - 1, y * height / side);
        for (int x = 0; x < side; ++x) {
          const int source_x = std::min(width - 1, x * width / side);
          const size_t source = static_cast<size_t>((source_y * width + source_x) * 3);
          const size_t target = static_cast<size_t>((y * side + x) * 3);
          input[target] = (*bytes)[source] / 255.0f;
          input[target + 1] = (*bytes)[source + 1] / 255.0f;
          input[target + 2] = (*bytes)[source + 2] / 255.0f;
        }
      }
      std::array<int64_t, 4> shape{1, side, side, 3};
      auto memory = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
      auto tensor = Ort::Value::CreateTensor<float>(memory, input.data(), input.size(), shape.data(), shape.size());
      const char* input_names[] = {input_name_.c_str()};
      std::vector<const char*> output_ptrs;
      for (const auto& name : output_names_) output_ptrs.push_back(name.c_str());
      auto outputs = session_->Run(Ort::RunOptions{nullptr}, input_names, &tensor, 1,
                                   output_ptrs.data(), output_ptrs.size());
      const float* landmarks = nullptr;
      size_t landmark_count = 0;
      double face_confidence = 0.0;
      for (auto& output : outputs) {
        if (!output.IsTensor()) continue;
        const auto count = output.GetTensorTypeAndShapeInfo().GetElementCount();
        const auto* data = output.GetTensorData<float>();
        if ((count == 478 * 3 || count == 468 * 3) && !landmarks) {
          landmarks = data;
          landmark_count = count / 3;
        } else if (count == 1) {
          face_confidence = std::clamp(static_cast<double>(data[0]), 0.0, 1.0);
        }
      }
      if (!landmarks || landmark_count < 468) return flutter::EncodableValue();
      flutter::EncodableList points;
      points.reserve(landmark_count);
      for (size_t i = 0; i < landmark_count; ++i) {
        flutter::EncodableMap point;
        point[Key("index")] = static_cast<int32_t>(i);
        point[Key("x")] = static_cast<double>(landmarks[i * 3] / side);
        point[Key("y")] = static_cast<double>(landmarks[i * 3 + 1] / side);
        point[Key("z")] = static_cast<double>(landmarks[i * 3 + 2] / side);
        points.emplace_back(point);
      }
      auto axis = [&](int iris, int a, int b, int offset) {
        if (landmark_count <= static_cast<size_t>(iris)) return 0.0;
        const double p = landmarks[iris * 3 + offset];
        const double av = landmarks[a * 3 + offset];
        const double bv = landmarks[b * 3 + offset];
        const double span = std::abs(bv - av);
        return span < 1e-4 ? 0.0 : std::clamp(((p - std::min(av, bv)) / span - 0.5) * 2.0, -1.0, 1.0);
      };
      const double gaze_x = landmark_count >= 478 ? (axis(468, 33, 133, 0) + axis(473, 362, 263, 0)) / 2.0 : 0.0;
      const double gaze_y = landmark_count >= 478 ? (axis(468, 159, 145, 1) + axis(473, 386, 374, 1)) / 2.0 : 0.0;
      flutter::EncodableMap gaze{{Key("x"), gaze_x}, {Key("y"), gaze_y}, {Key("z"), 1.0}};
      flutter::EncodableMap result;
      result[Key("label")] = std::string("windows_onnx_face_landmarker");
      result[Key("confidence")] = face_confidence > 0.0 ? face_confidence : 0.86;
      result[Key("landmarks")] = points;
      result[Key("gaze_vector")] = gaze;
      return flutter::EncodableValue(result);
    } catch (...) { return flutter::EncodableValue(); }
#else
    return flutter::EncodableValue();
#endif
  }

 private:
  bool ready_ = false;
#ifdef KSLAS_ENABLE_ONNXRUNTIME
  std::unique_ptr<Ort::Env> env_;
  std::unique_ptr<Ort::SessionOptions> options_;
  std::unique_ptr<Ort::Session> session_;
  std::string input_name_;
  std::vector<std::string> output_names_;
#endif
};
}  // namespace

void RegisterFaceLandmarkerRuntimeChannel(flutter::BinaryMessenger* messenger) {
  static FaceLandmarkerEngine engine;
  static auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "kslas.face_landmarker", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([](const auto& call, auto result) {
    const auto* args = call.arguments() ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
    if (call.method_name() == "initialize") result->Success(engine.Initialize(args));
    else if (call.method_name() == "analyseRgb") result->Success(engine.Analyze(args));
    else result->NotImplemented();
  });
}
