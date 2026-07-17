cmake_minimum_required(VERSION 3.28)

project(SwanSongAresEngine LANGUAGES C CXX OBJC OBJCXX)

if(NOT ARES_SOURCE_DIR)
  message(FATAL_ERROR "ARES_SOURCE_DIR must point to the pinned, patched ares checkout")
endif()

file(READ "${CMAKE_CURRENT_LIST_DIR}/../Dependencies/ares.lock.json" SWAN_ARES_LOCK)
string(JSON SWAN_ARES_COMMIT GET "${SWAN_ARES_LOCK}" commit)

set(ARES_HEADLESS_CORE_ONLY ON CACHE BOOL "" FORCE)
set(ARES_SKIP_DEPS ON CACHE BOOL "" FORCE)
set(ARES_CORES ws CACHE STRING "" FORCE)
set(ARES_BUILD_OPTIONAL_TARGETS OFF CACHE BOOL "" FORCE)
option(
  SWAN_PORTABLE_BUILD
  "Disable host-specific ares CPU tuning for distributable builds"
  OFF
)
if(SWAN_PORTABLE_BUILD)
  set(ARES_BUILD_LOCAL OFF CACHE BOOL "" FORCE)
else()
  set(ARES_BUILD_LOCAL ON CACHE BOOL "" FORCE)
endif()
set(ARES_ENABLE_CHD OFF CACHE BOOL "" FORCE)

add_subdirectory("${ARES_SOURCE_DIR}" "${CMAKE_BINARY_DIR}/ares")

add_library(SwanAresEngine SHARED
  "${CMAKE_CURRENT_LIST_DIR}/../Sources/CSwanEngine/swan_engine.cpp"
  "${CMAKE_CURRENT_LIST_DIR}/../Sources/CSwanEngine/swan_engine_ares.cpp"
)

target_compile_features(SwanAresEngine PUBLIC cxx_std_20)
target_compile_definitions(
  SwanAresEngine
  PRIVATE
    SWAN_ENABLE_ARES=1
    SWAN_ENGINE_BUILD_ID="ares-${SWAN_ARES_COMMIT}-swan-abi7"
)
set_target_properties(SwanAresEngine PROPERTIES
  CXX_VISIBILITY_PRESET default
  VISIBILITY_INLINES_HIDDEN NO
)
target_include_directories(SwanAresEngine
  PUBLIC "${CMAKE_CURRENT_LIST_DIR}/../Sources/CSwanEngine/include"
  PRIVATE
    "${ARES_SOURCE_DIR}"
    "${ARES_SOURCE_DIR}/ares"
    "${ARES_SOURCE_DIR}/nall"
)
target_link_libraries(SwanAresEngine PUBLIC ares nall)

add_executable(SwanAresSmoke "${CMAKE_CURRENT_LIST_DIR}/Tests/ares_smoke.cpp")
target_link_libraries(SwanAresSmoke PRIVATE SwanAresEngine)
