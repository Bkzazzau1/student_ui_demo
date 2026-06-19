#include "optimized_vision_runtime_engine.h"

#include <chrono>
#include <string>

#ifdef KSLAS_ENABLE_ONNXRUNTIME
#include <onnxruntime_cxx_api.h>
#endif

namespace {

flutter::EncodableValue StringValue(const char* value) {
  return flutter::EncodableValue(std::string(value));
}

flutter::EncodableValue DoubleValue(double value) {
  return flutter::EncodableValue(value);
}

}  // namespace

OptimizedVisionRuntimeEngine::OptimizedVisionRuntimeEngine() = default;
OptimizedVisionRuntimeEngine::~OptimizedVisionRuntimeEngine() = default;

bool OptimizedVisionRuntimeEngine::Initialize(const flutter::EncodableMap* policy) {
#ifdef KSLAS_ENABLE_ONNXRUNTIME
  // ONNX Runtime is available at compile time. The production implementation
  // should create Ort::Env, Ort::SessionOptions, append DirectML when present,
  // and load the selected INT8/FP16 model from the Flutter assets directory.
  // This scaffold intentionally keeps startup safe until model paths and
  // post-processing are finalized.
  available_ = false;
  return available_;
#else
  (void)policy;
  available_ = false;
  return false;
#endif
}

flutter::EncodableMap OptimizedVisionRuntimeEngine::RunFrame(
    const flutter::EncodableMap* request) {
  auto started = std::chrono::high_resolution_clock::now();
#ifdef KSLAS_ENABLE_ONNXRUNTIME
  // Production path placeholder. When the model is linked, this method should:
  // 1. Convert the incoming camera plane to the selected model tensor.
  // 2. Resize to the policy input size, normally 320x320 or 416x416.
  // 3. Run ONNX Runtime with DirectML/TensorRT/CPU provider.
  // 4. Return detections, landmarks, confidence, and timing.
  (void)request;
#else
  (void)request;
#endif
  auto elapsed = std::chrono::high_resolution_clock::now() - started;
  last_inference_ms_ =
      std::chrono::duration_cast<std::chrono::microseconds>(elapsed).count() /
      1000.0;
  return NotAvailablePayload(
      "ONNX Runtime engine is compiled as a safe scaffold. Provide ONNXRUNTIME_ROOT and model assets to enable production inference.");
}

flutter::EncodableMap OptimizedVisionRuntimeEngine::NotAvailablePayload(
    const char* message) const {
  flutter::EncodableMap outputs;
  outputs[StringValue("message")] = StringValue(message);

  flutter::EncodableMap response;
  response[StringValue("available")] = flutter::EncodableValue(false);
  response[StringValue("backend")] = StringValue("not_available");
  response[StringValue("precision")] = StringValue("not_available");
  response[StringValue("inference_ms")] = DoubleValue(last_inference_ms_);
  response[StringValue("outputs")] = flutter::EncodableValue(outputs);
  return response;
}
