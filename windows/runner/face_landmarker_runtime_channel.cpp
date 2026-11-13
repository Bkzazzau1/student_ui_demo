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

#ifdef _WIN32
#include <windows.h>
#endif

#ifdef KSLAS_ENABLE_ONNXRUNTIME
#include <onnxruntime_cxx_api.h>
#if __has_include(<onnxruntime/core/providers/dml/dml_provider_factory.h>)
#include <onnxruntime/core/providers/dml/dml_provider_factory.h>
#define KSLAS_LANDMARKER_HAS_DIRECTML 1
#elif __has_include(<dml_provider_factory.h>)
#include <dml_provider_factory.h>
#define KSLAS_LANDMARKER_HAS_DIRECTML 1
#else
#define KSLAS_LANDMARKER_HAS_DIRECTML 0
#endif
#endif

namespace {
flutter::EncodableValue Key(const char* value) { return std::string(value); }

#ifdef KSLAS_ENABLE_ONNXRUNTIME
// This model runs on every single processed frame (every guided enrollment
// capture and every liveness-burst frame), so it is the single highest-
// leverage place to enable GPU acceleration: unlike the optimized-vision
// (YOLO) engine, this session was left on ONNX Runtime's default CPU
// execution provider. Falls back to CPU silently if DirectML isn't
// available on this machine/build, exactly like the YOLO engine does.
std::string ExecutableDirectory() {
  std::wstring buffer(MAX_PATH, L'\0');
  DWORD length = GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
  while (length == buffer.size()) {
    buffer.resize(buffer.size() * 2);
    length = GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
  }
  if (length == 0) return "";
  buffer.resize(length);
  const int utf8_length = WideCharToMultiByte(CP_UTF8, 0, buffer.c_str(), -1, nullptr, 0, nullptr, nullptr);
  if (utf8_length <= 0) return "";
  std::string utf8(utf8_length - 1, '\0');
  WideCharToMultiByte(CP_UTF8, 0, buffer.c_str(), -1, utf8.data(), utf8_length, nullptr, nullptr);
  const auto index = utf8.find_last_of("\\/");
  return index == std::string::npos ? "" : utf8.substr(0, index);
}

bool DirectMlAvailable() {
  const std::string directml_path = ExecutableDirectory() + "\\DirectML.dll";
  return std::ifstream(directml_path, std::ios::binary).good();
}

void TryEnableDirectMl(Ort::SessionOptions* options) {
#if KSLAS_LANDMARKER_HAS_DIRECTML
  if (!DirectMlAvailable()) return;
  try {
    options->DisableMemPattern();
    options->SetExecutionMode(ExecutionMode::ORT_SEQUENTIAL);
    Ort::ThrowOnError(OrtSessionOptionsAppendExecutionProvider_DML(*options, 0));
  } catch (...) {
    // Leave the session on its default CPU execution provider.
  }
#else
  (void)options;
#endif
}
#endif

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

#ifdef KSLAS_ENABLE_ONNXRUNTIME
// A face found by the YuNet detector, in source-image pixels. Keypoints are
// right eye, left eye, nose tip, right and left mouth corner (subject's
// sides), i.e. image-left eye first.
struct DetectedFace {
  double x = 0, y = 0, w = 0, h = 0, score = 0;
  std::array<double, 10> keypoints{};
  double Area() const { return w * h; }
};

double IntersectionOverUnion(const DetectedFace& a, const DetectedFace& b) {
  const double x0 = std::max(a.x, b.x);
  const double y0 = std::max(a.y, b.y);
  const double x1 = std::min(a.x + a.w, b.x + b.w);
  const double y1 = std::min(a.y + a.h, b.y + b.h);
  const double inter = std::max(0.0, x1 - x0) * std::max(0.0, y1 - y0);
  const double uni = a.Area() + b.Area() - inter;
  return uni > 0 ? inter / uni : 0.0;
}

// Square crop that may extend past the image; outside pixels are black.
std::vector<uint8_t> SquareCrop(const std::vector<uint8_t>& rgb, int width, int height,
                                int left, int top, int side) {
  std::vector<uint8_t> crop(static_cast<size_t>(side) * side * 3, 0);
  const int x0 = std::max(0, left), y0 = std::max(0, top);
  const int x1 = std::min(width, left + side), y1 = std::min(height, top + side);
  if (x1 <= x0 || y1 <= y0) return crop;
  const size_t row_bytes = static_cast<size_t>(x1 - x0) * 3;
  for (int y = y0; y < y1; ++y) {
    const size_t source = (static_cast<size_t>(y) * width + x0) * 3;
    const size_t target = (static_cast<size_t>(y - top) * side + (x0 - left)) * 3;
    std::copy_n(rgb.begin() + source, row_bytes, crop.begin() + target);
  }
  return crop;
}
#endif

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
      TryEnableDirectMl(options_.get());
      std::wstring wide(path.begin(), path.end());
      session_ = std::make_unique<Ort::Session>(*env_, wide.c_str(), *options_);
      Ort::AllocatorWithDefaultOptions allocator;
      input_name_ = session_->GetInputNameAllocated(0, allocator).get();
      output_names_.clear();
      for (size_t i = 0; i < session_->GetOutputCount(); ++i) {
        output_names_.push_back(session_->GetOutputNameAllocated(i, allocator).get());
      }
      ready_ = true;
      InitializeDetector(ReadString(args, "detector_model_path"));
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
      // The face mesh model expects a face-centred crop (MediaPipe feeds it
      // a detector ROI). Find the face first, then run the mesh on a square
      // 1.5x the face box. Without the detector the whole frame is used.
      const uint8_t* source_rgb = bytes->data();
      int source_w = width, source_h = height, left = 0, top = 0;
      std::vector<uint8_t> crop;
      DetectedFace face;
      size_t face_count = 0;
      if (detector_ready_) {
        const auto faces = DetectFaces(*bytes, width, height);
        face_count = faces.size();
        if (faces.empty()) return flutter::EncodableValue();
        face = *std::max_element(faces.begin(), faces.end(),
                                 [](const auto& a, const auto& b) { return a.Area() < b.Area(); });
        const int crop_side = std::max(16, static_cast<int>(std::lround(std::max(face.w, face.h) * 1.5)));
        left = static_cast<int>(std::lround(face.x + face.w / 2.0 - crop_side / 2.0));
        top = static_cast<int>(std::lround(face.y + face.h / 2.0 - crop_side / 2.0));
        crop = SquareCrop(*bytes, width, height, left, top, crop_side);
        source_rgb = crop.data();
        source_w = crop_side;
        source_h = crop_side;
      }

