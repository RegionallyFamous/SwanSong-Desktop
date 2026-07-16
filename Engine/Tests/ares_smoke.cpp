#include "swan_engine.h"

#include <cstdio>
#include <cstring>
#include <fstream>
#include <iterator>
#include <vector>

int main(int argc, char** argv) {
  constexpr uint64_t kDeterministicRTCSeed = 946'684'800ull;
  swan_engine_config_t config{};
  config.struct_size = sizeof(config);
  config.abi_version = SWAN_ENGINE_ABI_VERSION;
  config.preferred_model = SWAN_MODEL_AUTOMATIC;
  config.output_sample_rate = 48'000;
  config.rtc_mode = SWAN_RTC_MODE_DETERMINISTIC;
  config.rtc_seed_unix_seconds = kDeterministicRTCSeed;

  swan_engine_t* engine = swan_engine_create(&config);
  if (!engine) {
    std::fputs("could not create SwanAresEngine\n", stderr);
    return 1;
  }

  if (argc == 2 && std::strcmp(argv[1], "--build-id") == 0) {
    const char* build_id = swan_engine_build_id(engine);
    if (!build_id || !build_id[0]) {
      std::fputs("engine did not expose a build ID\n", stderr);
      swan_engine_destroy(engine);
      return 1;
    }
    std::puts(build_id);
    swan_engine_destroy(engine);
    return 0;
  }

  const bool backend_ok = std::strcmp(swan_engine_backend_name(engine), "ares") == 0;
  const uint64_t capabilities = swan_engine_capabilities(engine);
  const bool execution_ok = (capabilities & SWAN_CAPABILITY_EXECUTION) != 0;
  const bool audio_ok = (capabilities & SWAN_CAPABILITY_AUDIO) != 0;

  if (!backend_ok || !execution_ok || !audio_ok) {
    std::fputs("ares backend did not advertise the expected live capabilities\n", stderr);
    swan_engine_destroy(engine);
    return 1;
  }

  if (argc > 1) {
    std::ifstream input(argv[1], std::ios::binary);
    std::vector<uint8_t> rom((std::istreambuf_iterator<char>(input)),
                             std::istreambuf_iterator<char>());
    if (rom.empty()) {
      std::fputs("could not read smoke-test ROM\n", stderr);
      swan_engine_destroy(engine);
      return 1;
    }

    const bool color_rom = rom.size() >= 16 && rom[rom.size() - 9] == 1;
    std::vector<uint8_t> staged_console(color_rom ? 2048u : 128u, 0);
    staged_console[0] = 0x5a;
    auto result = swan_engine_stage_persistence(
        engine, SWAN_PERSISTENCE_CONSOLE_EEPROM,
        staged_console.data(), staged_console.size());
    if (result != SWAN_RESULT_OK) {
      std::fputs("could not stage console EEPROM\n", stderr);
      swan_engine_destroy(engine);
      return 1;
    }

    swan_rom_info_t info{};
    result = swan_engine_load_rom(engine, rom.data(), rom.size(), &info);
    if (result != SWAN_RESULT_OK) {
      std::fprintf(stderr, "ROM load failed: %s (%s)\n",
                   swan_result_message(result), swan_engine_last_error(engine));
      swan_engine_destroy(engine);
      return 1;
    }

    uint64_t previous_frame = 0;
    uint32_t frame_width = 0;
    uint32_t frame_height = 0;
    uint64_t video_hash = 1469598103934665603ull;
    for (int index = 0; index < 3; ++index) {
      result = swan_engine_run_frame(engine);
      if (result != SWAN_RESULT_OK) {
        std::fprintf(stderr, "frame execution failed: %s (%s)\n",
                     swan_result_message(result), swan_engine_last_error(engine));
        swan_engine_destroy(engine);
        return 1;
      }

      swan_video_frame_t frame{};
      result = swan_engine_video_frame(engine, &frame);
      if (result != SWAN_RESULT_OK || !frame.pixels || frame.width == 0 ||
          frame.height == 0 || frame.frame_number <= previous_frame) {
        std::fputs("ares did not expose a new video frame\n", stderr);
        swan_engine_destroy(engine);
        return 1;
      }
      previous_frame = frame.frame_number;
      frame_width = frame.width;
      frame_height = frame.height;
      video_hash = 1469598103934665603ull;
      for (size_t offset = 0; offset < frame.byte_count; ++offset) {
        video_hash ^= frame.pixels[offset];
        video_hash *= 1099511628211ull;
      }
    }

    size_t state_size = 0;
    result = swan_engine_capture_state(engine, nullptr, 0, &state_size);
    std::vector<uint8_t> state(state_size);
    size_t captured_size = 0;
    if (result == SWAN_RESULT_OK) {
      result = swan_engine_capture_state(
          engine, state.data(), state.size(), &captured_size);
    }
    if (result != SWAN_RESULT_OK || captured_size != state.size() ||
        state.size() < 532) {
      std::fputs("ares did not produce a versioned save state\n", stderr);
      swan_engine_destroy(engine);
      return 1;
    }

    auto run_and_hash = [&]() -> uint64_t {
      if (swan_engine_run_frame(engine) != SWAN_RESULT_OK) return 0;
      swan_video_frame_t frame{};
      if (swan_engine_video_frame(engine, &frame) != SWAN_RESULT_OK) return 0;
      uint64_t hash = 1469598103934665603ull;
      // The second post-restore frame must reproduce both the native game
      // raster and ares' 13-pixel hardware-indicator rail. The first frame is
      // intentionally primed below because ares' threaded screen owns a
      // double-buffered presentation surface that is not part of save state.
      for (uint32_t row = 0; row < frame.height; ++row) {
        for (uint32_t byte = 0; byte < frame.width * 4; ++byte) {
          hash ^= frame.pixels[static_cast<size_t>(row) * frame.stride_bytes + byte];
          hash *= 1099511628211ull;
        }
      }
      return hash;
    };

    (void)run_and_hash();
    const uint64_t expected_replay = run_and_hash();
    result = swan_engine_restore_state(engine, state.data(), state.size());
    if (result == SWAN_RESULT_OK) (void)run_and_hash();
    const uint64_t actual_replay = result == SWAN_RESULT_OK ? run_and_hash() : 0;
    if (!expected_replay || actual_replay != expected_replay) {
      std::fprintf(stderr,
                   "save-state replay was not deterministic: expected=%016llx actual=%016llx\n",
                   static_cast<unsigned long long>(expected_replay),
                   static_cast<unsigned long long>(actual_replay));
      swan_engine_destroy(engine);
      return 1;
    }

    swan_audio_batch_t audio{};
    result = swan_engine_audio_batch(engine, &audio);
    if (result != SWAN_RESULT_OK || audio.channels != 2 ||
        audio.sample_rate != 48'000) {
      std::fputs("ares did not expose its normalized audio stream\n", stderr);
      swan_engine_destroy(engine);
      return 1;
    }

    size_t persistence_size = 0;
    result = swan_engine_persistence_size(
        engine, SWAN_PERSISTENCE_CONSOLE_EEPROM, &persistence_size);
    std::vector<uint8_t> persisted(persistence_size);
    size_t persisted_size = 0;
    if (result == SWAN_RESULT_OK) {
      result = swan_engine_read_persistence(
          engine, SWAN_PERSISTENCE_CONSOLE_EEPROM,
          persisted.data(), persisted.size(), &persisted_size);
    }
    if (result != SWAN_RESULT_OK || persisted_size != staged_console.size() ||
        persisted.empty() || persisted[0] != 0x5a) {
      std::fputs("console EEPROM persistence did not round trip\n", stderr);
      swan_engine_destroy(engine);
      return 1;
    }

    if (info.has_rtc) {
      size_t rtc_size = 0;
      result = swan_engine_persistence_size(
          engine, SWAN_PERSISTENCE_RTC, &rtc_size);
      std::vector<uint8_t> rtc(rtc_size);
      size_t captured_rtc_size = 0;
      if (result == SWAN_RESULT_OK) {
        result = swan_engine_read_persistence(
            engine, SWAN_PERSISTENCE_RTC,
            rtc.data(), rtc.size(), &captured_rtc_size);
      }
      uint64_t rtc_timestamp = 0;
      if (rtc.size() == 18) {
        for (size_t index = 0; index < 8; ++index) {
          rtc_timestamp |= static_cast<uint64_t>(rtc[8 + index]) << (index * 8);
        }
      }
      if (result != SWAN_RESULT_OK || captured_rtc_size != 18 ||
          rtc_timestamp != kDeterministicRTCSeed) {
        std::fputs("deterministic RTC seed did not survive persistence\n", stderr);
        swan_engine_destroy(engine);
        return 1;
      }
    }
    std::printf(
        "PASS ares executed and replayed state at %ux%u with %zu audio frames; video=%016llx\n",
        frame_width, frame_height, audio.frame_count,
        static_cast<unsigned long long>(video_hash));
  } else {
    std::puts("PASS pinned WonderSwan-only ares backend linked");
  }

  swan_engine_destroy(engine);
  return 0;
}
