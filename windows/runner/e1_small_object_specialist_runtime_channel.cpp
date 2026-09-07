#include "e1_small_object_specialist_runtime_channel.h"

#include <flutter/encodable_value.h>
#include <flutter/method_call.h>
#include <flutter/method_channel.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>

#include "optimized_vision_runtime_engine.h"

namespace {

constexpr char kChannelName[] = "kslas.e1_small_object_specialist_runtime";

const flutter::EncodableMap* MapArgument(
    const flutter::MethodCall<flutter::EncodableValue>& call) {
  if (call.arguments() == nullptr) {
    return nullptr;
  }
  return std::get_if<flutter::EncodableMap>(call.arguments());
}

}  // namespace

void RegisterE1SmallObjectSpecialistRuntimeChannel(
    flutter::BinaryMessenger* messenger) {
  static std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel;
  // Deliberately separate from the base E1 optimized-vision engine. A
  // specialist model must never replace the base YOLO session at runtime.
  static OptimizedVisionRuntimeEngine specialist_engine;

  channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, kChannelName, &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name().compare("initialize") == 0) {
          const auto* policy = MapArgument(call);
          result->Success(
              flutter::EncodableValue(specialist_engine.Initialize(policy)));
          return;
        }

        if (call.method_name().compare("runFrame") == 0) {
          const auto* request = MapArgument(call);
          result->Success(
              flutter::EncodableValue(specialist_engine.RunFrame(request)));
          return;
        }

        result->NotImplemented();
      });
}
