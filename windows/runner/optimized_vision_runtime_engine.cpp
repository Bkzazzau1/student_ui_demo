#include "optimized_vision_runtime_engine.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <stdexcept>
#include <string>
#include <vector>

#ifdef _WIN32
#include <windows.h>
#endif

#ifdef KSLAS_ENABLE_ONNXRUNTIME
#include <onnxruntime_cxx_api.h>
#if __has_include(<onnxruntime/core/providers/dml/dml_provider_factory.h>)
#include <onnxruntime/core/providers/dml/dml_provider_factory.h>
#define KSLAS_HAS_DIRECTML_PROVIDER 1
#elif __has_include(<dml_provider_factory.h>)
#include <dml_provider_factory.h>
#define KSLAS_HAS_DIRECTML_PROVIDER 1
#else
#define KSLAS_HAS_DIRECTML_PROVIDER 0
#endif
#endif

namespace {

struct Detection {
  double x1 = 0.0;
  double y1 = 0.0;
  double x2 = 0.0;
  double y2 = 0.0;
  double confidence = 0.0;
  int64_t class_id = -1;
  std::string label;
};

struct ImagePlane {
  const std::vector<uint8_t>* bytes = nullptr;
  int row_stride = 0;
  int pixel_stride = 1;
};

struct RgbPixel {
  int r = 0;
  int g = 0;
  int b = 0;
};

flutter::EncodableValue StringValue(const char* value) {
  return flutter::EncodableValue(std::string(value));
}

flutter::EncodableValue StringValue(const std::string& value) {
  return flutter::EncodableValue(value);
}

flutter::EncodableValue DoubleValue(double value) {
  return flutter::EncodableValue(value);
}

const flutter::EncodableValue* FindValue(const flutter::EncodableMap* map,
                                         const char* key) {
  if (map == nullptr) return nullptr;
  const auto it = map->find(StringValue(key));
  if (it == map->end()) return nullptr;
  return &it->second;
}

std::string ReadString(const flutter::EncodableMap* map,
                       const char* key,
                       const std::string& fallback = "") {
  const auto* value = FindValue(map, key);
  if (value == nullptr) return fallback;
  if (const auto* text = std::get_if<std::string>(value)) return *text;
  return fallback;
}

int ReadInt(const flutter::EncodableMap* map, const char* key, int fallback) {
  const auto* value = FindValue(map, key);
  if (value == nullptr) return fallback;
  if (const auto* int32_value = std::get_if<int32_t>(value)) return *int32_value;
  if (const auto* int64_value = std::get_if<int64_t>(value)) {
    return static_cast<int>(*int64_value);
  }
  if (const auto* double_value = std::get_if<double>(value)) {
    return static_cast<int>(*double_value);
  }
  return fallback;
}

double ReadDouble(const flutter::EncodableMap* map, const char* key, double fallback) {
  const auto* value = FindValue(map, key);
  if (value == nullptr) return fallback;
  if (const auto* double_value = std::get_if<double>(value)) return *double_value;
  if (const auto* int32_value = std::get_if<int32_t>(value)) {
    return static_cast<double>(*int32_value);
  }
  if (const auto* int64_value = std::get_if<int64_t>(value)) {
    return static_cast<double>(*int64_value);
  }
  return fallback;
}

std::vector<std::string> ReadStringList(const flutter::EncodableMap* map, const char* key) {
  std::vector<std::string> items;
  const auto* value = FindValue(map, key);
  const auto* list = value == nullptr ? nullptr : std::get_if<flutter::EncodableList>(value);
  if (list == nullptr) return items;
  for (const auto& item : *list) {
    if (const auto* text = std::get_if<std::string>(&item)) items.push_back(*text);
  }
  return items;
}

bool FileExists(const std::string& path) {
  std::ifstream file(path, std::ios::binary);
  return file.good();
}

std::string JoinPath(const std::string& left, const std::string& right) {
  if (left.empty()) return right;
  const char tail = left[left.size() - 1];
  if (tail == '\\' || tail == '/') return left + right;
  return left + "\\" + right;
}

std::string DirectoryName(const std::string& path) {
  const auto index = path.find_last_of("\\/");
  if (index == std::string::npos) return "";
  return path.substr(0, index);
}

std::string ExecutableDirectory() {
#ifdef _WIN32
  std::wstring buffer(MAX_PATH, L'\0');
  DWORD length = GetModuleFileNameW(nullptr, buffer.data(),
                                    static_cast<DWORD>(buffer.size()));
  while (length == buffer.size()) {
    buffer.resize(buffer.size() * 2);
    length = GetModuleFileNameW(nullptr, buffer.data(),
                                static_cast<DWORD>(buffer.size()));
  }
  if (length == 0) return "";
  buffer.resize(length);
  const int utf8_length = WideCharToMultiByte(
      CP_UTF8, 0, buffer.c_str(), -1, nullptr, 0, nullptr, nullptr);
  if (utf8_length <= 0) return "";
  std::string utf8(utf8_length - 1, '\0');
  WideCharToMultiByte(CP_UTF8, 0, buffer.c_str(), -1, utf8.data(),
                      utf8_length, nullptr, nullptr);
  return DirectoryName(utf8);
#else
  return "";
#endif
}

std::wstring Utf8ToWide(const std::string& value) {
#ifdef _WIN32
  const int length = MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, nullptr, 0);
  if (length <= 0) return std::wstring();
  std::wstring wide(length - 1, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, wide.data(), length);
  return wide;
#else
  return std::wstring(value.begin(), value.end());
#endif
}

