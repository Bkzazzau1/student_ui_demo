#include "optimized_vision_runtime_channel.h"

#include <flutter/encodable_value.h>
#include <flutter/method_call.h>
#include <flutter/method_channel.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>

namespace {

constexpr char kChannelName[] = "kslas.optimized_vision_runtime";

flutter::EncodableMap NotAvailablePayload() {
  flutter::EncodableMap outputs;
  outputs[flutter::EncodableValue("message")] =
      flutter::EncodableValue("Optimized native vision runtime is not linked yet. Install ONNX Runtime DirectML/TensorRT and replace this stub with the production runner.");

  flutter::EncodableMap response;
  response[flutter::EncodableValue("available")] = flutter::EncodableValue(false);
  response[flutter::EncodableValue("backend")] = flutter::EncodableValue("not_available");
  response[flutter::EncodableValue("precision")] = flutter::EncodableValue("not_available");
  response[flutter::EncodableValue("inference_ms")] = flutter::EncodableValue(0.0);
  response[flutter::EncodableValue("outputs")] = flutter::EncodableValue(outputs);
  return response;
}

}  // namespace

void RegisterOptimizedVisionRuntimeChannel(flutter::BinaryMessenger* messenger) {
  static std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel;
  channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, kChannelName, &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name().compare("initialize") == 0) {
          result->Success(flutter::EncodableValue(false));
          return;
        }

        if (call.method_name().compare("runFrame") == 0) {
          result->Success(flutter::EncodableValue(NotAvailablePayload()));
          return;
        }

        result->NotImplemented();
      });
}
