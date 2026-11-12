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

// How a camera frame was placed in the model input. Detector boxes are in
// model-input pixels; this geometry is what maps them back to the frame.
struct VisionInputGeometry {
  int input_width = 0;
  int input_height = 0;
  int source_width = 0;
  int source_height = 0;
  // Size of the source frame inside the model input, in input pixels.
  int content_width = 0;
  int content_height = 0;
  // Input pixels per source pixel, and left/top padding in input pixels.
  double scale_x = 1.0;
  double scale_y = 1.0;
  int pad_x = 0;
  int pad_y = 0;
};

class OptimizedVisionRuntimeEngine {
 public:
  OptimizedVisionRuntimeEngine();
  ~OptimizedVisionRuntimeEngine();

  bool Initialize(const flutter::EncodableMap* policy);
  flutter::EncodableMap RunFrame(const flutter::EncodableMap* request);
  bool available() const { return available_; }

  // Letterbox (aspect-preserving, centered) or stretch placement of a source
  // frame in the model input. Shared by preprocessing and box decoding.
  static VisionInputGeometry ComputeInputGeometry(const std::string& preprocessing,
                                                  int source_width,
                                                  int source_height,
                                                  int input_width,
                                                  int input_height);

 private:
  bool available_ = false;
  double last_inference_ms_ = 0.0;
  std::string backend_ = "not_available";
  std::string precision_ = "not_available";
  std::string model_path_;
  std::string last_error_;
  // Contract from the validated model manifest, sent in the init policy.
  std::string model_family_ = "yolo";
  std::string output_layout_ = "channels_first_yolov8";
  std::string input_preprocessing_ = "letterbox_rgb01";
  std::vector<std::string> class_names_;
  double confidence_threshold_ = 0.45;
  double iou_threshold_ = 0.45;

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
  std::vector<float> BuildInputTensor(const flutter::EncodableMap* request,
                                      VisionInputGeometry* geometry);
  flutter::EncodableMap RunOnnxFrame(const flutter::EncodableMap* request);
#endif

  flutter::EncodableMap NotAvailablePayload(const char* message) const;
  flutter::EncodableMap NotAvailablePayload(const std::string& message) const;
};

#endif  // RUNNER_OPTIMIZED_VISION_RUNTIME_ENGINE_H_
