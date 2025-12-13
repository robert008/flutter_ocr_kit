cmake_minimum_required(VERSION 3.10)
project(ocr_kit)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Source files
set(SOURCES
    native_lib.cpp
    ocr/ocr_engine.cpp
    ocr/config_manager.cpp
    ocr/utils.cpp
)

# Header directories
set(INCLUDE_DIRS
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/ocr/include
)

# For Android NDK build
if(ANDROID)
    find_package(OpenCV REQUIRED)

    add_library(ocr_kit SHARED ${SOURCES})

    target_include_directories(ocr_kit PRIVATE
        ${INCLUDE_DIRS}
        ${ONNXRUNTIME_DIR}/include
    )

    target_link_libraries(ocr_kit
        ${OpenCV_LIBS}
        ${ONNXRUNTIME_DIR}/lib/${ANDROID_ABI}/libonnxruntime.so
        log
    )

    # Support Android 15 16k page size
    target_link_options(ocr_kit PRIVATE "-Wl,-z,max-page-size=16384")
endif()

# For iOS build
if(IOS)
    find_package(OpenCV REQUIRED)

    add_library(ocr_kit STATIC ${SOURCES})

    target_include_directories(ocr_kit PRIVATE
        ${INCLUDE_DIRS}
        ${ONNXRUNTIME_DIR}/include
    )

    target_link_libraries(ocr_kit
        ${OpenCV_LIBS}
    )
endif()

# For desktop build (testing)
if(NOT ANDROID AND NOT IOS)
    find_package(OpenCV REQUIRED)

    add_library(ocr_kit STATIC ${SOURCES})

    target_include_directories(ocr_kit PRIVATE
        ${INCLUDE_DIRS}
        ${OpenCV_INCLUDE_DIRS}
        ${ONNXRUNTIME_DIR}/include
    )

    target_link_libraries(ocr_kit
        ${OpenCV_LIBS}
    )
endif()
