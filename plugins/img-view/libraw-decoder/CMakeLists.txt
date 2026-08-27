cmake_minimum_required(VERSION 3.20)

project(libraw-decoder LANGUAGES CXX)

if(NOT DEFINED LIBRAW_ROOT OR LIBRAW_ROOT STREQUAL "")
  message(FATAL_ERROR "LIBRAW_ROOT must point to the extracted LibRaw directory")
endif()
if(NOT DEFINED LIBRAW_LIB OR LIBRAW_LIB STREQUAL "")
  message(FATAL_ERROR "LIBRAW_LIB must point to LibRaw's import library")
endif()
if(NOT EXISTS "${LIBRAW_ROOT}/libraw/libraw.h")
  message(FATAL_ERROR "LibRaw headers were not found under ${LIBRAW_ROOT}")
endif()
if(NOT EXISTS "${LIBRAW_LIB}")
  message(FATAL_ERROR "LibRaw library was not found at ${LIBRAW_LIB}")
endif()

add_executable(libraw-decoder main.cpp)
target_compile_features(libraw-decoder PRIVATE cxx_std_17)
target_compile_definitions(libraw-decoder PRIVATE LIBRAW_NOTHREADS)
target_include_directories(libraw-decoder PRIVATE "${LIBRAW_ROOT}")
target_link_libraries(libraw-decoder PRIVATE "${LIBRAW_LIB}")
if(MSVC)
  target_compile_options(libraw-decoder PRIVATE /utf-8)
endif()

set_target_properties(libraw-decoder PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/out"
  RUNTIME_OUTPUT_DIRECTORY_DEBUG "${CMAKE_BINARY_DIR}/out"
  RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/out"
  RUNTIME_OUTPUT_DIRECTORY_RELWITHDEBINFO "${CMAKE_BINARY_DIR}/out"
  RUNTIME_OUTPUT_DIRECTORY_MINSIZEREL "${CMAKE_BINARY_DIR}/out"
)
