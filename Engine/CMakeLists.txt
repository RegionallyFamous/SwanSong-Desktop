cmake_minimum_required(VERSION 3.28)

project(SwanSongAresEngine LANGUAGES C CXX OBJC OBJCXX)

if(NOT ARES_SOURCE_DIR)
  message(FATAL_ERROR "ARES_SOURCE_DIR must point to the pinned, patched ares checkout")
endif()

file(READ "${CMAKE_CURRENT_LIST_DIR}/../Dependencies/ares.lock.json" SWAN_ARES_LOCK)
string(JSON SWAN_ARES_COMMIT GET "${SWAN_ARES_LOCK}" commit)
file(SHA256 "${CMAKE_CURRENT_LIST_DIR}/ares-headless.patch" SWAN_ARES_PATCH_SHA256)
# Keep the established 40-hex build-ID shape while binding it to both the
# pinned upstream revision and the exact local ares patch payload.
string(SHA1 SWAN_ARES_SOURCE_IDENTITY
  "${SWAN_ARES_COMMIT}:${SWAN_ARES_PATCH_SHA256}"
)

execute_process(
  COMMAND
    /bin/sh
    "${CMAKE_CURRENT_LIST_DIR}/../Scripts/ares-source-state.sh"
    check
    "${ARES_SOURCE_DIR}"
    "${SWAN_ARES_COMMIT}"
    "${CMAKE_CURRENT_LIST_DIR}/ares-headless.patch"
  RESULT_VARIABLE SWAN_ARES_SOURCE_CHECK_RESULT
  OUTPUT_VARIABLE SWAN_ARES_SOURCE_CHECK_OUTPUT
  ERROR_VARIABLE SWAN_ARES_SOURCE_CHECK_ERROR
)
if(NOT SWAN_ARES_SOURCE_CHECK_RESULT EQUAL 0)
  string(STRIP "${SWAN_ARES_SOURCE_CHECK_ERROR}" SWAN_ARES_SOURCE_CHECK_ERROR)
  message(FATAL_ERROR
    "The prepared ares source is stale or unauthenticated: "
    "${SWAN_ARES_SOURCE_CHECK_ERROR}"
  )
endif()

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
    SWAN_ENGINE_BUILD_ID="ares-${SWAN_ARES_SOURCE_IDENTITY}-swan-abi9"
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
if(APPLE)
  # Capability receipts compare complete source-built engine bytes. Strip
  # build-time STABS/N_OSO metadata while retaining the exported ABI table.
  # Apple's linker then derives the required LC_UUID from stable content.
  target_link_options(SwanAresEngine PRIVATE -Wl,-S)
endif()

add_executable(SwanAresSmoke "${CMAKE_CURRENT_LIST_DIR}/Tests/ares_smoke.cpp")
target_link_libraries(SwanAresSmoke PRIVATE SwanAresEngine)

add_executable(
  SwanV30PrefetchOriginControl
  "${CMAKE_CURRENT_LIST_DIR}/Tests/v30_prefetch_origin_control.cpp"
)
target_compile_features(SwanV30PrefetchOriginControl PRIVATE cxx_std_20)
target_include_directories(
  SwanV30PrefetchOriginControl
  PRIVATE
    "${ARES_SOURCE_DIR}"
    "${ARES_SOURCE_DIR}/ares"
    "${ARES_SOURCE_DIR}/ares/component/processor/v30mz"
    "${ARES_SOURCE_DIR}/nall"
    "${ARES_SOURCE_DIR}/thirdparty/sljit"
)
target_link_libraries(SwanV30PrefetchOriginControl PRIVATE ares nall)