      constexpr int side = 256;
      std::vector<float> input(side * side * 3);
      for (int y = 0; y < side; ++y) {
        const int source_y = std::min(source_h - 1, y * source_h / side);
        for (int x = 0; x < side; ++x) {
          const int source_x = std::min(source_w - 1, x * source_w / side);
          const size_t source = static_cast<size_t>((source_y * source_w + source_x) * 3);
          const size_t target = static_cast<size_t>((y * side + x) * 3);
          input[target] = source_rgb[source] / 255.0f;
          input[target + 1] = source_rgb[source + 1] / 255.0f;
          input[target + 2] = source_rgb[source + 2] / 255.0f;
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
      // The mesh has two scalar outputs: a rank-4 face-presence logit
      // (strongly positive for a face) and a rank-2 value near 1 for "no
      // face". Only the logit is a confidence, after a sigmoid; clamping
      // either raw value to 0..1 inverted the signal.
      double face_logit = 0.0;
      bool has_face_logit = false;
      for (auto& output : outputs) {
        if (!output.IsTensor()) continue;
        const auto info = output.GetTensorTypeAndShapeInfo();
        const auto count = info.GetElementCount();
        const auto* data = output.GetTensorData<float>();
        if ((count == 478 * 3 || count == 468 * 3) && !landmarks) {
          landmarks = data;
          landmark_count = count / 3;
        } else if (count == 1 && info.GetDimensionsCount() == 4 && !has_face_logit) {
          face_logit = static_cast<double>(data[0]);
          has_face_logit = true;
        }
      }
      const double face_confidence =
          has_face_logit ? 1.0 / (1.0 + std::exp(-face_logit)) : 0.86;
      if (!landmarks || landmark_count < 468) return flutter::EncodableValue();
      // Model coordinates (0..256 of the crop) back to the full frame,
      // normalized by the frame size as before.
      const double sx = static_cast<double>(source_w) / side / width;
      const double sy = static_cast<double>(source_h) / side / height;
      flutter::EncodableList points;
      points.reserve(landmark_count);
      for (size_t i = 0; i < landmark_count; ++i) {
        flutter::EncodableMap point;
        point[Key("index")] = static_cast<int32_t>(i);
        point[Key("x")] = landmarks[i * 3] * sx + static_cast<double>(left) / width;
        point[Key("y")] = landmarks[i * 3 + 1] * sy + static_cast<double>(top) / height;
        point[Key("z")] = landmarks[i * 3 + 2] * sx;
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
      result[Key("confidence")] = face_confidence;
      result[Key("landmarks")] = points;
      result[Key("gaze_vector")] = gaze;
      result[Key("detector")] = std::string(detector_ready_ ? "yunet" : "none");
      if (detector_ready_) {
        result[Key("face_count")] = static_cast<int32_t>(face_count);
        result[Key("detector_score")] = face.score;
        result[Key("face_box")] = flutter::EncodableMap{
            {Key("x"), face.x / width},
            {Key("y"), face.y / height},
            {Key("w"), face.w / width},
            {Key("h"), face.h / height},
        };
      }
      return flutter::EncodableValue(result);
    } catch (...) { return flutter::EncodableValue(); }
#else
    return flutter::EncodableValue();
#endif
  }

 private:
#ifdef KSLAS_ENABLE_ONNXRUNTIME
  // Optional: without the detector the engine keeps the old full-frame path.
  void InitializeDetector(const std::string& path) {
    detector_ready_ = false;
    if (path.empty() || !std::ifstream(path, std::ios::binary).good()) return;
    try {
      std::wstring wide(path.begin(), path.end());
      detector_ = std::make_unique<Ort::Session>(*env_, wide.c_str(), *options_);
      Ort::AllocatorWithDefaultOptions allocator;
      detector_input_name_ = detector_->GetInputNameAllocated(0, allocator).get();
      detector_output_names_.clear();
      for (size_t i = 0; i < detector_->GetOutputCount(); ++i) {
        detector_output_names_.push_back(detector_->GetOutputNameAllocated(i, allocator).get());
      }
      detector_ready_ = true;
    } catch (...) {
      detector_.reset();
      detector_ready_ = false;
    }
  }

  // YuNet 2023mar: fixed 640x640 BGR input (0..255). The frame is shrunk
  // (never enlarged) with nearest sampling and padded black at the bottom
  // and right; outputs are decoded as OpenCV's FaceDetectorYN does. Mirrors
  // ai_runtime/face_identity_reference.py.
  std::vector<DetectedFace> DetectFaces(const std::vector<uint8_t>& rgb, int width, int height) {
    constexpr int side = 640;
    constexpr double score_threshold = 0.6;
    constexpr double nms_iou = 0.3;
    const double scale = std::min(1.0, static_cast<double>(side) / std::max(width, height));
    const int out_w = std::max(1, static_cast<int>(width * scale));
    const int out_h = std::max(1, static_cast<int>(height * scale));
    std::vector<float> input(static_cast<size_t>(3) * side * side, 0.0f);
    const size_t plane = static_cast<size_t>(side) * side;
    for (int y = 0; y < out_h; ++y) {
      const int source_y = std::min(height - 1, y * height / out_h);
      for (int x = 0; x < out_w; ++x) {
        const int source_x = std::min(width - 1, x * width / out_w);
        const size_t source = (static_cast<size_t>(source_y) * width + source_x) * 3;
        const size_t target = static_cast<size_t>(y) * side + x;
        input[target] = rgb[source + 2];
        input[plane + target] = rgb[source + 1];
        input[2 * plane + target] = rgb[source];
      }
    }
    std::array<int64_t, 4> shape{1, 3, side, side};
    auto memory = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
    auto tensor = Ort::Value::CreateTensor<float>(memory, input.data(), input.size(), shape.data(), shape.size());
    const char* input_names[] = {detector_input_name_.c_str()};
    std::vector<const char*> output_ptrs;
    for (const auto& name : detector_output_names_) output_ptrs.push_back(name.c_str());
    auto outputs = detector_->Run(Ort::RunOptions{nullptr}, input_names, &tensor, 1,
                                  output_ptrs.data(), output_ptrs.size());
    auto output = [&](const std::string& name) -> const float* {
      for (size_t i = 0; i < detector_output_names_.size(); ++i) {
        if (detector_output_names_[i] == name && outputs[i].IsTensor()) {
          return outputs[i].GetTensorData<float>();
        }
      }
      return nullptr;
    };
    std::vector<DetectedFace> candidates;
    for (const int stride : {8, 16, 32}) {
      const std::string suffix = "_" + std::to_string(stride);
      const float* cls = output("cls" + suffix);
      const float* obj = output("obj" + suffix);
      const float* bbox = output("bbox" + suffix);
      const float* kps = output("kps" + suffix);
      if (!cls || !obj || !bbox || !kps) continue;
      const int cols = side / stride;
      const int anchors = cols * cols;
      for (int index = 0; index < anchors; ++index) {
        const double score = std::sqrt(std::clamp(static_cast<double>(cls[index]), 0.0, 1.0) *
                                       std::clamp(static_cast<double>(obj[index]), 0.0, 1.0));
        if (score < score_threshold) continue;
        const int row = index / cols;
        const int col = index % cols;
        const double cx = (col + bbox[index * 4]) * stride;
        const double cy = (row + bbox[index * 4 + 1]) * stride;
        const double w = std::exp(static_cast<double>(bbox[index * 4 + 2])) * stride;
        const double h = std::exp(static_cast<double>(bbox[index * 4 + 3])) * stride;
        DetectedFace face;
        face.x = (cx - w / 2) / scale;
        face.y = (cy - h / 2) / scale;
        face.w = w / scale;
        face.h = h / scale;
        face.score = score;
        for (int n = 0; n < 5; ++n) {
          face.keypoints[n * 2] = (kps[index * 10 + n * 2] + col) * stride / scale;
          face.keypoints[n * 2 + 1] = (kps[index * 10 + n * 2 + 1] + row) * stride / scale;
        }
        candidates.push_back(face);
      }
    }
    std::stable_sort(candidates.begin(), candidates.end(),
                     [](const auto& a, const auto& b) { return a.score > b.score; });
    std::vector<DetectedFace> kept;
    for (const auto& candidate : candidates) {
      bool overlaps = false;
      for (const auto& other : kept) {
        if (IntersectionOverUnion(candidate, other) > nms_iou) {
          overlaps = true;
          break;
        }
      }
      if (!overlaps) kept.push_back(candidate);
    }
    return kept;
  }
#endif

  bool ready_ = false;
  bool detector_ready_ = false;
#ifdef KSLAS_ENABLE_ONNXRUNTIME
  std::unique_ptr<Ort::Env> env_;
  std::unique_ptr<Ort::SessionOptions> options_;
  std::unique_ptr<Ort::Session> session_;
  std::string input_name_;
  std::vector<std::string> output_names_;
  std::unique_ptr<Ort::Session> detector_;
  std::string detector_input_name_;
  std::vector<std::string> detector_output_names_;
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
