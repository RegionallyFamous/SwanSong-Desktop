#ifndef SWAN_ENGINE_H
#define SWAN_ENGINE_H

#include <stddef.h>
#include <stdint.h>

#if defined(__GNUC__) || defined(__clang__)
#define SWAN_ENGINE_API __attribute__((visibility("default")))
#else
#define SWAN_ENGINE_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

#define SWAN_ENGINE_ABI_VERSION 4u

typedef struct swan_engine swan_engine_t;

typedef enum swan_result {
  SWAN_RESULT_OK = 0,
  SWAN_RESULT_INVALID_ARGUMENT = 1,
  SWAN_RESULT_ABI_MISMATCH = 2,
  SWAN_RESULT_INVALID_ROM = 3,
  SWAN_RESULT_IO_ERROR = 4,
  SWAN_RESULT_BACKEND_UNAVAILABLE = 5,
  SWAN_RESULT_NOT_LOADED = 6,
  SWAN_RESULT_UNSUPPORTED = 7,
  SWAN_RESULT_INTERNAL_ERROR = 8,
} swan_result_t;

typedef enum swan_model {
  SWAN_MODEL_AUTOMATIC = 0,
  SWAN_MODEL_WONDERSWAN = 1,
  SWAN_MODEL_WONDERSWAN_COLOR = 2,
  SWAN_MODEL_SWANCRYSTAL = 3,
  SWAN_MODEL_POCKET_CHALLENGE_V2 = 4,
} swan_model_t;

typedef enum swan_rtc_mode {
  SWAN_RTC_MODE_WALL_CLOCK = 0,
  SWAN_RTC_MODE_DETERMINISTIC = 1,
} swan_rtc_mode_t;

typedef enum swan_orientation {
  SWAN_ORIENTATION_HORIZONTAL = 0,
  SWAN_ORIENTATION_VERTICAL = 1,
} swan_orientation_t;

typedef enum swan_pixel_format {
  SWAN_PIXEL_FORMAT_BGRA8888 = 1,
} swan_pixel_format_t;

typedef enum swan_persistence_kind {
  SWAN_PERSISTENCE_CONSOLE_EEPROM = 1,
  SWAN_PERSISTENCE_CARTRIDGE_RAM = 2,
  SWAN_PERSISTENCE_CARTRIDGE_EEPROM = 3,
  SWAN_PERSISTENCE_CARTRIDGE_FLASH = 4,
  SWAN_PERSISTENCE_RTC = 5,
} swan_persistence_kind_t;

typedef enum swan_memory_region {
  SWAN_MEMORY_INTERNAL_RAM = 1,
} swan_memory_region_t;

enum {
  SWAN_INPUT_Y1 = 1u << 0,
  SWAN_INPUT_Y2 = 1u << 1,
  SWAN_INPUT_Y3 = 1u << 2,
  SWAN_INPUT_Y4 = 1u << 3,
  SWAN_INPUT_X1 = 1u << 4,
  SWAN_INPUT_X2 = 1u << 5,
  SWAN_INPUT_X3 = 1u << 6,
  SWAN_INPUT_X4 = 1u << 7,
  SWAN_INPUT_B = 1u << 8,
  SWAN_INPUT_A = 1u << 9,
  SWAN_INPUT_START = 1u << 10,
  SWAN_INPUT_VOLUME = 1u << 11,
  SWAN_INPUT_POWER = 1u << 12,
  SWAN_INPUT_POCKET_CHALLENGE_UP = 1u << 13,
  SWAN_INPUT_POCKET_CHALLENGE_RIGHT = 1u << 14,
  SWAN_INPUT_POCKET_CHALLENGE_DOWN = 1u << 15,
  SWAN_INPUT_POCKET_CHALLENGE_LEFT = 1u << 16,
  SWAN_INPUT_POCKET_CHALLENGE_PASS = 1u << 17,
  SWAN_INPUT_POCKET_CHALLENGE_CIRCLE = 1u << 18,
  SWAN_INPUT_POCKET_CHALLENGE_CLEAR = 1u << 19,
  SWAN_INPUT_POCKET_CHALLENGE_VIEW = 1u << 20,
  SWAN_INPUT_POCKET_CHALLENGE_ESCAPE = 1u << 21,
};

enum {
  SWAN_CAPABILITY_ROM_INSPECTION = 1ull << 0,
  SWAN_CAPABILITY_EXECUTION = 1ull << 1,
  SWAN_CAPABILITY_AUDIO = 1ull << 2,
  SWAN_CAPABILITY_SAVE_STATES = 1ull << 3,
  SWAN_CAPABILITY_PERSISTENCE = 1ull << 4,
  SWAN_CAPABILITY_DEBUGGER = 1ull << 5,
  SWAN_CAPABILITY_STRUCTURED_TRACE = 1ull << 6,
  SWAN_CAPABILITY_POCKET_CHALLENGE_V2 = 1ull << 7,
};

