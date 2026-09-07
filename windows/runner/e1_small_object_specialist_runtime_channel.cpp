#include "e1_small_object_specialist_runtime_channel.h"

#include <flutter/encodable_value.h>
#include <flutter/method_call.h>
#include <flutter/method_channel.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include "optimized_vision_runtime_engine.h"

namespace {

constexpr char kChannelName[] = "kslas.e1_small_object_specialist_runtime";

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

struct NormalizedRoi {
  double x = 0.0;
  double y = 0.0;
  double width = 0.0;
  double height = 0.0;
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

const flutter::EncodableMap* MapArgument(
    const flutter::MethodCall<flutter::EncodableValue>& call) {
  if (call.arguments() == nullptr) {
    return nullptr;
  }
  return std::get_if<flutter::EncodableMap>(call.arguments());
}

const flutter::EncodableValue* FindValue(const flutter::EncodableMap* map,
                                         const char* key) {
  if (map == nullptr) return nullptr;
  const auto it = map->find(StringValue(key));
  if (it == map->end()) return nullptr;
  return &it->second;
}

const flutter::EncodableMap* ReadMap(const flutter::EncodableMap* map,
                                     const char* key) {
  const auto* value = FindValue(map, key);
  return value == nullptr ? nullptr : std::get_if<flutter::EncodableMap>(value);
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
  if (const auto* int32_value = std::get_if<int32_t>(value)) {
    return *int32_value;
  }
  if (const auto* int64_value = std::get_if<int64_t>(value)) {
    return static_cast<int>(*int64_value);
  }
  if (const auto* double_value = std::get_if<double>(value)) {
    return static_cast<int>(*double_value);
  }
  return fallback;
}

double ReadDouble(const flutter::EncodableMap* map,
                  const char* key,
                  double fallback) {
  const auto* value = FindValue(map, key);
  if (value == nullptr) return fallback;
  if (const auto* double_value = std::get_if<double>(value)) {
    return *double_value;
  }
  if (const auto* int32_value = std::get_if<int32_t>(value)) {
    return static_cast<double>(*int32_value);
  }
  if (const auto* int64_value = std::get_if<int64_t>(value)) {
    return static_cast<double>(*int64_value);
  }
  return fallback;
}

int Clamp255(int value) {
  return std::max(0, std::min(255, value));
}

uint8_t SafeByte(const ImagePlane& plane, int index) {
  if (plane.bytes == nullptr || index < 0 ||
      index >= static_cast<int>(plane.bytes->size())) {
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
  const int y_value =
      SafeByte(y_plane, y * y_plane.row_stride + x * y_plane.pixel_stride);
  const int chroma_x = x / 2;
  const int chroma_y = y / 2;
  const int u_value = SafeByte(
      u_plane,
      chroma_y * u_plane.row_stride + chroma_x * u_plane.pixel_stride);
  const int v_value = SafeByte(
      v_plane,
      chroma_y * v_plane.row_stride + chroma_x * v_plane.pixel_stride);
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
  const ImagePlane& luma = planes.front();
  const int value =
      SafeByte(luma, y * luma.row_stride + x * luma.pixel_stride);
  return RgbPixel{value, value, value};
}

bool ReadNormalizedRoi(const flutter::EncodableMap* request,
                       NormalizedRoi* roi) {
  if (request == nullptr || roi == nullptr) return false;
  const auto* roi_hint = ReadMap(request, "roi_hint");
  const auto* box = ReadMap(roi_hint, "bounding_box");
  if (box == nullptr) return false;

  roi->x = ReadDouble(box, "x", -1.0);
  roi->y = ReadDouble(box, "y", -1.0);
  roi->width = ReadDouble(box, "width", -1.0);
  roi->height = ReadDouble(box, "height", -1.0);
  if (!std::isfinite(roi->x) || !std::isfinite(roi->y) ||
      !std::isfinite(roi->width) || !std::isfinite(roi->height)) {
    return false;
  }
  if (roi->x < 0.0 || roi->y < 0.0 || roi->width <= 0.0 ||
      roi->height <= 0.0) {
    return false;
  }
  return roi->x + roi->width <= 1.0001 &&
         roi->y + roi->height <= 1.0001;
}

bool ReadImagePlanes(const flutter::EncodableMap* request,
                     int source_width,
                     std::vector<ImagePlane>* image_planes) {
  if (request == nullptr || image_planes == nullptr) return false;
  const auto* planes_value = FindValue(request, "planes");
  const auto* planes = planes_value == nullptr
                           ? nullptr
                           : std::get_if<flutter::EncodableList>(planes_value);
  if (planes == nullptr || planes->empty()) return false;

  image_planes->clear();
  for (const auto& plane_value : *planes) {
    const auto* plane = std::get_if<flutter::EncodableMap>(&plane_value);
    if (plane == nullptr) continue;
    const auto* bytes_value = FindValue(plane, "bytes");
    const auto* bytes = bytes_value == nullptr
                            ? nullptr
                            : std::get_if<std::vector<uint8_t>>(bytes_value);
    if (bytes == nullptr || bytes->empty()) continue;
    image_planes->push_back(ImagePlane{
        bytes,
        std::max(1, ReadInt(plane, "bytes_per_row", source_width)),
        std::max(1, ReadInt(plane, "bytes_per_pixel", 1)),
    });
  }
  return !image_planes->empty();
}

flutter::EncodableMap UnavailablePayload(const std::string& message) {
  flutter::EncodableMap outputs;
  outputs[StringValue("message")] = StringValue(message);
  flutter::EncodableMap response;
  response[StringValue("available")] = flutter::EncodableValue(false);
  response[StringValue("backend")] = StringValue("not_available");
  response[StringValue("precision")] = StringValue("not_available");
  response[StringValue("inference_ms")] = DoubleValue(0.0);
  response[StringValue("outputs")] = flutter::EncodableValue(outputs);
  return response;
}

bool BuildCroppedRgbRequest(const flutter::EncodableMap* request,
                            flutter::EncodableMap* cropped_request,
                            NormalizedRoi* applied_roi) {
  if (request == nullptr || cropped_request == nullptr ||
      applied_roi == nullptr) {
    return false;
  }

  const int source_width = ReadInt(request, "width", 0);
  const int source_height = ReadInt(request, "height", 0);
  if (source_width <= 0 || source_height <= 0) return false;

  NormalizedRoi requested_roi;
  if (!ReadNormalizedRoi(request, &requested_roi)) return false;

  std::vector<ImagePlane> image_planes;
  if (!ReadImagePlanes(request, source_width, &image_planes)) return false;

  const int left = std::clamp(
      static_cast<int>(std::floor(requested_roi.x * source_width)),
      0,
      source_width - 1);
  const int top = std::clamp(
      static_cast<int>(std::floor(requested_roi.y * source_height)),
      0,
      source_height - 1);
  const int right = std::clamp(
      static_cast<int>(std::ceil(
          (requested_roi.x + requested_roi.width) * source_width)),
      left + 1,
      source_width);
  const int bottom = std::clamp(
      static_cast<int>(std::ceil(
          (requested_roi.y + requested_roi.height) * source_height)),
      top + 1,
      source_height);
  const int crop_width = right - left;
  const int crop_height = bottom - top;
  if (crop_width <= 0 || crop_height <= 0) return false;

  applied_roi->x = static_cast<double>(left) / source_width;
  applied_roi->y = static_cast<double>(top) / source_height;
  applied_roi->width = static_cast<double>(crop_width) / source_width;
  applied_roi->height = static_cast<double>(crop_height) / source_height;

  const std::string format = ReadString(request, "format");
  std::vector<uint8_t> rgb(
      static_cast<size_t>(crop_width) * crop_height * 3,
      0);
  size_t cursor = 0;
  for (int y = top; y < bottom; ++y) {
    for (int x = left; x < right; ++x) {
      const RgbPixel pixel = ReadRgbPixel(image_planes, format, x, y);
      rgb[cursor++] = static_cast<uint8_t>(Clamp255(pixel.r));
      rgb[cursor++] = static_cast<uint8_t>(Clamp255(pixel.g));
      rgb[cursor++] = static_cast<uint8_t>(Clamp255(pixel.b));
    }
  }

  flutter::EncodableMap plane;
  plane[StringValue("bytes")] = flutter::EncodableValue(rgb);
  plane[StringValue("bytes_per_row")] =
      flutter::EncodableValue(crop_width * 3);
  plane[StringValue("bytes_per_pixel")] = flutter::EncodableValue(3);
  plane[StringValue("width")] = flutter::EncodableValue(crop_width);
  plane[StringValue("height")] = flutter::EncodableValue(crop_height);

  flutter::EncodableList planes;
  planes.push_back(flutter::EncodableValue(plane));

  (*cropped_request)[StringValue("width")] =
      flutter::EncodableValue(crop_width);
  (*cropped_request)[StringValue("height")] =
      flutter::EncodableValue(crop_height);
  (*cropped_request)[StringValue("format")] = StringValue("rgb888");
  (*cropped_request)[StringValue("planes")] = flutter::EncodableValue(planes);
  return true;
}

void AnnotateAppliedRoi(flutter::EncodableMap* response,
                        const NormalizedRoi& roi) {
  if (response == nullptr) return;
  const auto outputs_it = response->find(StringValue("outputs"));
  if (outputs_it == response->end()) return;
  auto* outputs = std::get_if<flutter::EncodableMap>(&outputs_it->second);
  if (outputs == nullptr) return;

  flutter::EncodableMap roi_map;
  roi_map[StringValue("x")] = DoubleValue(roi.x);
  roi_map[StringValue("y")] = DoubleValue(roi.y);
  roi_map[StringValue("width")] = DoubleValue(roi.width);
  roi_map[StringValue("height")] = DoubleValue(roi.height);
  (*outputs)[StringValue("roi_applied")] = flutter::EncodableValue(true);
  (*outputs)[StringValue("source_roi")] = flutter::EncodableValue(roi_map);
  (*outputs)[StringValue("output_coordinate_space")] =
      StringValue("normalized_roi");
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
          flutter::EncodableMap cropped_request;
          NormalizedRoi applied_roi;
          if (!BuildCroppedRgbRequest(
                  request,
                  &cropped_request,
                  &applied_roi)) {
            result->Success(flutter::EncodableValue(UnavailablePayload(
                "Specialist ROI or source frame is invalid.")));
            return;
          }

          auto response = specialist_engine.RunFrame(&cropped_request);
          AnnotateAppliedRoi(&response, applied_roi);
          result->Success(flutter::EncodableValue(response));
          return;
        }

        result->NotImplemented();
      });
}