double Clamp01(double value) {
  return std::max(0.0, std::min(1.0, value));
}

int Clamp255(int value) {
  return std::max(0, std::min(255, value));
}

bool IsSupportedPreprocessing(const std::string& value) {
  return value == "letterbox_rgb01" || value == "stretch_rgb01";
}

bool IsSupportedLayout(const std::string& value) {
  return value == "channels_first_yolov8" || value == "rows_yolov8";
}

uint8_t SafeByte(const ImagePlane& plane, int index) {
  if (plane.bytes == nullptr || index < 0 || index >= static_cast<int>(plane.bytes->size())) {
    return 0;
  }
  return (*plane.bytes)[static_cast<size_t>(index)];
}

RgbPixel YuvToRgb(int y_value, int u_value, int v_value) {
  const int c = std::max(0, y_value - 16);
  const int d = u_value - 128;
  const int e = v_value - 128;
  return RgbPixel{
      Clamp255((298 * c + 409 * e + 128) >> 8),
      Clamp255((298 * c - 100 * d - 208 * e + 128) >> 8),
      Clamp255((298 * c + 516 * d + 128) >> 8),
  };
}

RgbPixel ReadPackedRgb(const ImagePlane& plane,
                       int x,
                       int y,
                       int fallback_pixel_width,
                       int red_offset,
                       int green_offset,
                       int blue_offset) {
  const int pixel_width = std::max(plane.pixel_stride, fallback_pixel_width);
  const int index = y * plane.row_stride + x * pixel_width;
  return RgbPixel{
      static_cast<int>(SafeByte(plane, index + red_offset)),
      static_cast<int>(SafeByte(plane, index + green_offset)),
      static_cast<int>(SafeByte(plane, index + blue_offset)),
  };
}

RgbPixel ReadYuv420(const std::vector<ImagePlane>& planes, int x, int y) {
  const ImagePlane& y_plane = planes[0];
  const ImagePlane& u_plane = planes[1];
  const ImagePlane& v_plane = planes[2];
  const int y_value = SafeByte(y_plane, y * y_plane.row_stride + x * y_plane.pixel_stride);
  const int chroma_x = x / 2;
  const int chroma_y = y / 2;
  const int u_value = SafeByte(u_plane, chroma_y * u_plane.row_stride + chroma_x * u_plane.pixel_stride);
  const int v_value = SafeByte(v_plane, chroma_y * v_plane.row_stride + chroma_x * v_plane.pixel_stride);
  return YuvToRgb(y_value, u_value, v_value);
}

RgbPixel ReadRgbPixel(const std::vector<ImagePlane>& planes,
                      const std::string& format,
                      int x,
                      int y) {
  if (planes.empty()) return RgbPixel{};
  if (format == "rgb888" || format == "rgb") {
    return ReadPackedRgb(planes.front(), x, y, 3, 0, 1, 2);
  }
  if (format == "bgra8888" || format == "bgra") {
    return ReadPackedRgb(planes.front(), x, y, 4, 2, 1, 0);
  }
  if (format.find("yuv") != std::string::npos && planes.size() >= 3) {
    return ReadYuv420(planes, x, y);
  }
  const ImagePlane& y_plane = planes.front();
  const int value = SafeByte(y_plane, y * y_plane.row_stride + x * y_plane.pixel_stride);
  return RgbPixel{value, value, value};
}

flutter::EncodableMap BoundingBoxValue(const Detection& detection) {
  flutter::EncodableMap box;
  box[StringValue("x1")] = DoubleValue(Clamp01(detection.x1));
  box[StringValue("y1")] = DoubleValue(Clamp01(detection.y1));
  box[StringValue("x2")] = DoubleValue(Clamp01(detection.x2));
  box[StringValue("y2")] = DoubleValue(Clamp01(detection.y2));
  return box;
}

