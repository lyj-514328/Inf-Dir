cmake_minimum_required(VERSION 3.20)

project(wic-decoder LANGUAGES CXX)

add_executable(wic-decoder main.cpp)
target_compile_features(wic-decoder PRIVATE cxx_std_17)
target_compile_definitions(wic-decoder PRIVATE UNICODE _UNICODE NOMINMAX WIN32_LEAN_AND_MEAN)
target_link_libraries(wic-decoder PRIVATE ole32 windowscodecs)

if(MSVC)
  target_compile_options(wic-decoder PRIVATE /utf-8)
endif()

set_target_properties(wic-decoder PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/out"
  RUNTIME_OUTPUT_DIRECTORY_DEBUG "${CMAKE_BINARY_DIR}/out"
  RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/out"
  RUNTIME_OUTPUT_DIRECTORY_RELWITHDEBINFO "${CMAKE_BINARY_DIR}/out"
  RUNTIME_OUTPUT_DIRECTORY_MINSIZEREL "${CMAKE_BINARY_DIR}/out"
)
