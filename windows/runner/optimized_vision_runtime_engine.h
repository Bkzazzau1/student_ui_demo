#ifndef RUNNER_OPTIMIZED_VISION_RUNTIME_ENGINE_H_
#define RUNNER_OPTIMIZED_VISION_RUNTIME_ENGINE_H_

#include <flutter/encodable_value.h>

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
  flutter::EncodableMap NotAvailablePayload(const char* message) const;
};

#endif  // RUNNER_OPTIMIZED_VISION_RUNTIME_ENGINE_H_