flutter::EncodableValue DetectionValue(const Detection& detection) {
  flutter::EncodableMap object;
  object[StringValue("label")] = StringValue(detection.label);
  object[StringValue("class_id")] = flutter::EncodableValue(detection.class_id);
  object[StringValue("confidence")] = DoubleValue(detection.confidence);
  object[StringValue("box")] = flutter::EncodableValue(BoundingBoxValue(detection));
  return flutter::EncodableValue(object);
}

bool IsPersonLike(const std::string& label) {
  return label.find("person") != std::string::npos ||
         label.find("human") != std::string::npos ||
         label.find("face") != std::string::npos;
}

bool IsPhoneLike(const std::string& label) {
  return label.find("phone") != std::string::npos ||
         label.find("mobile") != std::string::npos ||
         label.find("remote") != std::string::npos ||
         label.find("screen") != std::string::npos ||
         label.find("laptop") != std::string::npos ||
         label.find("tv_monitor") != std::string::npos;
}

bool IsMirrorLike(const std::string& label) {
  return label.find("mirror") != std::string::npos ||
         label.find("glass") != std::string::npos ||
         label.find("reflection") != std::string::npos;
}

bool IsOffscreenLike(const std::string& label) {
  return label.find("offscreen") != std::string::npos ||
         label.find("interaction") != std::string::npos ||
         label.find("hand") != std::string::npos;
}

double Iou(const Detection& a, const Detection& b) {
  const double overlap_x = std::max(0.0, std::min(a.x2, b.x2) - std::max(a.x1, b.x1));
  const double overlap_y = std::max(0.0, std::min(a.y2, b.y2) - std::max(a.y1, b.y1));
  const double overlap = overlap_x * overlap_y;
  const double area = (a.x2 - a.x1) * (a.y2 - a.y1) + (b.x2 - b.x1) * (b.y2 - b.y1) - overlap;
  return area > 0.0 ? overlap / area : 0.0;
}

constexpr size_t kMaxDetections = 50;

// Strict YOLOv8 decode against the manifest contract: shape [1, 4 + C, N]
// (channels_first_yolov8) or [1, N, 4 + C] (rows_yolov8), class probabilities,
// pixel cx/cy/w/h in model-input space. Boxes are mapped back to normalized
// source-frame coordinates, clipped, then class-aware greedy NMS is applied.
// Returns false when the tensor does not match the manifest; nothing is
// guessed from a tensor of another shape.
bool DecodeYoloV8(const float* data,
                  const std::vector<int64_t>& shape,
                  size_t element_count,
                  const std::string& layout,
                  const std::vector<std::string>& class_names,
                  double confidence_threshold,
                  double iou_threshold,
                  const VisionInputGeometry& geometry,
                  std::vector<Detection>* detections,
                  int64_t* num_predictions) {
  const int64_t num_classes = static_cast<int64_t>(class_names.size());
  const int64_t attributes = 4 + num_classes;
  if (data == nullptr || detections == nullptr || num_predictions == nullptr ||
      num_classes <= 0 || shape.size() != 3 || shape[0] != 1 ||
      geometry.content_width <= 0 || geometry.content_height <= 0) {
    return false;
  }
  const bool channels_first = layout == "channels_first_yolov8";
  if (!channels_first && layout != "rows_yolov8") return false;
  const int64_t predictions = channels_first ? shape[2] : shape[1];
  const int64_t reported_attributes = channels_first ? shape[1] : shape[2];
  if (reported_attributes != attributes || predictions <= 0 ||
      static_cast<size_t>(attributes * predictions) != element_count) {
    return false;
  }
  const auto at = [&](int64_t prediction, int64_t attribute) {
    return static_cast<double>(channels_first ? data[attribute * predictions + prediction]
                                              : data[prediction * attributes + attribute]);
  };

  std::vector<Detection> candidates;
  for (int64_t prediction = 0; prediction < predictions; ++prediction) {
    int64_t best_class = -1;
    double best_score = 0.0;
    for (int64_t class_index = 0; class_index < num_classes; ++class_index) {
      const double score = at(prediction, 4 + class_index);
      if (score > best_score) {
        best_score = score;
        best_class = class_index;
      }
    }
    if (best_class < 0 || best_score < confidence_threshold) continue;
    const double cx = at(prediction, 0);
    const double cy = at(prediction, 1);
    const double w = std::abs(at(prediction, 2));
    const double h = std::abs(at(prediction, 3));
    Detection detection;
    detection.x1 = Clamp01((cx - w / 2.0 - geometry.pad_x) / geometry.content_width);
    detection.y1 = Clamp01((cy - h / 2.0 - geometry.pad_y) / geometry.content_height);
    detection.x2 = Clamp01((cx + w / 2.0 - geometry.pad_x) / geometry.content_width);
    detection.y2 = Clamp01((cy + h / 2.0 - geometry.pad_y) / geometry.content_height);
    if (!(detection.x2 > detection.x1) || !(detection.y2 > detection.y1)) continue;
    detection.confidence = Clamp01(best_score);
    detection.class_id = best_class;
    detection.label = class_names[static_cast<size_t>(best_class)];
    candidates.push_back(detection);
  }

  std::stable_sort(candidates.begin(), candidates.end(), [](const Detection& a, const Detection& b) {
    return a.confidence > b.confidence;
  });
  std::vector<Detection> kept;
  for (const auto& candidate : candidates) {
    bool suppressed = false;
    for (const auto& existing : kept) {
      if (existing.class_id == candidate.class_id && Iou(existing, candidate) > iou_threshold) {
        suppressed = true;
        break;
      }
    }
    if (suppressed) continue;
    kept.push_back(candidate);
    if (kept.size() >= kMaxDetections) break;
  }
  *detections = std::move(kept);
  *num_predictions = predictions;
  return true;
}

}  // namespace

