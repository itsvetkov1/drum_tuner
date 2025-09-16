cmake_minimum_required(VERSION 3.20)
project(dsp_core LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(dsp_core STATIC)

target_sources(dsp_core
    PRIVATE
        src/dsp_core.cpp
)

target_include_directories(dsp_core
    PUBLIC
        ${PROJECT_SOURCE_DIR}/include
)

enable_testing()
add_subdirectory(tests)
