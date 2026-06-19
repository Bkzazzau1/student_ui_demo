#ifndef RUNNER_OPTIMIZED_VISION_RUNTIME_ENGINE_H_
#define RUNNER_OPTIMIZED_VISION_RUNTIME_ENGINE_H_

#include <flutter/encodable_value.h>

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#ifdef KSLAS_ENABLE_ONNXRUNTIME
namespace Ort {
struct Env;
struct Session;
struct SessionOptions;
}  // namespace Ort
#endif

class OptimizedVisionRuntimeEngine {
 public:
  OptimizedVisionRuntimeEngine();
  ~OptimizedVisionRuntimeEngine();

  bool Initialize(const flutter::EncodableMap* policy);
  flutter::EncodableMap RunFrame(const flutter::EncodableMap* request);
  bool available() const { return available_; }

 private:
  bool available_ = false;
  double last_inference_ms_ = 0.0;
  std::string backend_ = "not_available";
  std::string precision_ = "not_available";
  std::string model_path_;
  std::string last_error_;

#ifdef KSLAS_ENABLE_ONNXRUNTIME
  std::unique_ptr<Ort::Env> env_;
  std::unique_ptr<Ort::SessionOptions> session_options_;
  std::unique_ptr<Ort::Session> session_;
  std::vector<std::string> input_names_;
  std::vector<std::string> output_names_;
  std::vector<const char*> input_name_ptrs_;
  std::vector<const char*> output_name_ptrs_;
  std::vector<int64_t> input_shape_;

  bool LoadSession(const flutter::EncodableMap* policy);
  std::string ResolveModelPath(const flutter::EncodableMap* policy) const;
  std::vector<float> BuildInputTensor(const flutter::EncodableMap* request);
  flutter::EncodableMap RunOnnxFrame(const flutter::EncodableMap* request);
#endif

  flutter::EncodableMap NotAvailablePayload(const char* message) const;
  flutter::EncodableMap NotAvailablePayload(const std::string& message) const;
};

#endif  // RUNNER_OPTIMIZED_VISION_RUNTIME_ENGINE_H_