VisionInputGeometry OptimizedVisionRuntimeEngine::ComputeInputGeometry(
    const std::string& preprocessing,
    int source_width,
    int source_height,
    int input_width,
    int input_height) {
  VisionInputGeometry geometry;
  geometry.input_width = input_width;
  geometry.input_height = input_height;
  geometry.source_width = source_width;
  geometry.source_height = source_height;
  if (source_width <= 0 || source_height <= 0 || input_width <= 0 || input_height <= 0) {
    return geometry;
  }
  if (preprocessing == "letterbox_rgb01") {
    // Same placement as Ultralytics LetterBox(center=True): scale by the
    // limiting axis, round the content size, split padding floor-left/top.
    const double ratio = std::min(static_cast<double>(input_width) / source_width,
                                  static_cast<double>(input_height) / source_height);
    geometry.content_width = std::max(
        1, std::min(input_width, static_cast<int>(std::floor(source_width * ratio + 0.5))));
    geometry.content_height = std::max(
        1, std::min(input_height, static_cast<int>(std::floor(source_height * ratio + 0.5))));
    geometry.pad_x = (input_width - geometry.content_width) / 2;
    geometry.pad_y = (input_height - geometry.content_height) / 2;
  } else {
    geometry.content_width = input_width;
    geometry.content_height = input_height;
  }
  geometry.scale_x = static_cast<double>(geometry.content_width) / source_width;
  geometry.scale_y = static_cast<double>(geometry.content_height) / source_height;
  return geometry;
}

OptimizedVisionRuntimeEngine::OptimizedVisionRuntimeEngine() = default;
OptimizedVisionRuntimeEngine::~OptimizedVisionRuntimeEngine() = default;

bool OptimizedVisionRuntimeEngine::Initialize(const flutter::EncodableMap* policy) {
#ifdef KSLAS_ENABLE_ONNXRUNTIME
  return LoadSession(policy);
#else
  (void)policy;
  available_ = false;
  last_error_ = "ONNX Runtime is not compiled into this build. Configure ONNXRUNTIME_ROOT and enable KSLAS_ENABLE_ONNXRUNTIME.";
  return false;
#endif
}

flutter::EncodableMap OptimizedVisionRuntimeEngine::RunFrame(const flutter::EncodableMap* request) {
  auto started = std::chrono::high_resolution_clock::now();
#ifdef KSLAS_ENABLE_ONNXRUNTIME
  if (available_ && session_ != nullptr) {
    try {
      auto response = RunOnnxFrame(request);
      auto elapsed = std::chrono::high_resolution_clock::now() - started;
      last_inference_ms_ = std::chrono::duration_cast<std::chrono::microseconds>(elapsed).count() / 1000.0;
      response[StringValue("inference_ms")] = DoubleValue(last_inference_ms_);
      return response;
    } catch (const std::exception& error) {
      available_ = false;
      last_error_ = error.what();
    }
  }
#else
  (void)request;
#endif
  auto elapsed = std::chrono::high_resolution_clock::now() - started;
  last_inference_ms_ = std::chrono::duration_cast<std::chrono::microseconds>(elapsed).count() / 1000.0;
  return NotAvailablePayload(last_error_.empty() ? "ONNX Runtime engine is not available for this build." : last_error_);
}

