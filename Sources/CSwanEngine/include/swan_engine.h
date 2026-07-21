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

#define SWAN_ENGINE_ABI_VERSION 10u

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
  SWAN_RESULT_SOURCE_RANGE_OVERFLOW = 9,
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
  SWAN_CAPABILITY_DISPLAY_PROVENANCE = 1ull << 8,
  SWAN_CAPABILITY_DISPLAY_SOURCE_PROVENANCE = 1ull << 9,
  SWAN_CAPABILITY_DISPLAY_SOURCE_COMPONENT_SELECTION = 1ull << 10,
  SWAN_CAPABILITY_EXECUTED_SOURCE_READ_CONTEXT = 1ull << 11,
  SWAN_CAPABILITY_DISPLAY_SPRITE_ATTRIBUTE_PROVENANCE = 1ull << 12,
  SWAN_CAPABILITY_CONSUMED_PREFETCH_PROVENANCE = 1ull << 13,
};

typedef enum swan_display_layer {
  SWAN_DISPLAY_LAYER_BACKDROP = 0,
  SWAN_DISPLAY_LAYER_SCREEN_1 = 1,
  SWAN_DISPLAY_LAYER_SCREEN_2 = 2,
  SWAN_DISPLAY_LAYER_SPRITE = 3,
} swan_display_layer_t;

typedef enum swan_display_source_kind {
  SWAN_DISPLAY_SOURCE_NONE = 0,
  SWAN_DISPLAY_SOURCE_TILEMAP = 1,
  SWAN_DISPLAY_SOURCE_SPRITE = 2,
} swan_display_source_kind_t;

typedef struct swan_display_rectangle {
  uint32_t struct_size;
  uint16_t x;
  uint16_t y;
  uint16_t width;
  uint16_t height;
} swan_display_rectangle_t;

typedef struct swan_display_owner_sample {
  uint32_t struct_size;
  uint16_t x;
  uint16_t y;
  swan_display_layer_t layer;
  swan_display_source_kind_t source_kind;
  uint16_t cell_address;
  uint16_t tile_index;
  uint32_t cell_attributes;
  uint16_t raster_address;
  uint8_t raster_byte_count;
  uint8_t palette_index;
  uint8_t palette_color;
  uint8_t palette_byte_count;
  uint32_t palette_address;
  uint32_t cell_writer_pc;
  uint32_t raster_writer_pc;
  uint32_t palette_writer_pc;
  uint16_t oam_address;
  uint8_t oam_byte_count;
  uint8_t reserved;
  uint32_t oam_writer_pc;
} swan_display_owner_sample_t;

typedef enum swan_display_source_component {
  SWAN_DISPLAY_SOURCE_COMPONENT_MAP_CELL = 1,
  SWAN_DISPLAY_SOURCE_COMPONENT_RASTER = 2,
  SWAN_DISPLAY_SOURCE_COMPONENT_PALETTE = 3,
  SWAN_DISPLAY_SOURCE_COMPONENT_SPRITE_ATTRIBUTE = 4,
} swan_display_source_component_t;

enum {
  SWAN_DISPLAY_SOURCE_COMPONENT_MASK_MAP_CELL = 1u << 0,
  SWAN_DISPLAY_SOURCE_COMPONENT_MASK_RASTER = 1u << 1,
  SWAN_DISPLAY_SOURCE_COMPONENT_MASK_PALETTE = 1u << 2,
  SWAN_DISPLAY_SOURCE_COMPONENT_MASK_SPRITE_ATTRIBUTE = 1u << 3,
  SWAN_DISPLAY_SOURCE_COMPONENT_MASK_ALL =
      SWAN_DISPLAY_SOURCE_COMPONENT_MASK_MAP_CELL |
      SWAN_DISPLAY_SOURCE_COMPONENT_MASK_RASTER |
      SWAN_DISPLAY_SOURCE_COMPONENT_MASK_PALETTE |
      SWAN_DISPLAY_SOURCE_COMPONENT_MASK_SPRITE_ATTRIBUTE,
};

/**
 * ABI-9 selection applies only to the source ranges seeded by pixels inside
 * the rectangle. Outside-consumer discovery remains component-complete for
 * every display component that shares any selected cartridge range.
 */
typedef struct swan_display_source_probe_options {
  uint32_t struct_size;
  uint32_t selected_component_mask;
} swan_display_source_probe_options_t;

