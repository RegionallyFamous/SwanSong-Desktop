#pragma once

#include "swan_engine.h"

#include <cstdint>
#include <memory>
#include <span>
#include <string>
#include <vector>

class SwanEngineBackend {
 public:
  virtual ~SwanEngineBackend() = default;

  virtual const char* name() const = 0;
  virtual uint64_t capabilities() const = 0;
  virtual swan_result_t load(std::span<const uint8_t> rom,
                             const swan_rom_info_t& info,
                             std::string& error) = 0;
  virtual swan_result_t unload(std::string& error) = 0;
  virtual swan_result_t reset(std::string& error) = 0;
  virtual swan_result_t set_input(uint32_t input_mask,
                                  std::string& error) = 0;
  virtual swan_result_t run_frame(std::string& error) = 0;
  virtual swan_result_t video_frame(swan_video_frame_t& frame,
                                    std::string& error) const = 0;
  virtual swan_result_t audio_batch(swan_audio_batch_t& audio,
                                    std::string& error) const = 0;
  virtual swan_result_t stage_persistence(swan_persistence_kind_t kind,
                                          std::span<const uint8_t> bytes,
                                          std::string& error) = 0;
  virtual swan_result_t stage_boot_rom(std::span<const uint8_t> bytes,
                                      std::string& error) = 0;
  virtual swan_result_t persistence_size(swan_persistence_kind_t kind,
                                         size_t& size,
                                         std::string& error) = 0;
  virtual swan_result_t read_persistence(swan_persistence_kind_t kind,
                                         std::span<uint8_t> bytes,
                                         size_t& size,
                                         std::string& error) = 0;
  virtual swan_result_t memory_size(swan_memory_region_t region,
                                    size_t& size,
                                    std::string& error) = 0;
  virtual swan_result_t read_memory(swan_memory_region_t region,
                                    std::span<uint8_t> bytes,
                                    size_t& size,
                                    std::string& error) = 0;
  virtual swan_result_t capture_state(std::vector<uint8_t>& state,
                                      std::string& error) = 0;
  virtual swan_result_t restore_state(std::span<const uint8_t> state,
                                      std::string& error) = 0;
};

std::unique_ptr<SwanEngineBackend> create_swan_engine_backend(
    const swan_engine_config_t& config);