#ifdef KSLAS_ENABLE_ONNXRUNTIME
bool OptimizedVisionRuntimeEngine::LoadSession(const flutter::EncodableMap* policy) {
  try {
    backend_ = ReadString(policy, "backend", "onnxRuntimeDirectML");
    precision_ = ReadString(policy, "precision", "int8");

    // The validated manifest defines the model contract. Refuse to run a
    // model whose preprocessing, layout or classes are unknown rather than
    // guessing them (a wrong guess yields plausible-looking false detections).
    model_family_ = ReadString(policy, "model_family", "yolo");
    output_layout_ = ReadString(policy, "output_layout", "channels_first_yolov8");
    input_preprocessing_ = ReadString(policy, "input_preprocessing", "letterbox_rgb01");
    class_names_ = ReadStringList(policy, "class_names");
    confidence_threshold_ = ReadDouble(policy, "confidence_threshold", 0.45);
    iou_threshold_ = ReadDouble(policy, "iou_threshold", 0.45);
    if (model_family_ != "yolo") {
      throw std::runtime_error("Optimized vision runtime supports model_family 'yolo' only.");
    }
    if (!IsSupportedPreprocessing(input_preprocessing_)) {
      throw std::runtime_error("Unsupported input_preprocessing in the model manifest: " +
                               input_preprocessing_);
    }
    if (!IsSupportedLayout(output_layout_)) {
      throw std::runtime_error("Unsupported output_layout in the model manifest: " + output_layout_);
    }
    if (class_names_.empty()) {
      throw std::runtime_error("The model manifest must list class_names.");
    }
    if (!(confidence_threshold_ > 0.0 && confidence_threshold_ < 1.0) ||
        !(iou_threshold_ > 0.0 && iou_threshold_ < 1.0)) {
      throw std::runtime_error("Model manifest thresholds must be between 0 and 1.");
    }

    model_path_ = ResolveModelPath(policy);
    if (model_path_.empty()) {
      throw std::runtime_error("No optimized vision ONNX model found in Flutter assets.");
    }

    env_ = std::make_unique<Ort::Env>(ORT_LOGGING_LEVEL_WARNING, "kslas_optimized_vision");
    session_options_ = std::make_unique<Ort::SessionOptions>();
    session_options_->SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
    session_options_->SetIntraOpNumThreads(1);
    session_options_->SetExecutionMode(ExecutionMode::ORT_SEQUENTIAL);
    session_options_->DisableMemPattern();

    if (backend_ == "onnxRuntimeDirectML") {
#if KSLAS_HAS_DIRECTML_PROVIDER
      const std::string directml_path = JoinPath(ExecutableDirectory(), "DirectML.dll");
      if (FileExists(directml_path)) {
        Ort::ThrowOnError(OrtSessionOptionsAppendExecutionProvider_DML(*session_options_, 0));
        session_options_->DisableMemPattern();
      } else {
        backend_ = "onnxRuntimeCpu";
      }
#else
      backend_ = "onnxRuntimeCpu";
#endif
    }

    const std::wstring wide_model_path = Utf8ToWide(model_path_);
    session_ = std::make_unique<Ort::Session>(*env_, wide_model_path.c_str(), *session_options_);

    Ort::AllocatorWithDefaultOptions allocator;
    input_names_.clear();
    output_names_.clear();
    input_name_ptrs_.clear();
    output_name_ptrs_.clear();

    const size_t input_count = session_->GetInputCount();
    const size_t output_count = session_->GetOutputCount();
    if (input_count == 0 || output_count == 0) {
      throw std::runtime_error("ONNX model has no inputs or outputs.");
    }

    for (size_t i = 0; i < input_count; ++i) {
      auto name = session_->GetInputNameAllocated(i, allocator);
      input_names_.push_back(name.get());
    }
    for (size_t i = 0; i < output_count; ++i) {
      auto name = session_->GetOutputNameAllocated(i, allocator);
      output_names_.push_back(name.get());
    }
    for (const auto& name : input_names_) input_name_ptrs_.push_back(name.c_str());
    for (const auto& name : output_names_) output_name_ptrs_.push_back(name.c_str());

    auto input_type = session_->GetInputTypeInfo(0).GetTensorTypeAndShapeInfo();
    input_shape_ = input_type.GetShape();
    if (input_shape_.size() != 4) {
      input_shape_ = {1, 3, ReadInt(policy, "max_input_height", 416), ReadInt(policy, "max_input_width", 416)};
    } else {
      const int target_height = ReadInt(policy, "max_input_height", 416);
      const int target_width = ReadInt(policy, "max_input_width", 416);
      const bool nhwc = input_shape_[3] == 3 || input_shape_[3] == 1;
      input_shape_[0] = 1;
      if (nhwc) {
        if (input_shape_[1] <= 0) input_shape_[1] = target_height;
        if (input_shape_[2] <= 0) input_shape_[2] = target_width;
        if (input_shape_[3] <= 0) input_shape_[3] = 3;
      } else {
        if (input_shape_[1] <= 0) input_shape_[1] = 3;
        if (input_shape_[2] <= 0) input_shape_[2] = target_height;
        if (input_shape_[3] <= 0) input_shape_[3] = target_width;
      }
    }

    available_ = true;
    last_error_.clear();
    return true;
  } catch (const std::exception& error) {
    available_ = false;
    session_.reset();
    session_options_.reset();
    env_.reset();
    last_error_ = error.what();
    return false;
  }
}