typedef struct swan_engine_config {
  uint32_t struct_size;
  uint32_t abi_version;
  swan_model_t preferred_model;
  uint32_t output_sample_rate;
  swan_rtc_mode_t rtc_mode;
  uint32_t reserved;
  uint64_t rtc_seed_unix_seconds;
} swan_engine_config_t;

typedef struct swan_rom_info {
  uint32_t struct_size;
  uint64_t file_size;
  uint64_t mapped_size;
  uint16_t stored_checksum;
  uint16_t computed_checksum;
  uint8_t color;
  uint8_t save_type;
  uint8_t mapper;
  uint8_t rom_size_code;
  uint8_t checksum_valid;
  uint8_t footer_valid;
  uint8_t compact_layout;
  uint8_t has_rtc;
} swan_rom_info_t;

typedef struct swan_video_frame {
  uint32_t struct_size;
  const uint8_t* pixels;
  size_t byte_count;
  uint32_t width;
  uint32_t height;
  uint32_t stride_bytes;
  swan_pixel_format_t pixel_format;
  swan_orientation_t orientation;
  uint64_t frame_number;
} swan_video_frame_t;

typedef struct swan_audio_batch {
  uint32_t struct_size;
  const float* interleaved_samples;
  size_t frame_count;
  uint32_t channels;
  uint32_t sample_rate;
} swan_audio_batch_t;

SWAN_ENGINE_API const char* swan_result_message(swan_result_t result);

SWAN_ENGINE_API swan_result_t swan_inspect_rom(const uint8_t* bytes,
                                               size_t size,
                                               swan_rom_info_t* out_info);

SWAN_ENGINE_API swan_engine_t* swan_engine_create(
    const swan_engine_config_t* config);
SWAN_ENGINE_API void swan_engine_destroy(swan_engine_t* engine);

SWAN_ENGINE_API uint32_t swan_engine_abi_version(const swan_engine_t* engine);
SWAN_ENGINE_API const char* swan_engine_backend_name(
    const swan_engine_t* engine);
SWAN_ENGINE_API const char* swan_engine_build_id(
    const swan_engine_t* engine);
SWAN_ENGINE_API uint64_t swan_engine_capabilities(
    const swan_engine_t* engine);
SWAN_ENGINE_API swan_result_t swan_engine_active_model(
    const swan_engine_t* engine,
    swan_model_t* out_model);
SWAN_ENGINE_API const char* swan_engine_last_error(
    const swan_engine_t* engine);

SWAN_ENGINE_API swan_result_t swan_engine_load_rom(
    swan_engine_t* engine,
    const uint8_t* bytes,
    size_t size,
    swan_rom_info_t* out_info);
SWAN_ENGINE_API swan_result_t swan_engine_unload(swan_engine_t* engine);
SWAN_ENGINE_API swan_result_t swan_engine_reset(swan_engine_t* engine);
SWAN_ENGINE_API swan_result_t swan_engine_set_input(swan_engine_t* engine,
                                                    uint32_t input_mask);
SWAN_ENGINE_API swan_result_t swan_engine_run_frame(swan_engine_t* engine);
SWAN_ENGINE_API swan_result_t swan_engine_video_frame(
    const swan_engine_t* engine,
    swan_video_frame_t* out_frame);
SWAN_ENGINE_API swan_result_t swan_engine_audio_batch(
    const swan_engine_t* engine,
    swan_audio_batch_t* out_audio);
SWAN_ENGINE_API swan_result_t swan_engine_stage_persistence(
    swan_engine_t* engine,
    swan_persistence_kind_t kind,
    const uint8_t* bytes,
    size_t size);
SWAN_ENGINE_API swan_result_t swan_engine_stage_boot_rom(
    swan_engine_t* engine,
    const uint8_t* bytes,
    size_t size);
SWAN_ENGINE_API swan_result_t swan_engine_persistence_size(
    swan_engine_t* engine,
    swan_persistence_kind_t kind,
    size_t* out_size);
SWAN_ENGINE_API swan_result_t swan_engine_read_persistence(
    swan_engine_t* engine,
    swan_persistence_kind_t kind,
    uint8_t* out_bytes,
    size_t capacity,
    size_t* out_size);
SWAN_ENGINE_API swan_result_t swan_engine_memory_size(
    swan_engine_t* engine,
    swan_memory_region_t region,
    size_t* out_size);
SWAN_ENGINE_API swan_result_t swan_engine_read_memory(
    swan_engine_t* engine,
    swan_memory_region_t region,
    uint8_t* out_bytes,
    size_t capacity,
    size_t* out_size);
SWAN_ENGINE_API swan_result_t swan_engine_capture_state(
    swan_engine_t* engine,
    uint8_t* out_bytes,
    size_t capacity,
    size_t* out_size);
SWAN_ENGINE_API swan_result_t swan_engine_restore_state(
    swan_engine_t* engine,
    const uint8_t* bytes,
    size_t size);

#ifdef __cplusplus
}
#endif

#endif