typedef enum swan_display_source_scope {
  SWAN_DISPLAY_SOURCE_SCOPE_SELECTED = 1,
  SWAN_DISPLAY_SOURCE_SCOPE_OUTSIDE_CONSUMER = 2,
} swan_display_source_scope_t;

typedef enum swan_display_source_conservative_reason {
  SWAN_DISPLAY_SOURCE_CONSERVATIVE_NONE = 0,
  SWAN_DISPLAY_SOURCE_CONSERVATIVE_UNCLASSIFIED_INSTRUCTION = 1,
} swan_display_source_conservative_reason_t;

enum {
  /*
   * The source set is exact, never a collapsed superset. cartridge_length ==
   * 0 denotes an exact runtime-generated source.
   */
  SWAN_DISPLAY_SOURCE_FLAG_EXACT = 1u << 0,
  /* At least one CPU dataflow instruction separates cartridge and display RAM. */
  SWAN_DISPLAY_SOURCE_FLAG_TRANSFORMED = 1u << 1,
  /* Some dependency was not cartridge/IRAM/I/O and could not be traced. */
  SWAN_DISPLAY_SOURCE_FLAG_UNKNOWN_DEPENDENCY = 1u << 2,
  /* A fixed per-byte source set overflowed. No affected range is called exact. */
  SWAN_DISPLAY_SOURCE_FLAG_RANGE_OVERFLOW = 1u << 3,
  /* The observed instruction was traced conservatively, so the set may over-include. */
  SWAN_DISPLAY_SOURCE_FLAG_CONSERVATIVE_DATAFLOW = 1u << 4,
};

enum {
  /* The lineage includes the exact CPU instruction and mapper resolution that read it. */
  SWAN_DISPLAY_SOURCE_READ_CONTEXT_EXECUTED = 1u << 0,
};

typedef uint16_t swan_display_source_read_initiator_t;
enum {
  SWAN_DISPLAY_SOURCE_READ_INITIATOR_NONE = 0,
  SWAN_DISPLAY_SOURCE_READ_INITIATOR_CPU = 1,
  SWAN_DISPLAY_SOURCE_READ_INITIATOR_GENERAL_DMA = 2,
};

/**
 * One bounded upstream dataflow edge retained privately by Translation Lab.
 * cartridge_offset + cartridge_length is a half-open range in the original
 * project ROM file (not the rounded mapper aperture). source_address is an
 * emulated RAM/I/O address and must never be returned through public MCP.
 * Executed-read context records an explicit initiator. CPU reads retain the
 * caller's code segment/offset and exact data operand segment/offset;
 * immediate_caller_or_general_dma_source_operand is the immediate caller.
 * General DMA reads leave the CPU-only fields zero and use that same fixed ABI
 * slot for the exact 20-bit DMA source operand. resolved_cartridge_operand is
 * the mapper-aperture operand before leading-padding removal. All remain private.
 * Conservative diagnostics retain the first instruction that forced an
 * over-inclusive dependency set; such traces never carry the exact flag.
 */
typedef struct swan_display_source_trace {
  uint32_t struct_size;
  uint16_t x;
  uint16_t y;
  swan_display_source_scope_t scope;
  swan_display_source_component_t component;
  uint32_t source_address;
  uint16_t source_byte_count;
  uint16_t minimum_instruction_hops;
  uint16_t maximum_instruction_hops;
  swan_display_source_read_initiator_t read_context_initiator;
  uint32_t cartridge_offset;
  uint32_t cartridge_length;
  uint32_t flags;
  uint32_t read_context_flags;
  uint32_t immediate_caller_or_general_dma_source_operand;
  uint16_t caller_segment;
  uint16_t caller_offset;
  uint16_t operand_segment;
  uint16_t operand_offset;
  uint16_t mapper_window;
  uint16_t mapper_bank;
  uint32_t resolved_cartridge_operand;
  swan_display_source_conservative_reason_t conservative_reason;
  uint32_t conservative_origin;
  uint16_t conservative_origin_segment;
  uint16_t conservative_origin_offset;
} swan_display_source_trace_t;