std::string OptimizedVisionRuntimeEngine::ResolveModelPath(const flutter::EncodableMap* policy) const {
  std::vector<std::string> candidates;
  const std::string explicit_path = ReadString(policy, "model_path");
  const std::string explicit_onnx = ReadString(policy, "onnx_path");
  if (!explicit_path.empty()) candidates.push_back(explicit_path);
  if (!explicit_onnx.empty()) candidates.push_back(explicit_onnx);

  const std::string asset_name = precision_ == "fp16" ? "object_reflection_shadow_detector.fp16.onnx" : "object_reflection_shadow_detector.int8.onnx";
  const std::string asset_path = JoinPath("assets\\models\\optimized_vision_runtime", asset_name);
  candidates.push_back(asset_path);

  const std::string exe_dir = ExecutableDirectory();
  if (!exe_dir.empty()) {
    std::vector<std::string> expanded_candidates = candidates;
    for (const auto& candidate : candidates) {
      expanded_candidates.push_back(JoinPath(exe_dir, JoinPath("data\\flutter_assets", candidate)));
      expanded_candidates.push_back(JoinPath(exe_dir, JoinPath("flutter_assets", candidate)));
      expanded_candidates.push_back(JoinPath(exe_dir, candidate));
    }
    candidates = expanded_candidates;
    candidates.push_back(JoinPath(exe_dir, JoinPath("data\\flutter_assets", asset_path)));
    candidates.push_back(JoinPath(exe_dir, JoinPath("flutter_assets", asset_path)));
    candidates.push_back(JoinPath(exe_dir, asset_path));
  }

  for (const auto& candidate : candidates) {
    if (FileExists(candidate)) return candidate;
  }
  return "";
}

std::vector<float> OptimizedVisionRuntimeEngine::BuildInputTensor(const flutter::EncodableMap* request,
                                                                   VisionInputGeometry* geometry) {
  const int source_width = ReadInt(request, "width", 0);
  const int source_height = ReadInt(request, "height", 0);
  if (source_width <= 0 || source_height <= 0) {
    throw std::runtime_error("Camera frame dimensions are invalid.");
  }

  const auto* planes_value = FindValue(request, "planes");
  const auto* planes = planes_value == nullptr ? nullptr : std::get_if<flutter::EncodableList>(planes_value);
  if (planes == nullptr || planes->empty()) {
    throw std::runtime_error("Camera frame has no image planes.");
  }

  std::vector<ImagePlane> image_planes;
  for (const auto& plane_value : *planes) {
    const auto* plane = std::get_if<flutter::EncodableMap>(&plane_value);
    if (plane == nullptr) continue;
    const auto* bytes_value = FindValue(plane, "bytes");
    const auto* bytes = bytes_value == nullptr ? nullptr : std::get_if<std::vector<uint8_t>>(bytes_value);
    if (bytes == nullptr || bytes->empty()) continue;
    image_planes.push_back(ImagePlane{
        bytes,
        std::max(1, ReadInt(plane, "bytes_per_row", source_width)),
        std::max(1, ReadInt(plane, "bytes_per_pixel", 1)),
    });
  }
  if (image_planes.empty()) {
    throw std::runtime_error("Camera image plane has no bytes.");
  }

  const std::string format = ReadString(request, "format");
  const bool nchw = input_shape_.size() == 4 && input_shape_[1] <= 4;
  const int target_height = static_cast<int>(nchw ? input_shape_[2] : input_shape_[1]);
  const int target_width = static_cast<int>(nchw ? input_shape_[3] : input_shape_[2]);
  const int channels = static_cast<int>(nchw ? input_shape_[1] : input_shape_[3]);
  const size_t total = static_cast<size_t>(target_width) * target_height * std::max(1, channels);

  // Ultralytics YOLO is trained on letterboxed RGB scaled to [0, 1] with grey
  // (114) padding. Nearest-neighbour sampling inside the content area; the
  // same algorithm is mirrored by ai_runtime prepare-tensors letterbox_nn_rgb01.
  const VisionInputGeometry placement = ComputeInputGeometry(
      input_preprocessing_, source_width, source_height, target_width, target_height);
  if (placement.content_width <= 0 || placement.content_height <= 0) {
    throw std::runtime_error("Camera frame cannot be placed in the model input.");
  }
  if (geometry != nullptr) *geometry = placement;
  constexpr float kPadValue = 114.0f / 255.0f;
  std::vector<float> tensor(total, kPadValue);

  for (int y = 0; y < target_height; ++y) {
    const int content_y = y - placement.pad_y;
    if (content_y < 0 || content_y >= placement.content_height) continue;
    const int src_y = std::min(source_height - 1, content_y * source_height / placement.content_height);
    for (int x = 0; x < target_width; ++x) {
      const int content_x = x - placement.pad_x;
      if (content_x < 0 || content_x >= placement.content_width) continue;
      const int src_x = std::min(source_width - 1, content_x * source_width / placement.content_width);
      const RgbPixel pixel = ReadRgbPixel(image_planes, format, src_x, src_y);
      for (int c = 0; c < channels; ++c) {
        const int channel_value = c == 0 ? pixel.r : (c == 1 ? pixel.g : pixel.b);
        const float value = channel_value / 255.0f;
        const size_t index = nchw
                                 ? static_cast<size_t>(c * target_height * target_width + y * target_width + x)
                                 : static_cast<size_t>((y * target_width + x) * channels + c);
        if (index < tensor.size()) tensor[index] = value;
      }
    }
  }
  return tensor;
}

