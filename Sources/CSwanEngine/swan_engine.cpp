#include "swan_engine.h"
#include "swan_engine_backend.hpp"

#ifndef SWAN_ENGINE_BUILD_ID
#define SWAN_ENGINE_BUILD_ID "inspection-stub-swan-abi8"
#endif

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <new>
#include <memory>
#include <limits>
#include <span>
#include <string>
#include <vector>

namespace {

constexpr size_t kFooterSize = 16;
constexpr size_t kBankSize = 64u * 1024u;
constexpr size_t kMinimumCompactSize = 64u * 1024u;
constexpr size_t kMaximumSize = 16u * 1024u * 1024u;

bool is_power_of_two(size_t value) {
  return value != 0 && (value & (value - 1)) == 0;
}

size_t next_power_of_two(size_t value) {
  size_t result = 1;
  while (result < value && result <= kMaximumSize) result <<= 1;
  return result;
}

size_t declared_rom_size(uint8_t code) {
  switch (code) {
    case 0x00: return 128u * 1024u;
    case 0x01: return 256u * 1024u;
    case 0x02: return 512u * 1024u;
    case 0x03: return 1u * 1024u * 1024u;
    case 0x04: return 2u * 1024u * 1024u;
    case 0x05: return 3u * 1024u * 1024u;
    case 0x06: return 4u * 1024u * 1024u;
    case 0x07: return 6u * 1024u * 1024u;
    case 0x08: return 8u * 1024u * 1024u;
    case 0x09: return 16u * 1024u * 1024u;
    default: return 0;
  }
}

bool supported_save_type(uint8_t code) {
  switch (code) {
    case 0x00:
    case 0x01:
    case 0x02:
    case 0x03:
    case 0x04:
    case 0x05:
    case 0x10:
    case 0x20:
    case 0x50:
      return true;
    default:
      return false;
  }
}

void initialize_rom_info(swan_rom_info_t* info) {
  std::memset(info, 0, sizeof(*info));
  info->struct_size = sizeof(*info);
}

swan_result_t inspect_rom(const uint8_t* bytes,
                          size_t size,
                          swan_rom_info_t* info) {
  if (!bytes || !info) return SWAN_RESULT_INVALID_ARGUMENT;
  initialize_rom_info(info);
  if (size < kFooterSize || size > kMaximumSize) {
    return SWAN_RESULT_INVALID_ROM;
  }

  const uint8_t* footer = bytes + size - kFooterSize;
  uint16_t computed = 0;
  for (size_t index = 0; index < size - 2; ++index) {
    computed = static_cast<uint16_t>(computed + bytes[index]);
  }
  const uint16_t stored = static_cast<uint16_t>(
      footer[14] | (static_cast<uint16_t>(footer[15]) << 8));
  const size_t declared = declared_rom_size(footer[10]);
  const bool power_of_two = is_power_of_two(size);
  const size_t aperture = power_of_two ? size : next_power_of_two(size);
  const bool compact_shape = !power_of_two && size >= kMinimumCompactSize &&
                             size % kBankSize == 0 &&
                             aperture <= kMaximumSize;
  const bool declared_matches = declared != 0 &&
                                (declared == size || declared == aperture);
  const bool footer_valid = footer[0] == 0xea &&
                            (footer[5] & 0x0f) == 0 &&
                            footer[7] <= 1 &&
                            supported_save_type(footer[11]) &&
                            (footer[12] & 0x04) != 0 &&
                            footer[13] <= 1 &&
                            stored == computed &&
                            (power_of_two || declared_matches);

  info->file_size = size;
  info->mapped_size = aperture;
  info->stored_checksum = stored;
  info->computed_checksum = computed;
  info->color = footer[7] == 1;
  info->save_type = footer[11];
  info->mapper = footer[13];
  info->rom_size_code = footer[10];
  info->checksum_valid = stored == computed;
  info->footer_valid = footer_valid;
  info->compact_layout = !power_of_two;
  info->has_rtc = footer[13] == 1;

  if (!power_of_two && (!compact_shape || !footer_valid)) {
    return SWAN_RESULT_INVALID_ROM;
  }
  return SWAN_RESULT_OK;
}

}  // namespace