enum {
  /* The context was sealed at the terminal opcode boundary. */
  SWAN_FETCH_CONTEXT_FLAG_SEALED = 1u << 0,
  /* Every consumed byte belongs to one exact contiguous cartridge run. */
  SWAN_FETCH_CONTEXT_FLAG_EXACT_CARTRIDGE_RUN = 1u << 1,
  /* The structural context ID and canonical digest are bijective. */
  SWAN_FETCH_CONTEXT_FLAG_BIJECTIVE_IDENTITY = 1u << 2,
  /* A separately qualified pinned decoder must still validate the seed. */
  SWAN_FETCH_CONTEXT_FLAG_PYPCODE_CHECK_REQUIRED = 1u << 3,
  /* ABI 10 does not export operand/post-transform semantics. */
  SWAN_FETCH_CONTEXT_FLAG_EXACT_DATA_INCOMPLETE = 1u << 4,
};

/**
 * ABI-10 source trace. The ABI-9 prefix remains field-for-field compatible;
 * execution_context_id names one atomic sealed execution row when nonzero.
 */
typedef struct swan_display_source_trace_v2 {
  uint32_t struct_size;
  uint16_t x;
  uint16_t y;
  swan_display_source_scope_t scope;
  swan_display_source_component_t component;
  uint32_t source_address;
  uint16_t source_byte_count;
  uint16_t minimum_instruction_hops;
  uint16_t maximum_instruction_hops;
  swan_display_source_read_initiator_t read_context_initiator;
  uint32_t cartridge_offset;
  uint32_t cartridge_length;
  uint32_t flags;
  uint32_t read_context_flags;
  uint32_t immediate_caller_or_general_dma_source_operand;
  uint16_t caller_segment;
  uint16_t caller_offset;
  uint16_t operand_segment;
  uint16_t operand_offset;
  uint16_t mapper_window;
  uint16_t mapper_bank;
  uint32_t resolved_cartridge_operand;
  swan_display_source_conservative_reason_t conservative_reason;
  uint32_t conservative_origin;
  uint16_t conservative_origin_segment;
  uint16_t conservative_origin_offset;
  uint64_t execution_context_id;
  uint32_t fetch_context_flags;
  uint32_t reserved_v2;
} swan_display_source_trace_v2_t;

/** One interned logical-instruction consumed-prefetch context. */
typedef struct swan_instruction_fetch_context {
  uint32_t struct_size;
  uint64_t id;
  uint64_t structural_id;
  uint32_t byte_start;
  uint32_t byte_count;
  uint32_t flags;
  uint8_t terminal_opcode;
  uint8_t continuing;
  uint16_t reserved;
  uint32_t logical_start_physical;
  uint16_t logical_start_segment;
  uint16_t logical_start_offset;
  uint8_t canonical_digest[32];
} swan_instruction_fetch_context_t;

/** One consumed byte, retaining its exact pinned-engine prefetch origin. */
typedef struct swan_instruction_fetch_byte {
  uint32_t struct_size;
  uint64_t context_id;
  uint32_t ordinal;
  uint64_t token;
  uint32_t source_kind;
  uint32_t physical_address;
  uint32_t resolved_operand;
  uint32_t mapper_window;
  uint32_t mapper_bank;
  uint32_t event_context;
  uint32_t segment;
  uint32_t offset;
  uint32_t data;
} swan_instruction_fetch_byte_t;

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
SWAN_ENGINE_API swan_result_t swan_engine_display_owner_probe(
    swan_engine_t* engine,
    const swan_display_rectangle_t* rectangle,
    swan_display_owner_sample_t* out_samples,
    size_t capacity,
    size_t* out_count);
SWAN_ENGINE_API swan_result_t swan_engine_display_source_probe(
    swan_engine_t* engine,
    const swan_display_rectangle_t* rectangle,
    const swan_display_source_probe_options_t* options,
    swan_display_source_trace_t* out_traces,
    size_t capacity,
    size_t* out_count);
SWAN_ENGINE_API swan_result_t swan_engine_display_source_probe_v2(
    swan_engine_t* engine,
    const swan_display_rectangle_t* rectangle,
    const swan_display_source_probe_options_t* options,
    swan_display_source_trace_v2_t* out_traces,
    size_t trace_capacity,
    size_t* out_trace_count,
    swan_instruction_fetch_context_t* out_contexts,
    size_t context_capacity,
    size_t* out_context_count,
    swan_instruction_fetch_byte_t* out_bytes,
    size_t byte_capacity,
    size_t* out_byte_count);

#ifdef __cplusplus
}
#endif

#endif
