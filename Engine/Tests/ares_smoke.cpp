#include "swan_engine.h"

#include <algorithm>
#include <array>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <iterator>
#include <optional>
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
  const bool provenance_ok =
      (capabilities & SWAN_CAPABILITY_DISPLAY_PROVENANCE) != 0;
  const bool source_provenance_ok =
      (capabilities & SWAN_CAPABILITY_DISPLAY_SOURCE_PROVENANCE) != 0;
  const bool source_selection_ok =
      (capabilities & SWAN_CAPABILITY_DISPLAY_SOURCE_COMPONENT_SELECTION) != 0;
  const bool source_read_context_ok =
      (capabilities & SWAN_CAPABILITY_EXECUTED_SOURCE_READ_CONTEXT) != 0;
  const bool sprite_attribute_provenance_ok =
      (capabilities &
       SWAN_CAPABILITY_DISPLAY_SPRITE_ATTRIBUTE_PROVENANCE) != 0;
  const bool consumed_prefetch_provenance_ok =
      (capabilities & SWAN_CAPABILITY_CONSUMED_PREFETCH_PROVENANCE) != 0;

  if (!backend_ok || !execution_ok || !audio_ok || !provenance_ok ||
      !source_provenance_ok || !source_selection_ok || !source_read_context_ok ||
      !sprite_attribute_provenance_ok || !consumed_prefetch_provenance_ok) {
    std::fputs("ares backend did not advertise the expected live capabilities\n", stderr);
    swan_engine_destroy(engine);
    return 1;
  }

  const bool provenance_fixture =
      argc == 4 && std::strcmp(argv[1], "--provenance-fixture") == 0;
  const bool mono_palette_fixture =
      argc == 3 && std::strcmp(argv[1], "--mono-palette-fixture") == 0;
  const bool mapper_window_fixture =
      argc == 3 &&
      std::strcmp(argv[1], "--mapper-window-owner-matrix") == 0;
  const bool static_analysis_seed_v2_fixture =
      argc == 3 &&
      std::strcmp(argv[1], "--static-analysis-seed-v2-fixture") == 0;
  const bool dma_provenance_fixture =
      argc == 3 &&
      std::strcmp(argv[1], "--dma-provenance-fixture") == 0;
  const bool input_frame_fixture =
      argc == 3 && std::strcmp(argv[1], "--input-frame-fixture") == 0;
  const char* rom_path = provenance_fixture || mono_palette_fixture ||
          mapper_window_fixture || static_analysis_seed_v2_fixture ||
          dma_provenance_fixture || input_frame_fixture
      ? argv[2] : (argc > 1 ? argv[1] : nullptr);
  const uint8_t expected_raster_bytes = provenance_fixture
      ? static_cast<uint8_t>(std::strcmp(argv[3], "packed") == 0 ? 1 : 4)
      : 0;
  if (provenance_fixture &&
      std::strcmp(argv[3], "packed") != 0 &&
      std::strcmp(argv[3], "planar") != 0) {
    std::fputs("provenance fixture mode must be planar or packed\n", stderr);
    swan_engine_destroy(engine);
    return 1;
  }

  if (rom_path) {
    std::ifstream input(rom_path, std::ios::binary);
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

    size_t staged_readback_size = 0;
    result = swan_engine_persistence_size(
        engine, SWAN_PERSISTENCE_CONSOLE_EEPROM, &staged_readback_size);
    std::vector<uint8_t> staged_readback(staged_readback_size);
    size_t staged_readback_written = 0;
    if (result == SWAN_RESULT_OK) {
      result = swan_engine_read_persistence(
          engine, SWAN_PERSISTENCE_CONSOLE_EEPROM,
          staged_readback.data(), staged_readback.size(),
          &staged_readback_written);
    }
    if (result != SWAN_RESULT_OK ||
        staged_readback_written != staged_console.size() ||
        staged_readback != staged_console) {
      std::fputs("staged console EEPROM was not loaded exactly\n", stderr);
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

    if (dma_provenance_fixture) {
      if (frame_width != 237 || frame_height != 144) {
        std::fputs("general-DMA fixture exposed the wrong native frame\n", stderr);
        swan_engine_destroy(engine);
        return 1;
      }

      swan_video_frame_t dma_frame{};
      result = swan_engine_video_frame(engine, &dma_frame);
      const auto pixel_at = [&](uint16_t x, uint16_t y) {
        std::array<uint8_t, 4> pixel{};
        const size_t offset = static_cast<size_t>(y) * dma_frame.stride_bytes +
            static_cast<size_t>(x) * pixel.size();
        std::copy_n(dma_frame.pixels + offset, pixel.size(), pixel.begin());
        return pixel;
      };
      if (result != SWAN_RESULT_OK || !dma_frame.pixels ||
          dma_frame.stride_bytes < dma_frame.width * 4 ||
          pixel_at(8, 8) == pixel_at(9, 8)) {
        std::fputs("general-DMA fixture lost its isolated visible pixel\n", stderr);
        swan_engine_destroy(engine);
        return 1;
      }

      swan_display_rectangle_t dma_rectangle{};
      dma_rectangle.struct_size = sizeof(dma_rectangle);
      dma_rectangle.x = 8;
      dma_rectangle.y = 8;
      dma_rectangle.width = 1;
      dma_rectangle.height = 1;
      swan_display_owner_sample_t dma_owner{};
      size_t dma_owner_count = 0;
      result = swan_engine_display_owner_probe(
          engine, &dma_rectangle, &dma_owner, 1, &dma_owner_count);
      if (result != SWAN_RESULT_OK || dma_owner_count != 1 ||
          dma_owner.struct_size != sizeof(dma_owner) ||
          dma_owner.layer != SWAN_DISPLAY_LAYER_SCREEN_1 ||
          dma_owner.source_kind != SWAN_DISPLAY_SOURCE_TILEMAP ||
          dma_owner.cell_address != 0x1842 || dma_owner.tile_index != 1 ||
          dma_owner.cell_attributes != 1 ||
          dma_owner.raster_address != 0x4020 ||
          dma_owner.raster_byte_count != 4 ||
          dma_owner.raster_writer_pc == UINT32_MAX) {
        std::fputs("general-DMA fixture owner was not exact\n", stderr);
        swan_engine_destroy(engine);
        return 1;
      }

      swan_display_source_probe_options_t dma_options{};
      dma_options.struct_size = sizeof(dma_options);
      dma_options.selected_component_mask =
          SWAN_DISPLAY_SOURCE_COMPONENT_MASK_RASTER;
      size_t dma_source_count = 0;
      result = swan_engine_display_source_probe(
          engine, &dma_rectangle, &dma_options,
          nullptr, 0, &dma_source_count);
      std::vector<swan_display_source_trace_t> dma_sources(dma_source_count);
      size_t dma_source_written = 0;
      if (result == SWAN_RESULT_OK) {
        result = swan_engine_display_source_probe(
            engine, &dma_rectangle, &dma_options,
            dma_sources.data(), dma_sources.size(), &dma_source_written);
      }
      bool exact_dma = result == SWAN_RESULT_OK && dma_source_count == 4 &&
          dma_source_written == dma_sources.size();
      std::array<uint32_t, 4> cartridge_offsets{};
      std::array<uint32_t, 4> dma_operands{};
      for (size_t index = 0; exact_dma && index < dma_sources.size(); ++index) {
        const auto& source = dma_sources[index];
        exact_dma = source.struct_size == sizeof(source) &&
            source.x == 8 && source.y == 8 &&
            source.scope == SWAN_DISPLAY_SOURCE_SCOPE_SELECTED &&
            source.component == SWAN_DISPLAY_SOURCE_COMPONENT_RASTER &&
            source.source_address == 0x4020 &&
            source.source_byte_count == 4 &&
            source.cartridge_length == 1 &&
            source.flags == SWAN_DISPLAY_SOURCE_FLAG_EXACT &&
            source.read_context_flags ==
                SWAN_DISPLAY_SOURCE_READ_CONTEXT_EXECUTED &&
            source.read_context_initiator ==
                SWAN_DISPLAY_SOURCE_READ_INITIATOR_GENERAL_DMA &&
            source.minimum_instruction_hops == 0 &&
            source.maximum_instruction_hops == 0 &&
            source.immediate_caller_or_general_dma_source_operand != 0 &&
            source.caller_segment == 0 && source.caller_offset == 0 &&
            source.operand_segment == 0 && source.operand_offset == 0 &&
            source.mapper_window >= 2 && source.mapper_window <= 15 &&
            source.cartridge_offset == source.resolved_cartridge_operand &&
            source.cartridge_offset < rom.size() &&
            source.conservative_reason ==
                SWAN_DISPLAY_SOURCE_CONSERVATIVE_NONE;
        cartridge_offsets[index] = source.cartridge_offset;
        dma_operands[index] =
            source.immediate_caller_or_general_dma_source_operand;
      }
      std::sort(cartridge_offsets.begin(), cartridge_offsets.end());
      std::sort(dma_operands.begin(), dma_operands.end());
      for (size_t index = 1; exact_dma && index < cartridge_offsets.size();
           ++index) {
        exact_dma = cartridge_offsets[index] == cartridge_offsets[0] + index &&
            dma_operands[index] == dma_operands[0] + index;
      }
      constexpr std::array<uint8_t, 4> kExpectedSource = {0x80, 0, 0, 0};
      if (exact_dma) {
        exact_dma = cartridge_offsets[0] <= rom.size() - kExpectedSource.size() &&
            std::equal(kExpectedSource.begin(), kExpectedSource.end(),
                       rom.begin() + cartridge_offsets[0]);
      }
      if (!exact_dma) {
        std::fprintf(
            stderr,
            "general-DMA provenance mismatch result=%u count=%zu/%zu first=%08x operand=%05x\n",
            result, dma_source_count, dma_source_written,
            cartridge_offsets[0], dma_operands[0]);
        for (const auto& source : dma_sources) {
          std::fprintf(
              stderr,
              "trace scope=%u component=%u address=%05x/%u range=%08x/%u flags=%x read=%x initiator=%u hops=%u-%u dma=%05x caller=%04x:%04x operand=%04x:%04x window=%u bank=%04x resolved=%08x conservative=%u\n",
              source.scope, source.component, source.source_address,
              source.source_byte_count, source.cartridge_offset,
              source.cartridge_length, source.flags,
              source.read_context_flags, source.read_context_initiator,
              source.minimum_instruction_hops, source.maximum_instruction_hops,
              source.immediate_caller_or_general_dma_source_operand,
              source.caller_segment, source.caller_offset,
              source.operand_segment, source.operand_offset,
              source.mapper_window, source.mapper_bank,
              source.resolved_cartridge_operand, source.conservative_reason);
        }
        swan_engine_destroy(engine);
        return 1;
      }

      std::printf(
          "PASS general-DMA source lineage exact=4 initiator=dma source=%08x operand=%05x\n",
          cartridge_offsets[0], dma_operands[0]);
      swan_engine_destroy(engine);
      return 0;
    }

    if (input_frame_fixture) {
      constexpr size_t kTraceAddress = 0x1000;
      constexpr uint16_t kTraceMagic = 0x5349;
      constexpr uint16_t kTraceReady = 0xa55a;
      const auto read_word = [](const std::vector<uint8_t>& bytes,
                                size_t address) -> uint16_t {
        return static_cast<uint16_t>(bytes[address]) |
               static_cast<uint16_t>(bytes[address + 1]) << 8;
      };
      const auto read_memory = [&]() -> std::optional<std::vector<uint8_t>> {
        size_t size = 0;
        auto memory_result = swan_engine_memory_size(
            engine, SWAN_MEMORY_INTERNAL_RAM, &size);
        std::vector<uint8_t> bytes(size);
        size_t written = 0;
        if (memory_result == SWAN_RESULT_OK) {
          memory_result = swan_engine_read_memory(
              engine, SWAN_MEMORY_INTERNAL_RAM,
              bytes.data(), bytes.size(), &written);
        }
        if (memory_result != SWAN_RESULT_OK || written != bytes.size()) {
          return std::nullopt;
        }
        return bytes;
      };

      const auto before = read_memory();
      if (!before || before->size() < kTraceAddress + 12 ||
          read_word(*before, kTraceAddress) != kTraceMagic ||
          read_word(*before, kTraceAddress + 2) != kTraceReady) {
        std::fputs("input-frame fixture did not reach its ready boundary\n", stderr);
        swan_engine_destroy(engine);
        return 1;
      }
      const uint16_t first_sample = read_word(*before, kTraceAddress + 4);
      const std::array<uint16_t, 10> expected = {
          0x0004, 0x0000, 0x0010, 0x0000, 0x0004,
          0x0000, 0x0400, 0x0000, 0x0004, 0x0000,
      };
      if (first_sample + expected.size() > 16) {
        std::fputs("input-frame fixture trace did not have room for the exercise\n", stderr);
        swan_engine_destroy(engine);
        return 1;
      }

      struct InputSpan {
        uint32_t mask;
        uint16_t frames;
      };
      constexpr std::array<InputSpan, 11> input_spans = {{
          {0, 180},
          {SWAN_INPUT_A, 8},
          {0, 112},
          {SWAN_INPUT_X1, 6},
          {0, 24},
          {SWAN_INPUT_A, 6},
          {0, 24},
          {SWAN_INPUT_Y3, 6},
          {0, 24},
          {SWAN_INPUT_A, 8},
          {0, 32},
      }};
      size_t observed_transitions = 0;
      uint32_t previous_mask = 0;
      for (const auto& span : input_spans) {
        for (uint16_t frame_index = 0; frame_index < span.frames;
             ++frame_index) {
          result = swan_engine_set_input(engine, span.mask);
          if (result == SWAN_RESULT_OK) result = swan_engine_run_frame(engine);
          if (result != SWAN_RESULT_OK) {
            std::fputs("spaced input exercise could not run\n", stderr);
            swan_engine_destroy(engine);
            return 1;
          }
          if (frame_index == 0 && span.mask != previous_mask) {
            const auto immediate = read_memory();
            const uint16_t immediate_count = immediate
                ? read_word(*immediate, kTraceAddress + 4) : 0xffff;
            const uint16_t immediate_sample = immediate
                ? read_word(*immediate, kTraceAddress + 6 +
                    (first_sample + observed_transitions) * 2) : 0xffff;
            if (!immediate || observed_transitions >= expected.size() ||
                immediate_count != first_sample + observed_transitions + 1 ||
                immediate_sample != expected[observed_transitions]) {
              std::fprintf(
                  stderr,
                  "input transition was not visible on its scheduled frame: index=%zu count=%u sample=%04x\n",
                  observed_transitions, immediate_count, immediate_sample);
              swan_engine_destroy(engine);
              return 1;
            }
            ++observed_transitions;
          }
        }
        previous_mask = span.mask;
      }

      const auto after = read_memory();
      const uint16_t final_sample = after
          ? read_word(*after, kTraceAddress + 4) : 0xffff;
      bool exact = after && final_sample == first_sample + expected.size();
      for (size_t index = 0; exact && index < expected.size(); ++index) {
        exact = read_word(
            *after, kTraceAddress + 6 + (first_sample + index) * 2) ==
            expected[index];
      }
      if (!exact) {
        std::fprintf(
            stderr,
            "spaced input was stale: samples=%u..%u expected repeated A across X1 and Y3 changes\n",
            first_sample, final_sample);
        swan_engine_destroy(engine);
        return 1;
      }
      result = swan_engine_set_input(engine, 0);
      if (result != SWAN_RESULT_OK) {
        std::fputs("could not release input after frame exercise\n", stderr);
        swan_engine_destroy(engine);
        return 1;
      }
      std::puts("PASS scheduled input transitions reached their exact game frames");
      swan_engine_destroy(engine);
      return 0;
    }

    swan_display_rectangle_t rectangle{};
    rectangle.struct_size = sizeof(rectangle);
    rectangle.width = 2;
    rectangle.height = 2;
    std::array<swan_display_owner_sample_t, 4> owners{};
    size_t owner_count = 0;
    result = swan_engine_display_owner_probe(
        engine, &rectangle, owners.data(), owners.size(), &owner_count);
    if (result != SWAN_RESULT_OK || owner_count != owners.size()) {
      std::fputs("ares did not return bounded display provenance\n", stderr);
      swan_engine_destroy(engine);
      return 1;
    }
    for (const auto& owner : owners) {
      if (owner.struct_size != sizeof(owner) || owner.x >= 2 || owner.y >= 2 ||
          owner.layer > SWAN_DISPLAY_LAYER_SPRITE ||
          owner.source_kind > SWAN_DISPLAY_SOURCE_SPRITE) {
        std::fputs("ares returned invalid display provenance\n", stderr);
        swan_engine_destroy(engine);
        return 1;
      }
    }

    size_t source_trace_count = 0;
    swan_display_source_probe_options_t source_options{};
    source_options.struct_size = sizeof(source_options);
    source_options.selected_component_mask = SWAN_DISPLAY_SOURCE_COMPONENT_MASK_ALL;
    result = swan_engine_display_source_probe(
        engine, &rectangle, &source_options, nullptr, 0, &source_trace_count);
    if (result != SWAN_RESULT_OK || source_trace_count > 262'144u) {
      std::fputs("ares did not return bounded upstream source provenance\n", stderr);
      swan_engine_destroy(engine);
      return 1;
    }
    std::vector<swan_display_source_trace_t> source_traces(source_trace_count);
    size_t written_source_traces = 0;
    result = swan_engine_display_source_probe(
        engine, &rectangle, &source_options,
        source_traces.data(), source_traces.size(),
        &written_source_traces);
    if (result != SWAN_RESULT_OK || written_source_traces != source_trace_count) {
      std::fputs("ares returned incomplete upstream source provenance\n", stderr);
      swan_engine_destroy(engine);
      return 1;
    }
    for (const auto& trace : source_traces) {
      if (trace.struct_size != sizeof(trace) || trace.x >= frame_width ||
          trace.y >= frame_height ||
          trace.scope < SWAN_DISPLAY_SOURCE_SCOPE_SELECTED ||
          trace.scope > SWAN_DISPLAY_SOURCE_SCOPE_OUTSIDE_CONSUMER ||
          trace.component < SWAN_DISPLAY_SOURCE_COMPONENT_MAP_CELL ||
          trace.component > SWAN_DISPLAY_SOURCE_COMPONENT_SPRITE_ATTRIBUTE ||
          (trace.conservative_reason == SWAN_DISPLAY_SOURCE_CONSERVATIVE_NONE) !=
              ((trace.flags &
                SWAN_DISPLAY_SOURCE_FLAG_CONSERVATIVE_DATAFLOW) == 0) ||
          (trace.conservative_reason != SWAN_DISPLAY_SOURCE_CONSERVATIVE_NONE &&
           (trace.flags & SWAN_DISPLAY_SOURCE_FLAG_EXACT) != 0) ||
          (trace.conservative_reason != SWAN_DISPLAY_SOURCE_CONSERVATIVE_NONE &&
           trace.conservative_origin !=
               ((((uint32_t)trace.conservative_origin_segment << 4) +
                 trace.conservative_origin_offset) & 0xfffffu)) ||
          trace.cartridge_length > rom.size() ||
          trace.cartridge_offset > rom.size() - trace.cartridge_length) {
        std::fputs("ares returned invalid upstream source provenance\n", stderr);
        swan_engine_destroy(engine);
        return 1;
      }
    }

    size_t static_seed_trace_count = 0;
    size_t static_seed_context_count = 0;
    size_t static_seed_byte_count = 0;

    if (mapper_window_fixture) {
      constexpr size_t kExpectedROMSize = 2u * 1024u * 1024u;
      constexpr std::array<uint32_t, 4> kActiveOffsets = {
          0x028000, 0x038000, 0x148000, 0x1f8000,
      };
      constexpr std::array<uint32_t, 4> kInactiveOffsets = {
          0x068000, 0x078000, 0x048000, 0x0f8000,
      };
      constexpr std::array<std::array<uint8_t, 4>, 4> kTokens = {{
          {{0x80, 0x00, 0x00, 0x00}},
          {{0x00, 0x80, 0x00, 0x00}},
          {{0x00, 0x00, 0x80, 0x00}},
          {{0x00, 0x00, 0x00, 0x80}},
      }};
      bool exact_rom_layout = rom.size() == kExpectedROMSize;
      for (size_t index = 0; exact_rom_layout && index < kTokens.size();
           ++index) {
        exact_rom_layout = std::equal(
            kTokens[index].begin(), kTokens[index].end(),
            rom.begin() + kActiveOffsets[index]) &&
            std::equal(
                kTokens[index].begin(), kTokens[index].end(),
                rom.begin() + kInactiveOffsets[index]);
      }
      if (!exact_rom_layout) {
        std::fputs("mapper-window fixture did not retain its exact ROM layout\n",
                   stderr);
        swan_engine_destroy(engine);
        return 1;
      }

      if (frame_width != 237 || frame_height != 144) {
        std::fputs("mapper-window fixture exposed the wrong native frame\n",
                   stderr);
        swan_engine_destroy(engine);
        return 1;
      }

      size_t iram_size = 0;
      result = swan_engine_memory_size(
          engine, SWAN_MEMORY_INTERNAL_RAM, &iram_size);
      std::vector<uint8_t> iram(iram_size);
      size_t iram_written = 0;
      if (result == SWAN_RESULT_OK) {
        result = swan_engine_read_memory(
            engine, SWAN_MEMORY_INTERNAL_RAM,
            iram.data(), iram.size(), &iram_written);
      }
      if (result != SWAN_RESULT_OK || iram_written != iram.size() ||
          iram.size() <= 0x04f3 || iram[0x04f0] != 0xe6 ||
          iram[0x04f1] != 0xe7 || iram[0x04f2] != 0xfe ||
          iram[0x04f3] != 0xa5) {
        std::fputs("mapper-window fixture did not reach its inactive-bank boundary\n",
                   stderr);
        swan_engine_destroy(engine);
        return 1;
      }

      struct ExpectedMapperPixel {
        uint16_t x;
        uint16_t cell_address;
        uint16_t tile_index;
        uint16_t raster_address;
        uint8_t palette_color;
        uint32_t palette_address;
        uint32_t cartridge_offset;
        uint16_t caller_offset;
        uint16_t operand_segment;
        uint16_t mapper_window;
        uint16_t mapper_bank;
        uint32_t resolved_cartridge_operand;
      };
      constexpr std::array<ExpectedMapperPixel, 4> expected = {{
          // Keep the exact 16-bit register value in provenance. The fixture
          // changes only the low byte, so reset-state 0xff remains in the
          // high byte even though ROM aperture masking makes it ineffective.
          {0, 0x1800, 1, 0x4020, 1, 0xfe02, 0x028000,
           0x043f, 0x2000, 2, 0xffe2, 0x028000},
          {8, 0x1802, 2, 0x4040, 2, 0xfe04, 0x038000,
           0x044f, 0x3000, 3, 0xffe3, 0x038000},
          {16, 0x1804, 3, 0x4060, 4, 0xfe08, 0x148000,
           0x045f, 0x4000, 4, 0xffff, 0x148000},
          {24, 0x1806, 4, 0x4080, 8, 0xfe10, 0x1f8000,
           0x046f, 0xf000, 15, 0xffff, 0x1f8000},
      }};

      uint64_t trace_hash = 1469598103934665603ull;
      const auto mix_trace = [&](uint64_t value) {
        for (uint8_t byte = 0; byte < 8; ++byte) {
          trace_hash ^= static_cast<uint8_t>(value & 0xffu);
          trace_hash *= 1099511628211ull;
          value >>= 8;
        }
      };
      std::array<std::array<uint8_t, 4>, 4> selected_pixels{};
      std::array<uint8_t, 4> backdrop_pixel{};

      swan_video_frame_t matrix_frame{};
      result = swan_engine_video_frame(engine, &matrix_frame);
      if (result != SWAN_RESULT_OK || !matrix_frame.pixels ||
          matrix_frame.stride_bytes < matrix_frame.width * 4) {
        std::fputs("mapper-window fixture lost its native frame\n", stderr);
        swan_engine_destroy(engine);
        return 1;
      }
      const auto pixel_at = [&](uint16_t x, uint16_t y) {
        std::array<uint8_t, 4> pixel{};
        const size_t offset = static_cast<size_t>(y) * matrix_frame.stride_bytes +
            static_cast<size_t>(x) * pixel.size();
        std::copy_n(matrix_frame.pixels + offset, pixel.size(), pixel.begin());
        return pixel;
      };

      swan_display_source_probe_options_t raster_options{};
      raster_options.struct_size = sizeof(raster_options);
      raster_options.selected_component_mask =
          SWAN_DISPLAY_SOURCE_COMPONENT_MASK_RASTER;

      for (size_t index = 0; index < expected.size(); ++index) {
        const auto& item = expected[index];
        swan_display_rectangle_t selected_rectangle{};
        selected_rectangle.struct_size = sizeof(selected_rectangle);
        selected_rectangle.x = item.x;
        selected_rectangle.y = 0;
        selected_rectangle.width = 1;
        selected_rectangle.height = 1;

        swan_display_owner_sample_t owner{};
        size_t selected_owner_count = 0;
        result = swan_engine_display_owner_probe(
            engine, &selected_rectangle, &owner, 1, &selected_owner_count);
        if (result != SWAN_RESULT_OK || selected_owner_count != 1 ||
            owner.struct_size != sizeof(owner) || owner.x != item.x ||
            owner.y != 0 || owner.layer != SWAN_DISPLAY_LAYER_SCREEN_1 ||
            owner.source_kind != SWAN_DISPLAY_SOURCE_TILEMAP ||
            owner.cell_address != item.cell_address ||
            owner.tile_index != item.tile_index ||
            owner.cell_attributes != item.tile_index ||
            owner.raster_address != item.raster_address ||
            owner.raster_byte_count != 4 || owner.palette_index != 0 ||
            owner.palette_color != item.palette_color ||
            owner.palette_address != item.palette_address ||
            owner.palette_byte_count != 2 ||
            owner.cell_writer_pc == UINT32_MAX ||
            owner.raster_writer_pc != item.caller_offset + 1u ||
            owner.palette_writer_pc == UINT32_MAX ||
            owner.oam_address != 0xffff || owner.oam_byte_count != 0 ||
            owner.oam_writer_pc != UINT32_MAX) {
          std::fputs("mapper-window fixture owner mismatch\n", stderr);
          swan_engine_destroy(engine);
          return 1;
        }

        size_t source_count = 0;
        result = swan_engine_display_source_probe(
            engine, &selected_rectangle, &raster_options,
            nullptr, 0, &source_count);
        swan_display_source_trace_t source{};
        size_t source_written = 0;
        if (result == SWAN_RESULT_OK && source_count == 1) {
          result = swan_engine_display_source_probe(
              engine, &selected_rectangle, &raster_options,
              &source, 1, &source_written);
        }
        if (result != SWAN_RESULT_OK || source_count != 1 ||
            source_written != 1 || source.struct_size != sizeof(source) ||
            source.x != item.x || source.y != 0 ||
            source.scope != SWAN_DISPLAY_SOURCE_SCOPE_SELECTED ||
            source.component != SWAN_DISPLAY_SOURCE_COMPONENT_RASTER ||
            source.source_address != item.raster_address ||
            source.source_byte_count != 4 ||
            source.cartridge_offset != item.cartridge_offset ||
            source.cartridge_length != 4 ||
            source.flags != (SWAN_DISPLAY_SOURCE_FLAG_EXACT |
                             SWAN_DISPLAY_SOURCE_FLAG_TRANSFORMED) ||
            source.read_context_flags !=
                SWAN_DISPLAY_SOURCE_READ_CONTEXT_EXECUTED ||
            source.read_context_initiator !=
                SWAN_DISPLAY_SOURCE_READ_INITIATOR_CPU ||
            source.minimum_instruction_hops != 1 ||
            source.maximum_instruction_hops != 1 ||
            source.immediate_caller_or_general_dma_source_operand !=
                item.caller_offset ||
            source.caller_segment != 0 ||
            source.caller_offset != item.caller_offset ||
            source.operand_segment != item.operand_segment ||
            source.operand_offset != 0x8000 ||
            source.mapper_window != item.mapper_window ||
            source.mapper_bank != item.mapper_bank ||
            source.resolved_cartridge_operand !=
                item.resolved_cartridge_operand ||
            source.conservative_reason !=
                SWAN_DISPLAY_SOURCE_CONSERVATIVE_NONE) {
          std::fprintf(
              stderr,
              "mapper-window fixture source context mismatch index=%zu count=%zu/%zu result=%u pos=%u,%u scope=%u component=%u address=%05x/%u range=%08x/%u flags=%x read=%x hops=%u-%u caller=%05x:%04x:%04x operand=%04x:%04x window=%u bank=%04x resolved=%08x conservative=%u\n",
              index, source_count, source_written, result, source.x, source.y,
              source.scope, source.component, source.source_address,
              source.source_byte_count, source.cartridge_offset,
              source.cartridge_length, source.flags, source.read_context_flags,
              source.minimum_instruction_hops, source.maximum_instruction_hops,
              source.immediate_caller_or_general_dma_source_operand,
              source.caller_segment,
              source.caller_offset, source.operand_segment,
              source.operand_offset, source.mapper_window, source.mapper_bank,
              source.resolved_cartridge_operand, source.conservative_reason);
          swan_engine_destroy(engine);
          return 1;
        }

        size_t v2_trace_count = 0;
        size_t v2_context_count = 0;
        size_t v2_byte_count = 0;
        result = swan_engine_display_source_probe_v2(
            engine, &selected_rectangle, &raster_options,
            nullptr, 0, &v2_trace_count,
            nullptr, 0, &v2_context_count,
            nullptr, 0, &v2_byte_count);
        swan_display_source_trace_v2_t v2_trace{};
        size_t v2_trace_written = 0;
        size_t v2_context_written = 0;
        size_t v2_byte_written = 0;
        if (result == SWAN_RESULT_OK && v2_trace_count == 1 &&
            v2_context_count == 0 && v2_byte_count == 0) {
          result = swan_engine_display_source_probe_v2(
              engine, &selected_rectangle, &raster_options,
              &v2_trace, 1, &v2_trace_written,
              nullptr, 0, &v2_context_written,
              nullptr, 0, &v2_byte_written);
        }
        if (result != SWAN_RESULT_OK || v2_trace_written != 1 ||
            v2_context_written != 0 || v2_byte_written != 0 ||
            v2_trace.execution_context_id != 0 ||
            v2_trace.fetch_context_flags != 0 ||
            std::memcmp(
                reinterpret_cast<const uint8_t*>(&v2_trace) + 4,
                reinterpret_cast<const uint8_t*>(&source) + 4,
                sizeof(source) - 4) != 0) {
          std::fprintf(
              stderr,
              "ABI10 incorrectly derived caller bytes from an IRAM reader result=%u counts=%zu/%zu/%zu written=%zu/%zu/%zu id=%llu flags=%x\n",
              result, v2_trace_count, v2_context_count, v2_byte_count,
              v2_trace_written, v2_context_written, v2_byte_written,
              static_cast<unsigned long long>(v2_trace.execution_context_id),
              v2_trace.fetch_context_flags);
          swan_engine_destroy(engine);
          return 1;
        }

        mix_trace(source.x);
        mix_trace(source.y);
        mix_trace(source.scope);
        mix_trace(source.component);
        mix_trace(source.source_address);
        mix_trace(source.source_byte_count);
        mix_trace(source.minimum_instruction_hops);
        mix_trace(source.maximum_instruction_hops);
        mix_trace(source.cartridge_offset);
        mix_trace(source.cartridge_length);
        mix_trace(source.flags);
        mix_trace(source.read_context_flags);
        mix_trace(source.read_context_initiator);
        mix_trace(source.immediate_caller_or_general_dma_source_operand);
        mix_trace(source.caller_segment);
        mix_trace(source.caller_offset);
        mix_trace(source.operand_segment);
        mix_trace(source.operand_offset);
        mix_trace(source.mapper_window);
        mix_trace(source.mapper_bank);
        mix_trace(source.resolved_cartridge_operand);
        mix_trace(source.conservative_reason);

        swan_display_rectangle_t transparent_rectangle{};
        transparent_rectangle.struct_size = sizeof(transparent_rectangle);
        transparent_rectangle.x = item.x + 1;
        transparent_rectangle.y = 0;
        transparent_rectangle.width = 1;
        transparent_rectangle.height = 1;
        swan_display_owner_sample_t transparent_owner{};
        size_t transparent_owner_count = 0;
        result = swan_engine_display_owner_probe(
            engine, &transparent_rectangle, &transparent_owner, 1,
            &transparent_owner_count);
        if (result != SWAN_RESULT_OK || transparent_owner_count != 1 ||
            transparent_owner.layer != SWAN_DISPLAY_LAYER_BACKDROP ||
            transparent_owner.source_kind != SWAN_DISPLAY_SOURCE_NONE ||
            transparent_owner.raster_byte_count != 0 ||
            transparent_owner.raster_writer_pc != UINT32_MAX) {
          std::fputs("mapper-window fixture transparency control failed\n",
                     stderr);
          swan_engine_destroy(engine);
          return 1;
        }
        size_t transparent_source_count = 0;
        result = swan_engine_display_source_probe(
            engine, &transparent_rectangle, &raster_options,
            nullptr, 0, &transparent_source_count);
        if (result != SWAN_RESULT_OK || transparent_source_count != 0) {
          std::fputs("mapper-window fixture inactive source control failed\n",
                     stderr);
          swan_engine_destroy(engine);
          return 1;
        }

        selected_pixels[index] = pixel_at(item.x, 0);
        const auto transparent_pixel = pixel_at(item.x + 1, 0);
        if (index == 0) backdrop_pixel = transparent_pixel;
        if (transparent_pixel != backdrop_pixel ||
            selected_pixels[index] == backdrop_pixel) {
          std::fputs("mapper-window fixture pixel contrast failed\n", stderr);
          swan_engine_destroy(engine);
          return 1;
        }
        for (size_t previous = 0; previous < index; ++previous) {
          if (selected_pixels[index] == selected_pixels[previous]) {
            std::fputs("mapper-window fixture visible colors were not distinct\n",
                       stderr);
            swan_engine_destroy(engine);
            return 1;
          }
        }
      }

      std::printf(
          "PASS mapper-window owner matrix selected=4 exact=4 executed=4 inactive=0 controls=2 trace=%016llx video=%016llx\n",
          static_cast<unsigned long long>(trace_hash),
          static_cast<unsigned long long>(video_hash));
      swan_engine_destroy(engine);
      return 0;
    }

    if (static_analysis_seed_v2_fixture) {
      constexpr size_t kExpectedROMSize = 2u * 1024u * 1024u;
      constexpr uint32_t kFetchOffset = 0x028004;
      constexpr uint32_t kRefetchOffset = 0x068004;
      constexpr uint32_t kSourceDecoyOffset = 0x029000;
      constexpr uint32_t kSourceOffset = 0x069000;
      constexpr std::array<uint8_t, 2> kRetainedInstruction = {0xf3, 0xa5};
      constexpr std::array<uint8_t, 2> kRefetchDecoy = {0xf4, 0xa5};
      constexpr std::array<uint8_t, 4> kSourceDecoy = {0, 0, 0, 0};
      constexpr std::array<uint8_t, 4> kVisibleSource = {0x80, 0, 0, 0};
      if (rom.size() != kExpectedROMSize ||
          !std::equal(kRetainedInstruction.begin(), kRetainedInstruction.end(),
                      rom.begin() + kFetchOffset) ||
          !std::equal(kRefetchDecoy.begin(), kRefetchDecoy.end(),
                      rom.begin() + kRefetchOffset) ||
          !std::equal(kSourceDecoy.begin(), kSourceDecoy.end(),
                      rom.begin() + kSourceDecoyOffset) ||
          !std::equal(kVisibleSource.begin(), kVisibleSource.end(),
                      rom.begin() + kSourceOffset)) {
        std::fputs("static-analysis seed-v2 ROM layout was not exact\n", stderr);
        swan_engine_destroy(engine);
        return 1;
      }
      if (frame_width != 237 || frame_height != 144) {
        std::fputs("static-analysis seed-v2 exposed the wrong native frame\n",
                   stderr);
        swan_engine_destroy(engine);
        return 1;
      }

      swan_video_frame_t seed_frame{};
      result = swan_engine_video_frame(engine, &seed_frame);
      const auto frame_pixel = [&](uint16_t x, uint16_t y) {
        std::array<uint8_t, 4> pixel{};
        const size_t offset = static_cast<size_t>(y) * seed_frame.stride_bytes +
            static_cast<size_t>(x) * pixel.size();
        std::copy_n(seed_frame.pixels + offset, pixel.size(), pixel.begin());
        return pixel;
      };
      if (result != SWAN_RESULT_OK || !seed_frame.pixels ||
          seed_frame.stride_bytes < seed_frame.width * 4 ||
          frame_pixel(0, 0) == frame_pixel(1, 0)) {
        std::fputs("static-analysis seed-v2 visible pixel was absent\n", stderr);
        swan_engine_destroy(engine);
        return 1;
      }
      const auto seed_backdrop = frame_pixel(1, 0);
      for (uint16_t y = 0; y < 144; ++y) {
        for (uint16_t x = 0; x < 224; ++x) {
          if (x == 0 && y == 0) continue;
          if (frame_pixel(x, y) != seed_backdrop) {
            std::fputs(
                "static-analysis seed-v2 visible delta escaped its rectangle\n",
                stderr);
            swan_engine_destroy(engine);
            return 1;
          }
        }
      }

      swan_display_rectangle_t seed_rectangle{};
      seed_rectangle.struct_size = sizeof(seed_rectangle);
      seed_rectangle.width = 1;
      seed_rectangle.height = 1;
      swan_display_owner_sample_t seed_owner{};
      size_t seed_owner_count = 0;
      result = swan_engine_display_owner_probe(
          engine, &seed_rectangle, &seed_owner, 1, &seed_owner_count);
      if (result != SWAN_RESULT_OK || seed_owner_count != 1 ||
          seed_owner.struct_size != sizeof(seed_owner) ||
          seed_owner.x != 0 || seed_owner.y != 0 ||
          seed_owner.layer != SWAN_DISPLAY_LAYER_SCREEN_1 ||
          seed_owner.source_kind != SWAN_DISPLAY_SOURCE_TILEMAP ||
          seed_owner.cell_address != 0x1800 || seed_owner.tile_index != 1 ||
          seed_owner.cell_attributes != 1 ||
          seed_owner.raster_address != 0x4020 ||
          seed_owner.raster_byte_count != 4 ||
          seed_owner.palette_index != 0 || seed_owner.palette_color != 1 ||
          seed_owner.palette_address != 0xfe02 ||
          seed_owner.palette_byte_count != 2 ||
          seed_owner.cell_writer_pc == UINT32_MAX ||
          seed_owner.raster_writer_pc != 0x028006 ||
          seed_owner.palette_writer_pc == UINT32_MAX ||
          seed_owner.oam_address != 0xffff || seed_owner.oam_byte_count != 0 ||
          seed_owner.oam_writer_pc != UINT32_MAX) {
        std::fputs("static-analysis seed-v2 visible owner was not exact\n", stderr);
        swan_engine_destroy(engine);
        return 1;
      }

      swan_display_source_probe_options_t seed_options{};
      seed_options.struct_size = sizeof(seed_options);
      seed_options.selected_component_mask =
          SWAN_DISPLAY_SOURCE_COMPONENT_MASK_RASTER;
      size_t seed_source_count = 0;
      result = swan_engine_display_source_probe(
          engine, &seed_rectangle, &seed_options,
          nullptr, 0, &seed_source_count);
      std::vector<swan_display_source_trace_t> seed_sources(seed_source_count);
      size_t seed_source_written = 0;
      if (result == SWAN_RESULT_OK) {
        result = swan_engine_display_source_probe(
            engine, &seed_rectangle, &seed_options,
            seed_sources.data(), seed_sources.size(), &seed_source_written);
      }
      if (result != SWAN_RESULT_OK || seed_source_count != 1 ||
          seed_source_written != seed_sources.size()) {
        std::fputs("static-analysis seed-v2 ABI9 source count was not exact\n",
                   stderr);
        swan_engine_destroy(engine);
        return 1;
      }
      const auto& seed_source = seed_sources.front();
      if (seed_source.struct_size != sizeof(seed_source) ||
          seed_source.x != 0 || seed_source.y != 0 ||
          seed_source.scope != SWAN_DISPLAY_SOURCE_SCOPE_SELECTED ||
          seed_source.component != SWAN_DISPLAY_SOURCE_COMPONENT_RASTER ||
          seed_source.source_address != 0x4020 ||
          seed_source.source_byte_count != 4 ||
          seed_source.minimum_instruction_hops != 1 ||
          seed_source.maximum_instruction_hops != 1 ||
          seed_source.cartridge_offset != kSourceOffset ||
          seed_source.cartridge_length != 4 ||
          seed_source.flags != (SWAN_DISPLAY_SOURCE_FLAG_EXACT |
                                SWAN_DISPLAY_SOURCE_FLAG_TRANSFORMED) ||
          seed_source.read_context_flags !=
              SWAN_DISPLAY_SOURCE_READ_CONTEXT_EXECUTED ||
          seed_source.read_context_initiator !=
              SWAN_DISPLAY_SOURCE_READ_INITIATOR_CPU ||
          seed_source.immediate_caller_or_general_dma_source_operand !=
              kFetchOffset + 1u ||
          seed_source.caller_segment != 0x2000 ||
          seed_source.caller_offset != 0x8005 ||
          seed_source.operand_segment != 0x2000 ||
          seed_source.operand_offset != 0x9000 ||
          seed_source.mapper_window != 2 ||
          seed_source.mapper_bank != 0xffe6 ||
          seed_source.resolved_cartridge_operand != kSourceOffset ||
          seed_source.conservative_reason !=
              SWAN_DISPLAY_SOURCE_CONSERVATIVE_NONE) {
        std::fputs("static-analysis seed-v2 ABI9 source fields were not exact\n",
                   stderr);
        swan_engine_destroy(engine);
        return 1;
      }

      result = swan_engine_display_source_probe_v2(
          engine, &seed_rectangle, &seed_options,
          nullptr, 0, &static_seed_trace_count,
          nullptr, 0, &static_seed_context_count,
          nullptr, 0, &static_seed_byte_count);
      if (result != SWAN_RESULT_OK || static_seed_trace_count != 1 ||
          static_seed_context_count != 2 || static_seed_byte_count != 4) {
        std::fputs("static-analysis seed-v2 ABI10 sizing was not exact\n", stderr);
        swan_engine_destroy(engine);
        return 1;
      }

      const auto unchanged = [](const auto& records) {
        const auto* begin = reinterpret_cast<const uint8_t*>(records.data());
        return std::all_of(
            begin, begin + records.size() * sizeof(records.front()),
            [](uint8_t byte) { return byte == 0xa5; });
      };
      for (uint8_t undersized_table = 0; undersized_table < 3;
           ++undersized_table) {
        std::vector<swan_display_source_trace_v2_t> atomic_traces(
            static_seed_trace_count);
        std::vector<swan_instruction_fetch_context_t> atomic_contexts(
            static_seed_context_count);
        std::vector<swan_instruction_fetch_byte_t> atomic_bytes(
            static_seed_byte_count);
        std::memset(atomic_traces.data(), 0xa5,
                    atomic_traces.size() * sizeof(atomic_traces.front()));
        std::memset(atomic_contexts.data(), 0xa5,
                    atomic_contexts.size() * sizeof(atomic_contexts.front()));
        std::memset(atomic_bytes.data(), 0xa5,
                    atomic_bytes.size() * sizeof(atomic_bytes.front()));
        size_t atomic_trace_count = 0;
        size_t atomic_context_count = 0;
        size_t atomic_byte_count = 0;
        const size_t trace_capacity = static_seed_trace_count -
            (undersized_table == 0 ? 1u : 0u);
        const size_t context_capacity = static_seed_context_count -
            (undersized_table == 1 ? 1u : 0u);
        const size_t byte_capacity = static_seed_byte_count -
            (undersized_table == 2 ? 1u : 0u);
        result = swan_engine_display_source_probe_v2(
            engine, &seed_rectangle, &seed_options,
            atomic_traces.data(), trace_capacity, &atomic_trace_count,
            atomic_contexts.data(), context_capacity, &atomic_context_count,
            atomic_bytes.data(), byte_capacity, &atomic_byte_count);
        if (result != SWAN_RESULT_SOURCE_RANGE_OVERFLOW ||
            atomic_trace_count != static_seed_trace_count ||
            atomic_context_count != static_seed_context_count ||
            atomic_byte_count != static_seed_byte_count ||
            !unchanged(atomic_traces) || !unchanged(atomic_contexts) ||
            !unchanged(atomic_bytes)) {
          std::fputs("static-analysis seed-v2 ABI10 output was not atomic\n",
                     stderr);
          swan_engine_destroy(engine);
          return 1;
        }
      }

      std::vector<swan_display_source_trace_v2_t> seed_v2_traces(
          static_seed_trace_count);
      std::vector<swan_instruction_fetch_context_t> seed_contexts(
          static_seed_context_count);
      std::vector<swan_instruction_fetch_byte_t> seed_bytes(
          static_seed_byte_count);
      size_t seed_v2_trace_written = 0;
      size_t seed_context_written = 0;
      size_t seed_byte_written = 0;
      result = swan_engine_display_source_probe_v2(
          engine, &seed_rectangle, &seed_options,
          seed_v2_traces.data(), seed_v2_traces.size(),
          &seed_v2_trace_written,
          seed_contexts.data(), seed_contexts.size(), &seed_context_written,
          seed_bytes.data(), seed_bytes.size(), &seed_byte_written);
      if (result != SWAN_RESULT_OK ||
          seed_v2_trace_written != static_seed_trace_count ||
          seed_context_written != static_seed_context_count ||
          seed_byte_written != static_seed_byte_count) {
        std::fputs("static-analysis seed-v2 ABI10 retrieval was incomplete\n",
                   stderr);
        swan_engine_destroy(engine);
        return 1;
      }
      const auto& seed_v2_trace = seed_v2_traces.front();
      const uint32_t required_fetch_flags =
          SWAN_FETCH_CONTEXT_FLAG_SEALED |
          SWAN_FETCH_CONTEXT_FLAG_EXACT_CARTRIDGE_RUN |
          SWAN_FETCH_CONTEXT_FLAG_BIJECTIVE_IDENTITY |
          SWAN_FETCH_CONTEXT_FLAG_PYPCODE_CHECK_REQUIRED |
          SWAN_FETCH_CONTEXT_FLAG_EXACT_DATA_INCOMPLETE;
      if (seed_v2_trace.struct_size != sizeof(seed_v2_trace) ||
          std::memcmp(
              reinterpret_cast<const uint8_t*>(&seed_v2_trace) + 4,
              reinterpret_cast<const uint8_t*>(&seed_source) + 4,
              sizeof(seed_source) - 4) != 0 ||
          seed_v2_trace.execution_context_id == 0 ||
          seed_v2_trace.execution_context_id != seed_contexts.front().id ||
          seed_v2_trace.fetch_context_flags != seed_contexts.front().flags) {
        std::fputs("static-analysis seed-v2 association was not exact\n", stderr);
        swan_engine_destroy(engine);
        return 1;
      }
      for (size_t context_index = 0; context_index < seed_contexts.size();
           ++context_index) {
        const auto& seed_context = seed_contexts[context_index];
        if (seed_context.struct_size != sizeof(seed_context) ||
            seed_context.id == 0 || seed_context.structural_id == 0 ||
            seed_context.byte_start != context_index * 2 ||
            seed_context.byte_count != 2 ||
            seed_context.flags != required_fetch_flags ||
            seed_context.terminal_opcode != 0xa5 ||
            seed_context.continuing != (context_index == 0 ? 1u : 0u) ||
            seed_context.logical_start_physical != kFetchOffset ||
            seed_context.logical_start_segment != 0x2000 ||
            seed_context.logical_start_offset != 0x8004 ||
            std::all_of(
                std::begin(seed_context.canonical_digest),
                std::end(seed_context.canonical_digest),
                [](uint8_t byte) { return byte == 0; })) {
          std::fputs("static-analysis seed-v2 fetch context was not sealed\n",
                     stderr);
          swan_engine_destroy(engine);
          return 1;
        }
        if (context_index != 0 &&
            (seed_context.id == seed_contexts.front().id ||
             seed_context.structural_id != seed_contexts.front().structural_id ||
             std::memcmp(seed_context.canonical_digest,
                         seed_contexts.front().canonical_digest,
                         sizeof(seed_context.canonical_digest)) != 0)) {
          std::fputs("static-analysis seed-v2 REP contexts diverged\n", stderr);
          swan_engine_destroy(engine);
          return 1;
        }
        for (uint32_t ordinal = 0; ordinal < 2; ++ordinal) {
          const auto& seed_byte = seed_bytes[seed_context.byte_start + ordinal];
          if (seed_byte.struct_size != sizeof(seed_byte) ||
              seed_byte.context_id != seed_context.id ||
              seed_byte.ordinal != ordinal || seed_byte.token == 0 ||
              seed_byte.source_kind != 1 ||
              seed_byte.physical_address != kFetchOffset + ordinal ||
              seed_byte.resolved_operand != kFetchOffset + ordinal ||
              seed_byte.mapper_window != 2 || seed_byte.mapper_bank != 0xffe2 ||
              seed_byte.event_context == 0 || seed_byte.segment != 0x2000 ||
              seed_byte.offset != 0x8004 + ordinal ||
              seed_byte.data != kRetainedInstruction[ordinal] ||
              seed_source.mapper_bank == seed_byte.mapper_bank ||
              seed_source.cartridge_offset ==
                  (seed_byte.resolved_operand &
                   (static_cast<uint32_t>(info.mapped_size) - 1u))) {
            std::fputs("static-analysis seed-v2 consumed byte was not exact\n",
                       stderr);
            swan_engine_destroy(engine);
            return 1;
          }
        }
      }
    }

    if (mono_palette_fixture) {
      if (frame_width != 224 || frame_height != 157) {
        std::fprintf(stderr,
                     "monochrome fixture exposed the wrong native frame: %ux%u\n",
                     frame_width, frame_height);
        swan_engine_destroy(engine);
        return 1;
      }

      swan_display_rectangle_t selected_rectangle{};
      selected_rectangle.struct_size = sizeof(selected_rectangle);
      selected_rectangle.x = 0;
      selected_rectangle.y = 0;
      selected_rectangle.width = 1;
      selected_rectangle.height = 1;
      swan_display_owner_sample_t selected_owner{};
      size_t selected_owner_count = 0;
      result = swan_engine_display_owner_probe(
          engine, &selected_rectangle, &selected_owner, 1,
          &selected_owner_count);
      if (result != SWAN_RESULT_OK || selected_owner_count != 1 ||
          selected_owner.layer != SWAN_DISPLAY_LAYER_SCREEN_1 ||
          selected_owner.source_kind != SWAN_DISPLAY_SOURCE_TILEMAP ||
          selected_owner.cell_address != 0x1800 ||
          selected_owner.tile_index != 0 ||
          selected_owner.cell_attributes != 0 ||
          selected_owner.raster_address != 0x2000 ||
          selected_owner.raster_byte_count != 2 ||
          selected_owner.palette_index != 0 ||
          selected_owner.palette_color != 2 ||
          selected_owner.palette_address != 0x10021 ||
          selected_owner.palette_byte_count != 1 ||
          selected_owner.cell_writer_pc == UINT32_MAX ||
          selected_owner.raster_writer_pc == UINT32_MAX ||
          selected_owner.palette_writer_pc == UINT32_MAX ||
          selected_owner.oam_address != 0xffff ||
          selected_owner.oam_byte_count != 0 ||
          selected_owner.oam_writer_pc != UINT32_MAX) {
        std::fprintf(
            stderr,
            "monochrome owner mismatch layer=%u source=%u cell=%04x/%08x tile=%u raster=%04x/%u palette=%u:%u@%05x/%u writers=%05x/%05x/%05x\n",
            selected_owner.layer, selected_owner.source_kind,
            selected_owner.cell_address, selected_owner.cell_attributes,
            selected_owner.tile_index, selected_owner.raster_address,
            selected_owner.raster_byte_count, selected_owner.palette_index,
            selected_owner.palette_color, selected_owner.palette_address,
            selected_owner.palette_byte_count, selected_owner.cell_writer_pc,
            selected_owner.raster_writer_pc,
            selected_owner.palette_writer_pc);
        swan_engine_destroy(engine);
        return 1;
      }

      swan_display_rectangle_t transparency_rectangle{};
      transparency_rectangle.struct_size = sizeof(transparency_rectangle);
      transparency_rectangle.x = 9;
      transparency_rectangle.y = 0;
      transparency_rectangle.width = 1;
      transparency_rectangle.height = 1;
      swan_display_owner_sample_t transparency_owner{};
      size_t transparency_owner_count = 0;
      result = swan_engine_display_owner_probe(
          engine, &transparency_rectangle, &transparency_owner, 1,
          &transparency_owner_count);
      if (result != SWAN_RESULT_OK || transparency_owner_count != 1 ||
          transparency_owner.layer != SWAN_DISPLAY_LAYER_BACKDROP ||
          transparency_owner.source_kind != SWAN_DISPLAY_SOURCE_NONE ||
          transparency_owner.cell_writer_pc != UINT32_MAX ||
          transparency_owner.raster_byte_count != 0 ||
          transparency_owner.raster_writer_pc != UINT32_MAX ||
          transparency_owner.palette_address != 0x10001 ||
          transparency_owner.palette_byte_count != 1 ||
          transparency_owner.palette_writer_pc == UINT32_MAX) {
        std::fputs("palette-4 color-0 transparency control was not a backdrop\n",
                   stderr);
        swan_engine_destroy(engine);
        return 1;
      }

      swan_display_source_probe_options_t mono_source_options{};
      mono_source_options.struct_size = sizeof(mono_source_options);
      mono_source_options.selected_component_mask =
          SWAN_DISPLAY_SOURCE_COMPONENT_MASK_ALL;
      size_t mono_source_count = 0;
      result = swan_engine_display_source_probe(
          engine, &selected_rectangle, &mono_source_options,
          nullptr, 0, &mono_source_count);
      std::vector<swan_display_source_trace_t> mono_sources(mono_source_count);
      size_t mono_source_written = 0;
      if (result == SWAN_RESULT_OK) {
        result = swan_engine_display_source_probe(
            engine, &selected_rectangle, &mono_source_options,
            mono_sources.data(), mono_sources.size(), &mono_source_written);
      }
      struct ExpectedRuntimeSource {
        swan_display_source_component_t component;
        uint32_t address;
        uint16_t byte_count;
      };
      const std::array<ExpectedRuntimeSource, 3> expected_runtime_sources = {{
          {SWAN_DISPLAY_SOURCE_COMPONENT_MAP_CELL, 0x1800, 2},
          {SWAN_DISPLAY_SOURCE_COMPONENT_RASTER, 0x2000, 2},
          {SWAN_DISPLAY_SOURCE_COMPONENT_PALETTE, 0x10021, 1},
      }};
      bool exact_runtime_sources = result == SWAN_RESULT_OK &&
          mono_source_count == expected_runtime_sources.size() &&
          mono_source_written == mono_sources.size();
      for (const auto& expected_source : expected_runtime_sources) {
        exact_runtime_sources = exact_runtime_sources && std::count_if(
            mono_sources.begin(), mono_sources.end(), [&](const auto& trace) {
              return trace.x == 0 && trace.y == 0 &&
                     trace.scope == SWAN_DISPLAY_SOURCE_SCOPE_SELECTED &&
                     trace.component == expected_source.component &&
                     trace.source_address == expected_source.address &&
                     trace.source_byte_count == expected_source.byte_count &&
                     trace.cartridge_offset == 0 &&
                     trace.cartridge_length == 0 &&
                     trace.flags == SWAN_DISPLAY_SOURCE_FLAG_EXACT &&
                     trace.read_context_flags == 0 &&
                     trace.minimum_instruction_hops == 0 &&
                     trace.maximum_instruction_hops == 0 &&
                     trace.conservative_reason ==
                         SWAN_DISPLAY_SOURCE_CONSERVATIVE_NONE;
            }) == 1;
      }
      if (!exact_runtime_sources) {
        std::fprintf(stderr,
                     "monochrome runtime lineage was not exact across %zu records\n",
                     mono_sources.size());
        for (const auto& trace : mono_sources) {
          std::fprintf(
              stderr,
              "mono component=%u scope=%u address=%05x bytes=%u range=%08x/%u hops=%u-%u flags=%x conservative=%u\n",
              trace.component, trace.scope, trace.source_address,
              trace.source_byte_count, trace.cartridge_offset,
              trace.cartridge_length, trace.minimum_instruction_hops,
              trace.maximum_instruction_hops, trace.flags,
              trace.conservative_reason);
        }
        swan_engine_destroy(engine);
        return 1;
      }

      swan_display_source_probe_options_t backdrop_palette_options{};
      backdrop_palette_options.struct_size = sizeof(backdrop_palette_options);
      backdrop_palette_options.selected_component_mask =
          SWAN_DISPLAY_SOURCE_COMPONENT_MASK_PALETTE;
      size_t backdrop_palette_count = 0;
      result = swan_engine_display_source_probe(
          engine, &transparency_rectangle, &backdrop_palette_options,
          nullptr, 0, &backdrop_palette_count);
      std::vector<swan_display_source_trace_t> backdrop_palette_sources(
          backdrop_palette_count);
      size_t backdrop_palette_written = 0;
      if (result == SWAN_RESULT_OK) {
        result = swan_engine_display_source_probe(
            engine, &transparency_rectangle, &backdrop_palette_options,
            backdrop_palette_sources.data(), backdrop_palette_sources.size(),
            &backdrop_palette_written);
      }
      const auto exact_backdrop_palette = std::count_if(
          backdrop_palette_sources.begin(), backdrop_palette_sources.end(),
          [](const auto& trace) {
            return trace.struct_size == sizeof(trace) &&
                   trace.x == 9 && trace.y == 0 &&
                   trace.scope == SWAN_DISPLAY_SOURCE_SCOPE_SELECTED &&
                   trace.component == SWAN_DISPLAY_SOURCE_COMPONENT_PALETTE &&
                   trace.source_address == 0x10001 &&
                   trace.source_byte_count == 1 &&
                   trace.cartridge_offset == 0 &&
                   trace.cartridge_length == 0 &&
                   trace.flags == SWAN_DISPLAY_SOURCE_FLAG_EXACT &&
                   trace.read_context_flags == 0 &&
                   trace.minimum_instruction_hops == 0 &&
                   trace.maximum_instruction_hops == 0 &&
                   trace.conservative_reason ==
                       SWAN_DISPLAY_SOURCE_CONSERVATIVE_NONE;
          });
      const auto selected_backdrop_palette = std::count_if(
          backdrop_palette_sources.begin(), backdrop_palette_sources.end(),
          [](const auto& trace) {
            return trace.scope == SWAN_DISPLAY_SOURCE_SCOPE_SELECTED;
          });
      if (result != SWAN_RESULT_OK ||
          backdrop_palette_count != 1 || backdrop_palette_written != 1 ||
          backdrop_palette_sources.size() != 1 ||
          selected_backdrop_palette != 1 || exact_backdrop_palette != 1) {
        std::fputs("monochrome backdrop palette lineage was not exact\n", stderr);
        swan_engine_destroy(engine);
        return 1;
      }

      swan_video_frame_t mono_frame{};
      result = swan_engine_video_frame(engine, &mono_frame);
      if (result != SWAN_RESULT_OK || !mono_frame.pixels ||
          mono_frame.stride_bytes < mono_frame.width * 4) {
        std::fputs("monochrome fixture lost its native frame\n", stderr);
        swan_engine_destroy(engine);
        return 1;
      }
      const auto pixel_at = [&](uint32_t x, uint32_t y) {
        std::array<uint8_t, 4> pixel{};
        const size_t offset = static_cast<size_t>(y) * mono_frame.stride_bytes +
            static_cast<size_t>(x) * 4u;
        std::copy_n(mono_frame.pixels + offset, pixel.size(), pixel.begin());
        return pixel;
      };
      const auto selected_pixel = pixel_at(0, 0);
      const auto transparency_pixel = pixel_at(9, 0);
      const auto backdrop_pixel = pixel_at(16, 1);
      if (selected_pixel == transparency_pixel ||
          transparency_pixel != backdrop_pixel) {
        std::fputs("monochrome native pixels did not preserve the owner/control contrast\n",
                   stderr);
        swan_engine_destroy(engine);
        return 1;
      }
      std::printf(
          "PASS monochrome palette OUT owner selected=%02x%02x%02x%02x backdrop=%02x%02x%02x%02x writer=%05x\n",
          selected_pixel[0], selected_pixel[1], selected_pixel[2],
          selected_pixel[3], transparency_pixel[0], transparency_pixel[1],
          transparency_pixel[2], transparency_pixel[3],
          selected_owner.palette_writer_pc);
    }

    if (provenance_fixture) {
      const bool vertical = frame_width < frame_height;
      const std::array<uint8_t, 32> planar_source_tile = {
          0xa5, 0x5a, 0x5a, 0x5a, 0xdb, 0x18, 0x7e, 0x42,
          0xe7, 0x42, 0x18, 0x7e, 0xff, 0x00, 0x66, 0x99,
          0xbd, 0xdb, 0x42, 0x18, 0x81, 0x7e, 0x18, 0x42,
          0xc3, 0x3c, 0x66, 0x99, 0xaa, 0x55, 0xf0, 0x0f,
      };
      const std::array<uint8_t, 32> packed_source_tile = {
          0x4b, 0x4b, 0x4b, 0x4b, 0x48, 0x7b, 0x48, 0x7b,
          0x49, 0x6b, 0x49, 0x6b, 0x4e, 0x1b, 0x4e, 0x1b,
          0x4f, 0x0b, 0x4f, 0x0b, 0x4c, 0x3b, 0x4c, 0x3b,
          0x4d, 0x2b, 0x4d, 0x2b, 0x42, 0xdb, 0x42, 0xdb,
      };
      const auto& source_tile = expected_raster_bytes == 1
          ? packed_source_tile : planar_source_tile;
      const auto marker = std::search(
          rom.begin(), rom.end(), source_tile.begin(), source_tile.end());
      if (marker == rom.end() ||
          std::search(std::next(marker), rom.end(),
                      source_tile.begin(), source_tile.end()) != rom.end()) {
        std::fputs("upstream source fixture table is missing or ambiguous\n", stderr);
        swan_engine_destroy(engine);
        return 1;
      }
      const uint32_t marker_offset = static_cast<uint32_t>(
          std::distance(rom.begin(), marker));
      // On the 16-bit cartridge bus, the packed byte arrives through a
      // byte-register chain whose observed upstream read covers its aligned
      // two-byte bus unit. Planar pixels consume all four row bytes.
      const uint32_t expected_source_bytes =
          expected_raster_bytes == 1 ? 2u : 4u;
      struct ExpectedOwner {
        uint16_t x;
        uint16_t y;
        swan_display_layer_t layer;
        swan_display_source_kind_t source;
        uint16_t cell;
        uint16_t tile;
        uint16_t raster;
        uint8_t palette;
        uint8_t color;
        uint32_t palette_address;
        uint16_t oam_address;
      };
      const std::array<ExpectedOwner, 3> expected = vertical
          ? std::array<ExpectedOwner, 3>{
                ExpectedOwner{8, 215, SWAN_DISPLAY_LAYER_SCREEN_1,
                              SWAN_DISPLAY_SOURCE_TILEMAP, 0x1842, 1,
                              0x4020, 0, 1, 0xfe02, 0xffff},
                ExpectedOwner{48, 159, SWAN_DISPLAY_LAYER_SCREEN_2,
                              SWAN_DISPLAY_SOURCE_TILEMAP, 0x1190, 2,
                              0x4040, 1, 2, 0xfe24, 0xffff},
                ExpectedOwner{48, 95, SWAN_DISPLAY_LAYER_SPRITE,
                              SWAN_DISPLAY_SOURCE_SPRITE, 0xffff, 3,
                              0x4060, 8, 3, 0xff06, 0x0e00},
            }
          : std::array<ExpectedOwner, 3>{
                ExpectedOwner{8, 8, SWAN_DISPLAY_LAYER_SCREEN_1,
                              SWAN_DISPLAY_SOURCE_TILEMAP, 0x1842, 1,
                              0x4020, 0, 1, 0xfe02, 0xffff},
                ExpectedOwner{64, 48, SWAN_DISPLAY_LAYER_SCREEN_2,
                              SWAN_DISPLAY_SOURCE_TILEMAP, 0x1190, 2,
                              0x4040, 1, 2, 0xfe24, 0xffff},
                ExpectedOwner{128, 48, SWAN_DISPLAY_LAYER_SPRITE,
                              SWAN_DISPLAY_SOURCE_SPRITE, 0xffff, 3,
                              0x4060, 8, 3, 0xff06, 0x0e00},
            };

      for (const auto& item : expected) {
        swan_display_rectangle_t fixture_rectangle{};
        fixture_rectangle.struct_size = sizeof(fixture_rectangle);
        fixture_rectangle.x = item.x;
        fixture_rectangle.y = item.y;
        fixture_rectangle.width = 1;
        fixture_rectangle.height = 1;
        swan_display_owner_sample_t owner{};
        size_t fixture_count = 0;
        result = swan_engine_display_owner_probe(
            engine, &fixture_rectangle, &owner, 1, &fixture_count);
        const bool cell_writer_ok = item.source == SWAN_DISPLAY_SOURCE_SPRITE
            ? owner.cell_writer_pc == UINT32_MAX
            : owner.cell_writer_pc != UINT32_MAX;
        const bool oam_writer_ok = item.source == SWAN_DISPLAY_SOURCE_SPRITE
            ? owner.oam_address == item.oam_address &&
                owner.oam_byte_count == 4 &&
                owner.oam_writer_pc != UINT32_MAX
            : owner.oam_address == 0xffff && owner.oam_byte_count == 0 &&
                owner.oam_writer_pc == UINT32_MAX;
        if (result != SWAN_RESULT_OK || fixture_count != 1 ||
            owner.x != item.x || owner.y != item.y ||
            owner.layer != item.layer || owner.source_kind != item.source ||
            owner.cell_address != item.cell || owner.tile_index != item.tile ||
            owner.raster_address != item.raster ||
            owner.raster_byte_count != expected_raster_bytes ||
            owner.palette_index != item.palette ||
            owner.palette_color != item.color ||
            owner.palette_address != item.palette_address ||
            owner.palette_byte_count != 2 || !cell_writer_ok ||
            !oam_writer_ok ||
            owner.raster_writer_pc == UINT32_MAX ||
            owner.palette_writer_pc == UINT32_MAX) {
          std::fprintf(
              stderr,
              "fixture provenance mismatch at %u,%u layer=%u source=%u cell=%04x tile=%u raster=%04x/%u palette=%u:%u@%05x oam=%04x/%u writers=%05x/%05x/%05x/%05x\n",
              item.x, item.y, owner.layer, owner.source_kind,
              owner.cell_address, owner.tile_index, owner.raster_address,
              owner.raster_byte_count, owner.palette_index,
              owner.palette_color, owner.palette_address,
              owner.oam_address, owner.oam_byte_count,
              owner.cell_writer_pc, owner.raster_writer_pc,
              owner.palette_writer_pc, owner.oam_writer_pc);
          swan_engine_destroy(engine);
          return 1;
        }
      }

      swan_display_rectangle_t sprite_rectangle{};
      sprite_rectangle.struct_size = sizeof(sprite_rectangle);
      sprite_rectangle.x = expected[2].x;
      sprite_rectangle.y = expected[2].y;
      sprite_rectangle.width = 1;
      sprite_rectangle.height = 1;
      swan_display_source_probe_options_t oam_options{};
      oam_options.struct_size = sizeof(oam_options);
      oam_options.selected_component_mask =
          SWAN_DISPLAY_SOURCE_COMPONENT_MASK_SPRITE_ATTRIBUTE;
      size_t oam_source_count = 0;
      result = swan_engine_display_source_probe(
          engine, &sprite_rectangle, &oam_options,
          nullptr, 0, &oam_source_count);
      std::vector<swan_display_source_trace_t> oam_sources(oam_source_count);
      size_t oam_source_written = 0;
      if (result == SWAN_RESULT_OK) {
        result = swan_engine_display_source_probe(
            engine, &sprite_rectangle, &oam_options,
            oam_sources.data(), oam_sources.size(), &oam_source_written);
      }
      const auto selected_oam = std::find_if(
          oam_sources.begin(), oam_sources.end(), [&](const auto& trace) {
            return trace.scope == SWAN_DISPLAY_SOURCE_SCOPE_SELECTED &&
                   trace.component ==
                       SWAN_DISPLAY_SOURCE_COMPONENT_SPRITE_ATTRIBUTE &&
                   trace.source_address == expected[2].oam_address &&
                   trace.source_byte_count == 4 &&
                   (trace.conservative_reason ==
                        SWAN_DISPLAY_SOURCE_CONSERVATIVE_NONE ||
                    ((trace.flags &
                      SWAN_DISPLAY_SOURCE_FLAG_CONSERVATIVE_DATAFLOW) != 0 &&
                     (trace.flags & SWAN_DISPLAY_SOURCE_FLAG_EXACT) == 0 &&
                     trace.conservative_origin ==
                         ((((uint32_t)trace.conservative_origin_segment << 4) +
                           trace.conservative_origin_offset) & 0xfffffu)));
          });
      if (result != SWAN_RESULT_OK || oam_source_count == 0 ||
          oam_source_written != oam_sources.size() ||
          selected_oam == oam_sources.end() ||
          std::any_of(oam_sources.begin(), oam_sources.end(), [](const auto& trace) {
            return trace.scope == SWAN_DISPLAY_SOURCE_SCOPE_SELECTED &&
                   trace.component !=
                       SWAN_DISPLAY_SOURCE_COMPONENT_SPRITE_ATTRIBUTE;
          })) {
        std::fputs("sprite-attribute source selection was invalid\n", stderr);
        swan_engine_destroy(engine);
        return 1;
      }

      swan_display_rectangle_t source_rectangle{};
      source_rectangle.struct_size = sizeof(source_rectangle);
      source_rectangle.x = 8;
      source_rectangle.y = vertical ? 215 : 8;
      source_rectangle.width = 1;
      source_rectangle.height = 1;
      size_t fixture_source_count = 0;
      swan_display_source_probe_options_t fixture_source_options{};
      fixture_source_options.struct_size = sizeof(fixture_source_options);
      fixture_source_options.selected_component_mask =
          SWAN_DISPLAY_SOURCE_COMPONENT_MASK_ALL;
      result = swan_engine_display_source_probe(
          engine, &source_rectangle, &fixture_source_options,
          nullptr, 0, &fixture_source_count);
      if (result != SWAN_RESULT_OK || fixture_source_count == 0 ||
          fixture_source_count > 262'144u) {
        std::fputs("fixture did not expose bounded upstream source records\n", stderr);
        swan_engine_destroy(engine);
        return 1;
      }
      std::vector<swan_display_source_trace_t> fixture_sources(
          fixture_source_count);
      size_t fixture_source_written = 0;
      result = swan_engine_display_source_probe(
          engine, &source_rectangle, &fixture_source_options,
          fixture_sources.data(),
          fixture_sources.size(), &fixture_source_written);
      if (result != SWAN_RESULT_OK ||
          fixture_source_written != fixture_sources.size()) {
        std::fputs("fixture upstream source records were incomplete\n", stderr);
        swan_engine_destroy(engine);
        return 1;
      }
      const auto exact_raster = std::find_if(
          fixture_sources.begin(), fixture_sources.end(),
          [&](const auto& trace) {
            return trace.scope == SWAN_DISPLAY_SOURCE_SCOPE_SELECTED &&
                   trace.component == SWAN_DISPLAY_SOURCE_COMPONENT_RASTER &&
                   (trace.flags & SWAN_DISPLAY_SOURCE_FLAG_EXACT) != 0 &&
                   (trace.flags & SWAN_DISPLAY_SOURCE_FLAG_TRANSFORMED) != 0 &&
                   trace.cartridge_offset == marker_offset &&
                   trace.cartridge_length == expected_source_bytes &&
                   trace.minimum_instruction_hops > 0 &&
                   (trace.read_context_flags &
                    SWAN_DISPLAY_SOURCE_READ_CONTEXT_EXECUTED) != 0 &&
                   trace.read_context_initiator ==
                       SWAN_DISPLAY_SOURCE_READ_INITIATOR_CPU &&
                   trace.immediate_caller_or_general_dma_source_operand ==
                       (((uint32_t)trace.caller_segment << 4) +
                        trace.caller_offset) % 0x100000u &&
                   ((((uint32_t)trace.operand_segment << 4) +
                      trace.operand_offset) & 0xf0000u) >> 16 ==
                       trace.mapper_window &&
                   trace.mapper_window >= 2 && trace.mapper_window <= 15;
          });
      if (exact_raster == fixture_sources.end()) {
        std::fprintf(
            stderr,
            "fixture lost exact raster source %08x/%u across %zu records\n",
            marker_offset, expected_source_bytes, fixture_sources.size());
        for (const auto& trace : fixture_sources) {
          if (trace.scope == SWAN_DISPLAY_SOURCE_SCOPE_SELECTED) {
            std::fprintf(
                stderr,
                "selected component=%u address=%05x range=%08x/%u hops=%u-%u flags=%x\n",
                trace.component, trace.source_address, trace.cartridge_offset,
                trace.cartridge_length, trace.minimum_instruction_hops,
                trace.maximum_instruction_hops, trace.flags);
          }
        }
        swan_engine_destroy(engine);
        return 1;
      }
      const auto outside_consumer = std::find_if(
          fixture_sources.begin(), fixture_sources.end(),
          [&](const auto& trace) {
            return trace.scope == SWAN_DISPLAY_SOURCE_SCOPE_OUTSIDE_CONSUMER &&
                   trace.component == SWAN_DISPLAY_SOURCE_COMPONENT_RASTER &&
                   trace.cartridge_offset == marker_offset &&
                   trace.cartridge_length == expected_source_bytes &&
                   (trace.flags & SWAN_DISPLAY_SOURCE_FLAG_EXACT) != 0;
          });
      if (outside_consumer == fixture_sources.end()) {
        std::fputs("fixture lost its outside consumer of the exact raster source\n", stderr);
        swan_engine_destroy(engine);
        return 1;
      }

      swan_display_source_probe_options_t raster_options{};
      raster_options.struct_size = sizeof(raster_options);
      raster_options.selected_component_mask =
          SWAN_DISPLAY_SOURCE_COMPONENT_MASK_RASTER;
      size_t raster_only_count = 0;
      result = swan_engine_display_source_probe(
          engine, &source_rectangle, &raster_options,
          nullptr, 0, &raster_only_count);
      std::vector<swan_display_source_trace_t> raster_only(raster_only_count);
      size_t raster_only_written = 0;
      if (result == SWAN_RESULT_OK) {
        result = swan_engine_display_source_probe(
            engine, &source_rectangle, &raster_options,
            raster_only.data(), raster_only.size(), &raster_only_written);
      }
      if (result != SWAN_RESULT_OK || raster_only_written != raster_only.size() ||
          raster_only.empty() ||
          std::any_of(raster_only.begin(), raster_only.end(), [](const auto& trace) {
            return trace.scope == SWAN_DISPLAY_SOURCE_SCOPE_SELECTED &&
                   trace.component != SWAN_DISPLAY_SOURCE_COMPONENT_RASTER;
          })) {
        std::fputs("component-selective raster source probe was invalid\n", stderr);
        swan_engine_destroy(engine);
        return 1;
      }
      const auto same_trace = [](const auto& lhs, const auto& rhs) {
        return lhs.x == rhs.x && lhs.y == rhs.y && lhs.scope == rhs.scope &&
               lhs.component == rhs.component &&
               lhs.source_address == rhs.source_address &&
               lhs.source_byte_count == rhs.source_byte_count &&
               lhs.cartridge_offset == rhs.cartridge_offset &&
               lhs.cartridge_length == rhs.cartridge_length &&
               lhs.read_context_initiator == rhs.read_context_initiator &&
               lhs.immediate_caller_or_general_dma_source_operand ==
                   rhs.immediate_caller_or_general_dma_source_operand &&
               lhs.caller_segment == rhs.caller_segment &&
               lhs.caller_offset == rhs.caller_offset &&
               lhs.operand_segment == rhs.operand_segment &&
               lhs.operand_offset == rhs.operand_offset &&
               lhs.mapper_window == rhs.mapper_window &&
               lhs.mapper_bank == rhs.mapper_bank &&
               lhs.resolved_cartridge_operand == rhs.resolved_cartridge_operand;
      };
      for (const auto& consumer : fixture_sources) {
        if (consumer.scope != SWAN_DISPLAY_SOURCE_SCOPE_OUTSIDE_CONSUMER) continue;
        const uint64_t consumer_upper =
            static_cast<uint64_t>(consumer.cartridge_offset) +
            consumer.cartridge_length;
        const bool shares_raster_range = std::any_of(
            raster_only.begin(), raster_only.end(), [&](const auto& selected) {
              if (selected.scope != SWAN_DISPLAY_SOURCE_SCOPE_SELECTED) return false;
              const uint64_t selected_upper =
                  static_cast<uint64_t>(selected.cartridge_offset) +
                  selected.cartridge_length;
              return consumer.cartridge_offset < selected_upper &&
                     selected.cartridge_offset < consumer_upper;
            });
        if (shares_raster_range &&
            std::none_of(raster_only.begin(), raster_only.end(), [&](const auto& trace) {
              return same_trace(consumer, trace);
            })) {
          std::fputs("raster selection omitted a cross-component outside consumer\n", stderr);
          swan_engine_destroy(engine);
          return 1;
        }
      }

      size_t v2_trace_count = 0;
      size_t v2_context_count = 0;
      size_t v2_byte_count = 0;
      result = swan_engine_display_source_probe_v2(
          engine, &source_rectangle, &raster_options,
          nullptr, 0, &v2_trace_count,
          nullptr, 0, &v2_context_count,
          nullptr, 0, &v2_byte_count);
      if (result != SWAN_RESULT_OK || v2_trace_count != raster_only.size() ||
          v2_context_count == 0 || v2_byte_count == 0) {
        std::fprintf(
            stderr,
            "ABI10 consumed-prefetch sizing failed result=%u traces=%zu contexts=%zu bytes=%zu error=%s\n",
            result, v2_trace_count, v2_context_count, v2_byte_count,
            swan_engine_last_error(engine));
        swan_engine_destroy(engine);
        return 1;
      }
      std::vector<swan_display_source_trace_v2_t> v2_traces(v2_trace_count);
      std::vector<swan_instruction_fetch_context_t> v2_contexts(
          v2_context_count);
      std::vector<swan_instruction_fetch_byte_t> v2_bytes(v2_byte_count);
      size_t v2_trace_written = 0;
      size_t v2_context_written = 0;
      size_t v2_byte_written = 0;
      result = swan_engine_display_source_probe_v2(
          engine, &source_rectangle, &raster_options,
          v2_traces.data(), v2_traces.size(), &v2_trace_written,
          v2_contexts.data(), v2_contexts.size(), &v2_context_written,
          v2_bytes.data(), v2_bytes.size(), &v2_byte_written);
      if (result != SWAN_RESULT_OK || v2_trace_written != v2_traces.size() ||
          v2_context_written != v2_contexts.size() ||
          v2_byte_written != v2_bytes.size()) {
        std::fputs("ABI10 consumed-prefetch retrieval was incomplete\n", stderr);
        swan_engine_destroy(engine);
        return 1;
      }
      for (size_t index = 0; index < v2_traces.size(); ++index) {
        if (v2_traces[index].struct_size != sizeof(v2_traces[index]) ||
            std::memcmp(
                reinterpret_cast<const uint8_t*>(&v2_traces[index]) + 4,
                reinterpret_cast<const uint8_t*>(&raster_only[index]) + 4,
                sizeof(swan_display_source_trace_t) - 4) != 0) {
          std::fputs("ABI10 trace changed its ABI9 field prefix\n", stderr);
          swan_engine_destroy(engine);
          return 1;
        }
      }
      const uint32_t required_fetch_flags =
          SWAN_FETCH_CONTEXT_FLAG_SEALED |
          SWAN_FETCH_CONTEXT_FLAG_EXACT_CARTRIDGE_RUN |
          SWAN_FETCH_CONTEXT_FLAG_BIJECTIVE_IDENTITY |
          SWAN_FETCH_CONTEXT_FLAG_PYPCODE_CHECK_REQUIRED |
          SWAN_FETCH_CONTEXT_FLAG_EXACT_DATA_INCOMPLETE;
      for (const auto& context : v2_contexts) {
        const size_t matching_contexts = std::count_if(
            v2_contexts.begin(), v2_contexts.end(), [&](const auto& candidate) {
              return candidate.id == context.id;
            });
        if (context.struct_size != sizeof(context) || context.id == 0 ||
            matching_contexts != 1 ||
            context.structural_id == 0 ||
            (context.flags & required_fetch_flags) != required_fetch_flags ||
            context.byte_count == 0 ||
            context.byte_count > v2_bytes.size() ||
            context.byte_start > v2_bytes.size() - context.byte_count) {
          std::fputs("ABI10 emitted an ineligible fetch context\n", stderr);
          swan_engine_destroy(engine);
          return 1;
        }
        const auto& first = v2_bytes[context.byte_start];
        size_t terminal_index = 0;
        const auto supported_prefix = [](uint32_t byte) {
          return byte == 0x26 || byte == 0x2e || byte == 0x36 ||
                 byte == 0x3e || byte == 0xf0 || byte == 0xf2 ||
                 byte == 0xf3;
        };
        while (terminal_index < context.byte_count &&
               supported_prefix(
                   v2_bytes[context.byte_start + terminal_index].data)) {
          ++terminal_index;
        }
        if (context.logical_start_segment != first.segment ||
            context.logical_start_offset != first.offset ||
            context.logical_start_physical != first.physical_address ||
            terminal_index == context.byte_count ||
            v2_bytes[context.byte_start + terminal_index].data !=
                context.terminal_opcode ||
            context.terminal_opcode == 0x0f || context.terminal_opcode == 0x64 ||
            context.terminal_opcode == 0x65 || context.terminal_opcode == 0x66 ||
            context.terminal_opcode == 0x67) {
          std::fputs("ABI10 logical instruction start was inconsistent\n", stderr);
          swan_engine_destroy(engine);
          return 1;
        }
        for (uint32_t ordinal = 0; ordinal < context.byte_count; ++ordinal) {
          const auto& byte = v2_bytes[context.byte_start + ordinal];
          const uint32_t mapped = byte.resolved_operand &
              (static_cast<uint32_t>(info.mapped_size) - 1u);
          const uint32_t padding = static_cast<uint32_t>(
              info.mapped_size - rom.size());
          if (byte.struct_size != sizeof(byte) || byte.context_id != context.id ||
              byte.ordinal != ordinal || byte.token == 0 ||
              byte.source_kind != 1 || byte.event_context == 0 ||
              byte.mapper_window != first.mapper_window ||
              byte.mapper_bank != first.mapper_bank ||
              byte.resolved_operand != first.resolved_operand + ordinal ||
              byte.physical_address != first.physical_address + ordinal ||
              byte.segment != first.segment ||
              byte.offset != first.offset + ordinal ||
              mapped < padding || mapped - padding >= rom.size() ||
              byte.data != rom[mapped - padding]) {
            std::fputs("ABI10 fetch byte did not match its exact ROM origin\n", stderr);
            swan_engine_destroy(engine);
            return 1;
          }
        }
      }
      bool selected_execution_association = false;
      for (const auto& trace : v2_traces) {
        if (trace.execution_context_id == 0) continue;
        const auto context = std::find_if(
            v2_contexts.begin(), v2_contexts.end(), [&](const auto& candidate) {
              return candidate.id == trace.execution_context_id;
            });
        if (context == v2_contexts.end() ||
            trace.fetch_context_flags != context->flags) {
          std::fputs("ABI10 trace did not resolve to its sealed execution row\n", stderr);
          swan_engine_destroy(engine);
          return 1;
        }
        if (trace.scope == SWAN_DISPLAY_SOURCE_SCOPE_SELECTED &&
            trace.x == source_rectangle.x && trace.y == source_rectangle.y) {
          selected_execution_association = true;
        }
      }
      if (!selected_execution_association) {
        std::fputs("ABI10 raster trace had no sealed execution context\n", stderr);
        swan_engine_destroy(engine);
        return 1;
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
    owner_count = 0;
    const auto restored_probe = swan_engine_display_owner_probe(
        engine, &rectangle, owners.data(), owners.size(), &owner_count);
    if (result == SWAN_RESULT_OK && restored_probe != SWAN_RESULT_UNSUPPORTED) {
      std::fputs("restored state incorrectly retained CPU-writer provenance\n", stderr);
      swan_engine_destroy(engine);
      return 1;
    }
    if (result == SWAN_RESULT_OK && static_analysis_seed_v2_fixture) {
      swan_display_rectangle_t restored_seed_rectangle{};
      restored_seed_rectangle.struct_size = sizeof(restored_seed_rectangle);
      restored_seed_rectangle.width = 1;
      restored_seed_rectangle.height = 1;
      swan_display_source_probe_options_t restored_seed_options{};
      restored_seed_options.struct_size = sizeof(restored_seed_options);
      restored_seed_options.selected_component_mask =
          SWAN_DISPLAY_SOURCE_COMPONENT_MASK_RASTER;
      size_t restored_trace_count = 7;
      size_t restored_context_count = 7;
      size_t restored_byte_count = 7;
      const auto restored_v2_probe = swan_engine_display_source_probe_v2(
          engine, &restored_seed_rectangle, &restored_seed_options,
          nullptr, 0, &restored_trace_count,
          nullptr, 0, &restored_context_count,
          nullptr, 0, &restored_byte_count);
      if (restored_v2_probe != SWAN_RESULT_UNSUPPORTED ||
          restored_trace_count != 0 || restored_context_count != 0 ||
          restored_byte_count != 0) {
        std::fputs("restored state incorrectly retained ABI10 fetch provenance\n",
                   stderr);
        swan_engine_destroy(engine);
        return 1;
      }
    }
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
    // The running software owns console EEPROM after boot and may legitimately
    // update it. Exact staging is verified immediately after load above; here
    // verify that the live persistence surface remains readable and retains
    // the hardware-sized region after execution and save-state replay.
    if (result != SWAN_RESULT_OK || persisted_size != staged_console.size() ||
        persisted.empty()) {
      std::fputs("console EEPROM persistence surface became invalid\n", stderr);
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
    if (static_analysis_seed_v2_fixture) {
      std::printf(
          "PASS static-analysis-seed-v2 visible=1 abi9=1 abi10=1 distinct=1 atomic=3 restore-stop=1 traces=%zu contexts=%zu bytes=%zu video=%016llx\n",
          static_seed_trace_count, static_seed_context_count,
          static_seed_byte_count,
          static_cast<unsigned long long>(video_hash));
    } else {
      std::printf(
          "PASS ares executed and replayed state at %ux%u with %zu audio frames; video=%016llx\n",
          frame_width, frame_height, audio.frame_count,
          static_cast<unsigned long long>(video_hash));
    }
  } else {
    std::puts("PASS pinned WonderSwan-only ares backend linked");
  }

  swan_engine_destroy(engine);
  return 0;
}
