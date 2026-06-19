cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "optimized_vision_runtime_channel.cpp"
  "optimized_vision_runtime_engine.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

set(KSLAS_LOCAL_ONNXRUNTIME_ROOT
  "${CMAKE_CURRENT_LIST_DIR}/../../third_party/onnxruntime-directml/package")
if(EXISTS "${KSLAS_LOCAL_ONNXRUNTIME_ROOT}/runtimes/win-x64/native/onnxruntime.lib")
  set(KSLAS_DEFAULT_ONNXRUNTIME_ROOT "${KSLAS_LOCAL_ONNXRUNTIME_ROOT}")
else()
  set(KSLAS_DEFAULT_ONNXRUNTIME_ROOT "")
endif()

set(ONNXRUNTIME_ROOT "${KSLAS_DEFAULT_ONNXRUNTIME_ROOT}" CACHE PATH "Optional ONNX Runtime root directory")
if(NOT ONNXRUNTIME_ROOT AND KSLAS_DEFAULT_ONNXRUNTIME_ROOT)
  set(ONNXRUNTIME_ROOT "${KSLAS_DEFAULT_ONNXRUNTIME_ROOT}" CACHE PATH
    "Optional ONNX Runtime root directory" FORCE)
endif()
if(ONNXRUNTIME_ROOT)
  target_compile_definitions(${BINARY_NAME} PRIVATE "KSLAS_ENABLE_ONNXRUNTIME")
  target_include_directories(${BINARY_NAME} PRIVATE
    "${ONNXRUNTIME_ROOT}/include"
    "${ONNXRUNTIME_ROOT}/build/native/include"
  )
  target_link_libraries(${BINARY_NAME} PRIVATE
    "${ONNXRUNTIME_ROOT}/runtimes/win-x64/native/onnxruntime.lib")
  if(EXISTS "${ONNXRUNTIME_ROOT}/runtimes/win-x64/native/onnxruntime.dll")
    add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${ONNXRUNTIME_ROOT}/runtimes/win-x64/native/onnxruntime.dll"
        "$<TARGET_FILE_DIR:${BINARY_NAME}>/onnxruntime.dll")
  endif()
  if(EXISTS "${ONNXRUNTIME_ROOT}/runtimes/win-x64/native/onnxruntime_providers_shared.dll")
    add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${ONNXRUNTIME_ROOT}/runtimes/win-x64/native/onnxruntime_providers_shared.dll"
        "$<TARGET_FILE_DIR:${BINARY_NAME}>/onnxruntime_providers_shared.dll")
  endif()
  if(EXISTS "${ONNXRUNTIME_ROOT}/runtimes/win-x64/native/DirectML.dll")
    add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${ONNXRUNTIME_ROOT}/runtimes/win-x64/native/DirectML.dll"
        "$<TARGET_FILE_DIR:${BINARY_NAME}>/DirectML.dll")
  endif()
endif()

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
