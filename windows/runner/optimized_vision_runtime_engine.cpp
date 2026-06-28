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

std::string LabelForClass(int64_t class_id) {
  switch (class_id) {
    case 0:
      return "person";
    case 1:
      return "phone";
    case 2:
      return "screen_glow";
    case 3:
      return "mirror_reflection";
    case 4:
      return "offscreen_interaction";
    case 56:
      return "chair";
    case 62:
      return "tv_monitor";
    case 63:
      return "laptop";
    case 64:
      return "mouse";
    case 66:
      return "keyboard";
    case 67:
      return "cell_phone";
    default:
      return "class_" + std::to_string(class_id);
  }
}

double Clamp01(double value) {
  return std::max(0.0, std::min(1.0, value));
}

int Clamp255(int value) {
  return std::max(0, std::min(255, value));
}

double Logistic(double value) {
  if (value >= 0.0 && value <= 1.0) return value;
  return 1.0 / (1.0 + std::exp(-value));
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

void DecodeCandidate(const float* values,
                     int64_t length,
                     std::vector<Detection>* detections) {
  if (values == nullptr || detections == nullptr || length < 6) return;

  int64_t class_id = -1;
  double confidence = 0.0;
  if (length == 6) {
    confidence = Logistic(values[4]);
    class_id = static_cast<int64_t>(std::llround(values[5]));
  } else {
    const bool yolov5_layout = length == 85 || length == 10;
    const int64_t class_start = yolov5_layout ? 5 : 4;
    const double objectness = yolov5_layout ? Logistic(values[4]) : 1.0;
    for (int64_t i = class_start; i < length; ++i) {
      const double score = Logistic(values[i]) * objectness;
      if (score > confidence) {
        confidence = score;
        class_id = i - class_start;
      }
    }
  }

  if (confidence < 0.20 || class_id < 0) return;

  const double a = values[0];
  const double b = values[1];
  const double c = values[2];
  const double d = values[3];
  Detection detection;
  detection.confidence = Clamp01(confidence);
  detection.class_id = class_id;
  detection.label = LabelForClass(class_id);

  if (a >= 0.0 && b >= 0.0 && c <= 1.5 && d <= 1.5) {
    if (c > a && d > b) {
      detection.x1 = a;
      detection.y1 = b;
      detection.x2 = c;
      detection.y2 = d;
    } else {
      detection.x1 = a - c / 2.0;
      detection.y1 = b - d / 2.0;
      detection.x2 = a + c / 2.0;
      detection.y2 = b + d / 2.0;
    }
  } else {
    const double scale = std::max(1.0, std::max(std::abs(a), std::max(std::abs(b), std::max(std::abs(c), std::abs(d)))));
    detection.x1 = (a - c / 2.0) / scale;
    detection.y1 = (b - d / 2.0) / scale;
    detection.x2 = (a + c / 2.0) / scale;
    detection.y2 = (b + d / 2.0) / scale;
  }

  detections->push_back(detection);
}

std::vector<Detection> ParseDetections(const float* data,
                                       const std::vector<int64_t>& shape,
                                       size_t element_count) {
  std::vector<Detection> detections;
  if (data == nullptr || element_count < 6) return detections;

  if (shape.size() == 2 && shape[1] >= 6) {
    const int64_t rows = shape[0];
    const int64_t columns = shape[1];
    for (int64_t row = 0; row < rows; ++row) {
      DecodeCandidate(data + row * columns, columns, &detections);
    }
  } else if (shape.size() == 3) {
    const int64_t dim1 = shape[1];
    const int64_t dim2 = shape[2];
    if (dim1 >= 6 && dim1 <= 512) {
      std::vector<float> candidate(static_cast<size_t>(dim1));
      for (int64_t row = 0; row < dim2; ++row) {
        for (int64_t col = 0; col < dim1; ++col) {
          candidate[static_cast<size_t>(col)] = data[col * dim2 + row];
        }
        DecodeCandidate(candidate.data(), dim1, &detections);
      }
    } else if (dim2 >= 6) {
      for (int64_t row = 0; row < dim1; ++row) {
        DecodeCandidate(data + row * dim2, dim2, &detections);
      }
    }
  }

  std::sort(detections.begin(), detections.end(), [](const Detection& a, const Detection& b) {
    return a.confidence > b.confidence;
  });
  if (detections.size() > 20) detections.resize(20);
  return detections;
}

}  // namespace

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

std::vector<float> OptimizedVisionRuntimeEngine::BuildInputTensor(const flutter::EncodableMap* request) {
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
  std::vector<float> tensor(total, 0.0f);

  for (int y = 0; y < target_height; ++y) {
    const int src_y = std::min(source_height - 1, y * source_height / target_height);
    for (int x = 0; x < target_width; ++x) {
      const int src_x = std::min(source_width - 1, x * source_width / target_width);
      const RgbPixel pixel = ReadRgbPixel(image_planes, format, src_x, src_y);
      for (int c = 0; c < channels; ++c) {
        const int channel_value = c == 0 ? pixel.r : (c == 1 ? pixel.g : pixel.b);
        const float value = (channel_value / 255.0f - 0.5f) / 0.5f;
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
  auto tensor = BuildInputTensor(request);
  std::vector<int64_t> shape = input_shape_;
  size_t expected = 1;
  for (const auto dim : shape) expected *= static_cast<size_t>(std::max<int64_t>(1, dim));
  if (expected != tensor.size()) shape = {1, 3, 416, 416};

  Ort::MemoryInfo memory_info = Ort::MemoryInfo::CreateCpu(OrtAllocatorType::OrtArenaAllocator, OrtMemType::OrtMemTypeDefault);
  Ort::Value input_tensor = Ort::Value::CreateTensor<float>(memory_info, tensor.data(), tensor.size(), shape.data(), shape.size());

  auto outputs = session_->Run(Ort::RunOptions{nullptr}, input_name_ptrs_.data(), &input_tensor, 1, output_name_ptrs_.data(), output_name_ptrs_.size());

  flutter::EncodableList output_summaries;
  std::vector<Detection> detections;
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
        auto parsed = ParseDetections(data, output_shape, info.GetElementCount());
        detections.insert(detections.end(), parsed.begin(), parsed.end());
        const size_t limit = std::min<size_t>(info.GetElementCount(), 16);
        flutter::EncodableList sample;
        for (size_t j = 0; j < limit; ++j) sample.push_back(DoubleValue(data[j]));
        summary[StringValue("sample")] = flutter::EncodableValue(sample);
      }
    }
    output_summaries.push_back(flutter::EncodableValue(summary));
  }

  std::sort(detections.begin(), detections.end(), [](const Detection& a, const Detection& b) {
    return a.confidence > b.confidence;
  });
  if (detections.size() > 20) detections.resize(20);

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
  outputs_map[StringValue("input_conversion")] = StringValue("rgb_normalized");

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