struct swan_engine {
  swan_engine_config_t config{};
  std::unique_ptr<SwanEngineBackend> backend;
  swan_rom_info_t rom_info{};
  swan_model_t active_model = SWAN_MODEL_AUTOMATIC;
  bool loaded = false;
  std::vector<uint8_t> state_cache;
  std::string last_error;
};

namespace {

bool valid_model(swan_model_t model) {
  return model >= SWAN_MODEL_AUTOMATIC &&
         model <= SWAN_MODEL_POCKET_CHALLENGE_V2;
}

swan_model_t resolved_model(const swan_engine_config_t& config,
                            const swan_rom_info_t& info) {
  if (config.preferred_model != SWAN_MODEL_AUTOMATIC) {
    return config.preferred_model;
  }
  return info.color ? SWAN_MODEL_WONDERSWAN_COLOR
                    : SWAN_MODEL_WONDERSWAN;
}

swan_result_t finish_backend_call(swan_engine_t* engine,
                                  swan_result_t result,
                                  std::string&& error) {
  if (result == SWAN_RESULT_OK) {
    engine->last_error.clear();
  } else if (!error.empty()) {
    engine->last_error = std::move(error);
  } else {
    engine->last_error = swan_result_message(result);
  }
  return result;
}

}  // namespace

extern "C" {

const char* swan_result_message(swan_result_t result) {
  switch (result) {
    case SWAN_RESULT_OK: return "ok";
    case SWAN_RESULT_INVALID_ARGUMENT: return "invalid argument";
    case SWAN_RESULT_ABI_MISMATCH: return "engine ABI mismatch";
    case SWAN_RESULT_INVALID_ROM: return "invalid or unsupported WonderSwan ROM";
    case SWAN_RESULT_IO_ERROR: return "input/output error";
    case SWAN_RESULT_BACKEND_UNAVAILABLE:
      return "live ares backend is unavailable in this build";
    case SWAN_RESULT_NOT_LOADED: return "no game is loaded";
    case SWAN_RESULT_UNSUPPORTED: return "operation is unsupported";
    case SWAN_RESULT_INTERNAL_ERROR: return "internal engine error";
    case SWAN_RESULT_SOURCE_RANGE_OVERFLOW:
      return "display source exceeded the exact cartridge-range bound";
  }
  return "unknown engine result";
}

swan_result_t swan_inspect_rom(const uint8_t* bytes,
                               size_t size,
                               swan_rom_info_t* out_info) {
  return inspect_rom(bytes, size, out_info);
}

swan_engine_t* swan_engine_create(const swan_engine_config_t* config) {
  if (config && (config->struct_size < sizeof(swan_engine_config_t) ||
                 config->abi_version != SWAN_ENGINE_ABI_VERSION)) {
    return nullptr;
  }
  if (config && !valid_model(config->preferred_model)) return nullptr;
  if (config && config->rtc_mode != SWAN_RTC_MODE_WALL_CLOCK &&
      config->rtc_mode != SWAN_RTC_MODE_DETERMINISTIC) {
    return nullptr;
  }
  if (config && config->rtc_mode == SWAN_RTC_MODE_DETERMINISTIC &&
      (config->rtc_seed_unix_seconds == 0 ||
       config->rtc_seed_unix_seconds >
           static_cast<uint64_t>(std::numeric_limits<int64_t>::max()))) {
    return nullptr;
  }
  auto* engine = new (std::nothrow) swan_engine;
  if (!engine) return nullptr;
  engine->config.struct_size = sizeof(swan_engine_config_t);
  engine->config.abi_version = SWAN_ENGINE_ABI_VERSION;
  engine->config.preferred_model = SWAN_MODEL_AUTOMATIC;
  engine->config.output_sample_rate = 48'000;
  engine->config.rtc_mode = SWAN_RTC_MODE_WALL_CLOCK;
  engine->config.reserved = 0;
  engine->config.rtc_seed_unix_seconds = 0;
  if (config) engine->config = *config;
  try {
    engine->backend = create_swan_engine_backend(engine->config);
  } catch (...) {
    delete engine;
    return nullptr;
  }
  if (!engine->backend) {
    delete engine;
    return nullptr;
  }
  return engine;
}

void swan_engine_destroy(swan_engine_t* engine) {
  delete engine;
}

uint32_t swan_engine_abi_version(const swan_engine_t* engine) {
  return engine ? SWAN_ENGINE_ABI_VERSION : 0;
}

const char* swan_engine_backend_name(const swan_engine_t* engine) {
  return engine && engine->backend ? engine->backend->name() : "unavailable";
}

const char* swan_engine_build_id(const swan_engine_t* engine) {
  return engine && engine->backend ? SWAN_ENGINE_BUILD_ID : "unavailable";
}

uint64_t swan_engine_capabilities(const swan_engine_t* engine) {
  return engine && engine->backend ? engine->backend->capabilities() : 0;
}

swan_result_t swan_engine_active_model(const swan_engine_t* engine,
                                       swan_model_t* out_model) {
  if (!engine || !out_model) return SWAN_RESULT_INVALID_ARGUMENT;
  *out_model = SWAN_MODEL_AUTOMATIC;
  if (!engine->loaded) return SWAN_RESULT_NOT_LOADED;
  *out_model = engine->active_model;
  return SWAN_RESULT_OK;
}

const char* swan_engine_last_error(const swan_engine_t* engine) {
  if (!engine) return "engine is null";
  return engine->last_error.empty() ? "" : engine->last_error.c_str();
}

swan_result_t swan_engine_load_rom(swan_engine_t* engine,
                                   const uint8_t* bytes,
                                   size_t size,
                                   swan_rom_info_t* out_info) {
  if (!engine || !bytes) return SWAN_RESULT_INVALID_ARGUMENT;
  swan_rom_info_t inspected{};
  const swan_result_t result = inspect_rom(bytes, size, &inspected);
  if (result != SWAN_RESULT_OK) {
    engine->last_error = swan_result_message(result);
    return result;
  }
  engine->loaded = false;
  engine->active_model = SWAN_MODEL_AUTOMATIC;
  engine->state_cache.clear();
  initialize_rom_info(&engine->rom_info);
  std::string error;
  const auto backend_result = engine->backend->load(
      std::span<const uint8_t>(bytes, size), inspected, error);
  if (backend_result != SWAN_RESULT_OK) {
    return finish_backend_call(engine, backend_result, std::move(error));
  }
  engine->rom_info = inspected;
  engine->active_model = resolved_model(engine->config, inspected);
  engine->loaded = true;
  engine->last_error.clear();
  if (out_info) *out_info = inspected;
  return SWAN_RESULT_OK;
}

swan_result_t swan_engine_unload(swan_engine_t* engine) {
  if (!engine) return SWAN_RESULT_INVALID_ARGUMENT;
  std::string error;
  const auto result = engine->backend->unload(error);
  if (result != SWAN_RESULT_OK) {
    return finish_backend_call(engine, result, std::move(error));
  }
  initialize_rom_info(&engine->rom_info);
  engine->active_model = SWAN_MODEL_AUTOMATIC;
  engine->loaded = false;
  engine->state_cache.clear();
  engine->last_error.clear();
  return SWAN_RESULT_OK;
}

swan_result_t swan_engine_reset(swan_engine_t* engine) {
  if (!engine) return SWAN_RESULT_INVALID_ARGUMENT;
  if (!engine->loaded) return SWAN_RESULT_NOT_LOADED;
  std::string error;
  return finish_backend_call(engine, engine->backend->reset(error),
                             std::move(error));
}

swan_result_t swan_engine_set_input(swan_engine_t* engine,
                                    uint32_t input_mask) {
  if (!engine) return SWAN_RESULT_INVALID_ARGUMENT;
  std::string error;
  return finish_backend_call(engine,
                             engine->backend->set_input(input_mask, error),
                             std::move(error));
}

swan_result_t swan_engine_run_frame(swan_engine_t* engine) {
  if (!engine) return SWAN_RESULT_INVALID_ARGUMENT;
  if (!engine->loaded) return SWAN_RESULT_NOT_LOADED;
  std::string error;
  return finish_backend_call(engine, engine->backend->run_frame(error),
                             std::move(error));
}

swan_result_t swan_engine_video_frame(const swan_engine_t* engine,
                                      swan_video_frame_t* out_frame) {
  if (!engine || !out_frame) return SWAN_RESULT_INVALID_ARGUMENT;
  std::memset(out_frame, 0, sizeof(*out_frame));
  out_frame->struct_size = sizeof(*out_frame);
  if (!engine->loaded) return SWAN_RESULT_NOT_LOADED;
  std::string error;
  const auto result = engine->backend->video_frame(*out_frame, error);
  return finish_backend_call(const_cast<swan_engine_t*>(engine), result,
                             std::move(error));
}

swan_result_t swan_engine_audio_batch(const swan_engine_t* engine,
                                      swan_audio_batch_t* out_audio) {
  if (!engine || !out_audio) return SWAN_RESULT_INVALID_ARGUMENT;
  std::memset(out_audio, 0, sizeof(*out_audio));
  out_audio->struct_size = sizeof(*out_audio);
  if (!engine->loaded) return SWAN_RESULT_NOT_LOADED;
  std::string error;
  const auto result = engine->backend->audio_batch(*out_audio, error);
  return finish_backend_call(const_cast<swan_engine_t*>(engine), result,
                             std::move(error));
}

swan_result_t swan_engine_stage_persistence(swan_engine_t* engine,
                                            swan_persistence_kind_t kind,
                                            const uint8_t* bytes,
                                            size_t size) {
  if (!engine || (!bytes && size != 0)) return SWAN_RESULT_INVALID_ARGUMENT;
  std::string error;
  const auto data = size ? std::span<const uint8_t>(bytes, size)
                         : std::span<const uint8_t>();
  return finish_backend_call(
      engine, engine->backend->stage_persistence(kind, data, error),
      std::move(error));
}

swan_result_t swan_engine_persistence_size(swan_engine_t* engine,
                                           swan_persistence_kind_t kind,
                                           size_t* out_size) {
  if (!engine || !out_size) return SWAN_RESULT_INVALID_ARGUMENT;
  *out_size = 0;
  std::string error;
  return finish_backend_call(
      engine, engine->backend->persistence_size(kind, *out_size, error),
      std::move(error));
}

swan_result_t swan_engine_read_persistence(swan_engine_t* engine,
                                           swan_persistence_kind_t kind,
                                           uint8_t* out_bytes,
                                           size_t capacity,
                                           size_t* out_size) {
  if (!engine || !out_size || (!out_bytes && capacity != 0)) {
    return SWAN_RESULT_INVALID_ARGUMENT;
  }
  *out_size = 0;
  std::string error;
  const auto output = capacity ? std::span<uint8_t>(out_bytes, capacity)
                               : std::span<uint8_t>();
  return finish_backend_call(
      engine, engine->backend->read_persistence(kind, output, *out_size, error),
      std::move(error));
}

swan_result_t swan_engine_memory_size(swan_engine_t* engine,
                                      swan_memory_region_t region,
                                      size_t* out_size) {
  if (!engine || !out_size) return SWAN_RESULT_INVALID_ARGUMENT;
  *out_size = 0;
  std::string error;
  return finish_backend_call(
      engine, engine->backend->memory_size(region, *out_size, error),
      std::move(error));
}

swan_result_t swan_engine_read_memory(swan_engine_t* engine,
                                      swan_memory_region_t region,
                                      uint8_t* out_bytes,
                                      size_t capacity,
                                      size_t* out_size) {
  if (!engine || !out_size || (!out_bytes && capacity != 0)) {
    return SWAN_RESULT_INVALID_ARGUMENT;
  }
  *out_size = 0;
  std::string error;
  const auto output = capacity ? std::span<uint8_t>(out_bytes, capacity)
                               : std::span<uint8_t>();
  return finish_backend_call(
      engine, engine->backend->read_memory(region, output, *out_size, error),
      std::move(error));
}

swan_result_t swan_engine_capture_state(swan_engine_t* engine,
                                        uint8_t* out_bytes,
                                        size_t capacity,
                                        size_t* out_size) {
  if (!engine || !out_size || (!out_bytes && capacity != 0)) {
    return SWAN_RESULT_INVALID_ARGUMENT;
  }
  if (!engine->loaded) return SWAN_RESULT_NOT_LOADED;

  std::string error;
  if (engine->state_cache.empty()) {
    const auto result = engine->backend->capture_state(engine->state_cache, error);
    if (result != SWAN_RESULT_OK) {
      return finish_backend_call(engine, result, std::move(error));
    }
  }

  *out_size = engine->state_cache.size();
  if (!out_bytes && capacity == 0) {
    engine->last_error.clear();
    return SWAN_RESULT_OK;
  }
  if (capacity < engine->state_cache.size()) {
    engine->last_error = "save-state output buffer is too small";
    return SWAN_RESULT_INVALID_ARGUMENT;
  }
  std::memcpy(out_bytes, engine->state_cache.data(), engine->state_cache.size());
  engine->state_cache.clear();
  engine->last_error.clear();
  return SWAN_RESULT_OK;
}

swan_result_t swan_engine_restore_state(swan_engine_t* engine,
                                        const uint8_t* bytes,
                                        size_t size) {
  if (!engine || !bytes || size == 0) return SWAN_RESULT_INVALID_ARGUMENT;
  if (!engine->loaded) return SWAN_RESULT_NOT_LOADED;
  engine->state_cache.clear();
  std::string error;
  return finish_backend_call(
      engine,
      engine->backend->restore_state(std::span<const uint8_t>(bytes, size), error),
      std::move(error));
}

swan_result_t swan_engine_display_owner_probe(
    swan_engine_t* engine,
    const swan_display_rectangle_t* rectangle,
    swan_display_owner_sample_t* out_samples,
    size_t capacity,
    size_t* out_count) {
  if (!engine || !rectangle || !out_count ||
      (!out_samples && capacity != 0) ||
      rectangle->struct_size < sizeof(swan_display_rectangle_t) ||
      rectangle->width == 0 || rectangle->height == 0) {
    return SWAN_RESULT_INVALID_ARGUMENT;
  }
  if (!engine->loaded) return SWAN_RESULT_NOT_LOADED;
  const size_t width = rectangle->width;
  const size_t height = rectangle->height;
  if (height > 4096u / width) return SWAN_RESULT_INVALID_ARGUMENT;
  const size_t expected = width * height;
  *out_count = 0;
  if (out_samples && capacity < expected) {
    engine->last_error = "display-provenance output buffer is too small";
    return SWAN_RESULT_INVALID_ARGUMENT;
  }
  std::string error;
  const auto output = out_samples
      ? std::span<swan_display_owner_sample_t>(out_samples, capacity)
      : std::span<swan_display_owner_sample_t>();
  return finish_backend_call(
      engine,
      engine->backend->display_owner_probe(
          *rectangle, output, *out_count, error),
      std::move(error));
}

swan_result_t swan_engine_display_source_probe(
    swan_engine_t* engine,
    const swan_display_rectangle_t* rectangle,
    const swan_display_source_probe_options_t* options,
    swan_display_source_trace_t* out_traces,
    size_t capacity,
    size_t* out_count) {
  if (!engine || !rectangle || !options || !out_count ||
      (!out_traces && capacity != 0) ||
      rectangle->struct_size < sizeof(swan_display_rectangle_t) ||
      options->struct_size < sizeof(swan_display_source_probe_options_t) ||
      options->selected_component_mask == 0 ||
      (options->selected_component_mask &
       ~SWAN_DISPLAY_SOURCE_COMPONENT_MASK_ALL) != 0 ||
      rectangle->width == 0 || rectangle->height == 0) {
    return SWAN_RESULT_INVALID_ARGUMENT;
  }
  if (!engine->loaded) return SWAN_RESULT_NOT_LOADED;
  const size_t width = rectangle->width;
  const size_t height = rectangle->height;
  if (height > 4096u / width) return SWAN_RESULT_INVALID_ARGUMENT;
  *out_count = 0;
  std::string error;
  const auto output = out_traces
      ? std::span<swan_display_source_trace_t>(out_traces, capacity)
      : std::span<swan_display_source_trace_t>();
  return finish_backend_call(
      engine,
      engine->backend->display_source_probe(
          *rectangle, options->selected_component_mask,
          output, *out_count, error),
      std::move(error));
}

}  // extern "C"