flutter::EncodableMap OptimizedVisionRuntimeEngine::RunOnnxFrame(const flutter::EncodableMap* request) {
  VisionInputGeometry geometry;
  auto tensor = BuildInputTensor(request, &geometry);
  std::vector<int64_t> shape = input_shape_;
  size_t expected = 1;
  for (const auto dim : shape) expected *= static_cast<size_t>(std::max<int64_t>(1, dim));
  if (expected != tensor.size()) shape = {1, 3, 416, 416};

  Ort::MemoryInfo memory_info = Ort::MemoryInfo::CreateCpu(OrtAllocatorType::OrtArenaAllocator, OrtMemType::OrtMemTypeDefault);
  Ort::Value input_tensor = Ort::Value::CreateTensor<float>(memory_info, tensor.data(), tensor.size(), shape.data(), shape.size());

  auto outputs = session_->Run(Ort::RunOptions{nullptr}, input_name_ptrs_.data(), &input_tensor, 1, output_name_ptrs_.data(), output_name_ptrs_.size());

  flutter::EncodableList output_summaries;
  std::vector<Detection> detections;
  bool decoded = false;
  int64_t num_predictions = 0;
  std::vector<float> yolo_output;
  for (size_t i = 0; i < outputs.size(); ++i) {
    flutter::EncodableMap summary;
    summary[StringValue("name")] = StringValue(i < output_names_.size() ? output_names_[i] : "");
    if (outputs[i].IsTensor()) {
      auto info = outputs[i].GetTensorTypeAndShapeInfo();
      const auto output_shape = info.GetShape();
      flutter::EncodableList dims;
      for (const auto dim : output_shape) dims.push_back(flutter::EncodableValue(dim));
      summary[StringValue("shape")] = flutter::EncodableValue(dims);
      summary[StringValue("element_count")] = flutter::EncodableValue(static_cast<int64_t>(info.GetElementCount()));
      if (info.GetElementType() == ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT) {
        const float* data = outputs[i].GetTensorData<float>();
        if (!decoded &&
            DecodeYoloV8(data, output_shape, info.GetElementCount(), output_layout_, class_names_,
                         confidence_threshold_, iou_threshold_, geometry, &detections,
                         &num_predictions)) {
          decoded = true;
          yolo_output.assign(data, data + info.GetElementCount());
        }
        const size_t limit = std::min<size_t>(info.GetElementCount(), 16);
        flutter::EncodableList sample;
        for (size_t j = 0; j < limit; ++j) sample.push_back(DoubleValue(data[j]));
        summary[StringValue("sample")] = flutter::EncodableValue(sample);
      }
    }
    output_summaries.push_back(flutter::EncodableValue(summary));
  }

  if (!decoded) {
    // Fail closed: a model whose output does not match its manifest must not
    // produce detections, and RunFrame marks the runtime unavailable.
    throw std::runtime_error(
        "YOLO output does not match the model manifest (expected [1, " +
        std::to_string(4 + class_names_.size()) + ", N] for " + output_layout_ + ").");
  }

  flutter::EncodableList objects;
  int64_t person_count = 0;
  bool screen_glow = false;
  bool mirror_reflection = false;
  bool offscreen_interaction = false;
  for (const auto& detection : detections) {
    objects.push_back(DetectionValue(detection));
    if (IsPersonLike(detection.label) && detection.confidence >= 0.40) person_count++;
    screen_glow = screen_glow || IsPhoneLike(detection.label);
    mirror_reflection = mirror_reflection || IsMirrorLike(detection.label);
    offscreen_interaction = offscreen_interaction || IsOffscreenLike(detection.label);
  }

  flutter::EncodableMap outputs_map;
  outputs_map[StringValue("objects")] = flutter::EncodableValue(objects);
  outputs_map[StringValue("person_count")] = flutter::EncodableValue(person_count);
  outputs_map[StringValue("multiple_people_likely")] = flutter::EncodableValue(person_count >= 2);
  outputs_map[StringValue("screen_glow")] = flutter::EncodableValue(screen_glow);
  outputs_map[StringValue("mirror_reflection")] = flutter::EncodableValue(mirror_reflection);
  outputs_map[StringValue("offscreen_interaction")] = flutter::EncodableValue(offscreen_interaction);
  outputs_map[StringValue("runtime")] = StringValue(backend_);
  outputs_map[StringValue("precision")] = StringValue(precision_);
  outputs_map[StringValue("inference_ms")] = DoubleValue(last_inference_ms_);
  outputs_map[StringValue("model_path")] = StringValue(model_path_);
  outputs_map[StringValue("raw_outputs")] = flutter::EncodableValue(output_summaries);
  outputs_map[StringValue("input_format")] = StringValue(ReadString(request, "format"));
  outputs_map[StringValue("input_conversion")] = StringValue(input_preprocessing_);

  // Raw detector tensor plus the exact input geometry, so the Dart/Rust decode
  // path (E1 model events) maps boxes back to the camera frame itself.
  flutter::EncodableList class_names;
  for (const auto& name : class_names_) class_names.push_back(StringValue(name));
  outputs_map[StringValue("model_family")] = StringValue(model_family_);
  outputs_map[StringValue("requires_rust_decode")] = flutter::EncodableValue(true);
  outputs_map[StringValue("yolo_output")] = flutter::EncodableValue(yolo_output);
  outputs_map[StringValue("num_predictions")] = flutter::EncodableValue(num_predictions);
  outputs_map[StringValue("class_names")] = flutter::EncodableValue(class_names);
  outputs_map[StringValue("num_classes")] =
      flutter::EncodableValue(static_cast<int64_t>(class_names_.size()));
  outputs_map[StringValue("layout")] = StringValue(output_layout_);
  outputs_map[StringValue("output_layout")] = StringValue(output_layout_);
  outputs_map[StringValue("confidence_threshold")] = DoubleValue(confidence_threshold_);
  outputs_map[StringValue("iou_threshold")] = DoubleValue(iou_threshold_);
  outputs_map[StringValue("image_width")] = flutter::EncodableValue(geometry.source_width);
  outputs_map[StringValue("image_height")] = flutter::EncodableValue(geometry.source_height);
  outputs_map[StringValue("input_width")] = flutter::EncodableValue(geometry.input_width);
  outputs_map[StringValue("input_height")] = flutter::EncodableValue(geometry.input_height);
  outputs_map[StringValue("input_preprocessing")] = StringValue(input_preprocessing_);
  outputs_map[StringValue("letterbox_scale_x")] = DoubleValue(geometry.scale_x);
  outputs_map[StringValue("letterbox_scale_y")] = DoubleValue(geometry.scale_y);
  outputs_map[StringValue("letterbox_pad_x")] = DoubleValue(static_cast<double>(geometry.pad_x));
  outputs_map[StringValue("letterbox_pad_y")] = DoubleValue(static_cast<double>(geometry.pad_y));

  flutter::EncodableMap response;
  response[StringValue("available")] = flutter::EncodableValue(true);
  response[StringValue("backend")] = StringValue(backend_);
  response[StringValue("precision")] = StringValue(precision_);
  response[StringValue("inference_ms")] = DoubleValue(last_inference_ms_);
  response[StringValue("outputs")] = flutter::EncodableValue(outputs_map);
  return response;
}
#endif

flutter::EncodableMap OptimizedVisionRuntimeEngine::NotAvailablePayload(const char* message) const {
  return NotAvailablePayload(std::string(message));
}

flutter::EncodableMap OptimizedVisionRuntimeEngine::NotAvailablePayload(const std::string& message) const {
  flutter::EncodableMap outputs;
  outputs[StringValue("message")] = StringValue(message);
  if (!model_path_.empty()) outputs[StringValue("model_path")] = StringValue(model_path_);

  flutter::EncodableMap response;
  response[StringValue("available")] = flutter::EncodableValue(false);
  response[StringValue("backend")] = StringValue(backend_);
  response[StringValue("precision")] = StringValue(precision_);
  response[StringValue("inference_ms")] = DoubleValue(last_inference_ms_);
  response[StringValue("outputs")] = flutter::EncodableValue(outputs);
  return response;
}
