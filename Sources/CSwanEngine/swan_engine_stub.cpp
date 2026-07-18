#include "swan_engine_backend.hpp"

#if !defined(SWAN_ENABLE_ARES)

#include <vector>

namespace {

class StubBackend final : public SwanEngineBackend {
 public:
  const char* name() const override { return "inspection-only fallback"; }
  uint64_t capabilities() const override {
    return SWAN_CAPABILITY_ROM_INSPECTION;
  }

  swan_result_t load(std::span<const uint8_t> rom,
                     const swan_rom_info_t&,
                     std::string& error) override {
    try {
      rom_.assign(rom.begin(), rom.end());
    } catch (...) {
      error = "could not retain ROM data";
      return SWAN_RESULT_INTERNAL_ERROR;
    }
    error.clear();
    return SWAN_RESULT_OK;
  }

  swan_result_t unload(std::string& error) override {
    rom_.clear();
    input_mask_ = 0;
    error.clear();
    return SWAN_RESULT_OK;
  }

  swan_result_t reset(std::string& error) override {
    return unavailable(error);
  }

  swan_result_t set_input(uint32_t input_mask,
                          std::string& error) override {
    input_mask_ = input_mask;
    error.clear();
    return SWAN_RESULT_OK;
  }

  swan_result_t run_frame(std::string& error) override {
    return unavailable(error);
  }

  swan_result_t video_frame(swan_video_frame_t&,
                            std::string& error) const override {
    return unavailable(error);
  }

  swan_result_t audio_batch(swan_audio_batch_t&,
                            std::string& error) const override {
    return unavailable(error);
  }

  swan_result_t stage_persistence(swan_persistence_kind_t,
                                  std::span<const uint8_t>,
                                  std::string& error) override {
    error = "persistence requires the live ares backend";
    return SWAN_RESULT_UNSUPPORTED;
  }

  swan_result_t persistence_size(swan_persistence_kind_t,
                                 size_t&,
                                 std::string& error) override {
    error = "persistence requires the live ares backend";
    return SWAN_RESULT_UNSUPPORTED;
  }

  swan_result_t read_persistence(swan_persistence_kind_t,
                                 std::span<uint8_t>,
                                 size_t&,
                                 std::string& error) override {
    error = "persistence requires the live ares backend";
    return SWAN_RESULT_UNSUPPORTED;
  }

  swan_result_t memory_size(swan_memory_region_t,
                            size_t&,
                            std::string& error) override {
    error = "memory capture requires the live ares backend";
    return SWAN_RESULT_UNSUPPORTED;
  }

  swan_result_t read_memory(swan_memory_region_t,
                            std::span<uint8_t>,
                            size_t&,
                            std::string& error) override {
    error = "memory capture requires the live ares backend";
    return SWAN_RESULT_UNSUPPORTED;
  }

  swan_result_t capture_state(std::vector<uint8_t>&,
                              std::string& error) override {
    error = "save states require the live ares backend";
    return SWAN_RESULT_UNSUPPORTED;
  }

  swan_result_t restore_state(std::span<const uint8_t>,
                              std::string& error) override {
    error = "save states require the live ares backend";
    return SWAN_RESULT_UNSUPPORTED;
  }

  swan_result_t display_owner_probe(
      const swan_display_rectangle_t&,
      std::span<swan_display_owner_sample_t>,
      size_t& count,
      std::string& error) const override {
    count = 0;
    error = "display provenance requires the live ares backend";
    return SWAN_RESULT_UNSUPPORTED;
  }

  swan_result_t display_source_probe(
      const swan_display_rectangle_t&,
      uint32_t,
      std::span<swan_display_source_trace_t>,
      size_t& count,
      std::string& error) const override {
    count = 0;
    error = "upstream display-source provenance requires the live ares backend";
    return SWAN_RESULT_UNSUPPORTED;
  }

 private:
  swan_result_t unavailable(std::string& error) const {
    if (rom_.empty()) return SWAN_RESULT_NOT_LOADED;
    error = "live ares backend is unavailable in this build";
    return SWAN_RESULT_BACKEND_UNAVAILABLE;
  }

  std::vector<uint8_t> rom_;
  uint32_t input_mask_ = 0;
};

}  // namespace

std::unique_ptr<SwanEngineBackend> create_swan_engine_backend(
    const swan_engine_config_t&) {
  return std::make_unique<StubBackend>();
}

#endif
