#include "swan_engine_backend.hpp"

#if defined(SWAN_ENABLE_ARES)

#include <ares/ares.hpp>
#include <ws/ws.hpp>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <ctime>
#include <cstring>
#include <map>
#include <limits>
#include <mutex>
#include <span>
#include <vector>

namespace {

constexpr auto kFrameTimeout = std::chrono::seconds(2);

size_t save_size(uint8_t save_type) {
  switch (save_type) {
    case 0x01:
    case 0x02: return 32u * 1024u;
    case 0x03: return 128u * 1024u;
    case 0x04: return 256u * 1024u;
    case 0x05: return 512u * 1024u;
    case 0x10: return 128u;
    case 0x20: return 2048u;
    case 0x50: return 1024u;
    default: return 0;
  }
}

bool save_is_eeprom(uint8_t save_type) {
  return save_type == 0x10 || save_type == 0x20 || save_type == 0x50;
}

enum class OpenIPLModel {
  WonderSwan,
  WonderSwanColor,
  SwanCrystal,
  PocketChallengeV2,
};

OpenIPLModel open_ipl_model(swan_model_t configured,
                            const swan_rom_info_t& info) {
  switch (configured) {
    case SWAN_MODEL_WONDERSWAN: return OpenIPLModel::WonderSwan;
    case SWAN_MODEL_WONDERSWAN_COLOR: return OpenIPLModel::WonderSwanColor;
    case SWAN_MODEL_SWANCRYSTAL: return OpenIPLModel::SwanCrystal;
    case SWAN_MODEL_POCKET_CHALLENGE_V2:
      return OpenIPLModel::PocketChallengeV2;
    case SWAN_MODEL_AUTOMATIC:
      return info.color ? OpenIPLModel::WonderSwanColor
                        : OpenIPLModel::WonderSwan;
  }
  return OpenIPLModel::WonderSwan;
}

const char* model_name(OpenIPLModel model) {
  switch (model) {
    case OpenIPLModel::WonderSwan: return "[Bandai] WonderSwan";
    case OpenIPLModel::WonderSwanColor: return "[Bandai] WonderSwan Color";
    case OpenIPLModel::SwanCrystal: return "[Bandai] SwanCrystal";
    case OpenIPLModel::PocketChallengeV2:
      return "[Benesse] Pocket Challenge V2";
  }
  return "[Bandai] WonderSwan";
}

bool color_model(OpenIPLModel model) {
  return model == OpenIPLModel::WonderSwanColor ||
         model == OpenIPLModel::SwanCrystal;
}

// SwanSong's independently written IPL. The original console boot ROM is not
// needed for the normal path. The V30 reset vector first jumps backward into
// the still-mapped IPL window, where this code establishes a conservative
// cartridge handoff state and writes a tiny transfer routine into internal
// RAM. That routine irreversibly enables cartridge mapping through HW_FLAGS,
// then safely transfers through the newly exposed FFFF:0000 reset vector.
//
// Executing the lockout from RAM matters: code in the boot window disappears
// as soon as HW_FLAGS bit 0 is set, so relying on the CPU prefetch queue for a
// following jump is fragile. The NOP-filled 4/8 KiB container only supplies
// the address window expected by ares and contains no third-party firmware.
std::vector<uint8_t> swan_song_open_ipl(OpenIPLModel model,
                                        bool word_width,
                                        bool protect_owner_area) {
  const bool color = color_model(model);
  const bool pocket_challenge = model == OpenIPLModel::PocketChallengeV2;
  std::vector<uint8_t> boot(color ? 8192u : 4096u, 0x90);
  const uint8_t hardware_flags = static_cast<uint8_t>(
      0x81u | (color ? 0x02u : 0u) | (word_width ? 0x04u : 0u));
  const uint16_t cartridge_entry_offset = pocket_challenge ? 0x0010u : 0x0000u;
  const uint16_t cartridge_entry_segment = pocket_challenge ? 0x4000u : 0xffffu;
  std::vector<uint8_t> ram_handoff = {
      0xb0, hardware_flags,              // mov al, HW_FLAGS
      0xe6, 0xa0,                        // out 0xa0, al
  };
  if (pocket_challenge) {
    // The PCV2 pinstrap enters the cartridge with the reset accumulator. MOV
    // and OUT leave the V30 flags untouched, retaining a near-power-on state.
    ram_handoff.insert(ram_handoff.end(), {0xb8, 0x00, 0x00}); // mov ax,0
  }
  ram_handoff.insert(ram_handoff.end(), {
      0xea,
      static_cast<uint8_t>(cartridge_entry_offset),
      static_cast<uint8_t>(cartridge_entry_offset >> 8),
      static_cast<uint8_t>(cartridge_entry_segment),
      static_cast<uint8_t>(cartridge_entry_segment >> 8),
  });

  std::vector<uint8_t> startup;
  const auto emit = [&](std::initializer_list<uint8_t> bytes) {
    startup.insert(startup.end(), bytes.begin(), bytes.end());
  };
  const auto emit_out8 = [&](uint8_t port, uint8_t value) {
    emit({0xb0, value, 0xe6, port});       // mov al,value; out port,al
  };
  const auto emit_ram_handoff_bytes = [&] {
    for (size_t index = 0; index < ram_handoff.size(); ++index) {
      const uint16_t address = static_cast<uint16_t>(0x0400u + index);
      emit({0xc6, 0x06,                   // mov byte [address], immediate
            static_cast<uint8_t>(address),
            static_cast<uint8_t>(address >> 8),
            ram_handoff[index]});
    }
  };

  if (pocket_challenge) {
    // Pocket Challenge V2 exposes a keypad pinstrap that bypasses a normal
    // WonderSwan IPL. Preserve the V30's near-power-on register/flag and LCD
    // state, lock out the boot window from a tiny IRAM trampoline, and enter
    // the cartridge directly at the documented 4000:0010 pinstrap target.
    emit_ram_handoff_bytes();
    emit({0xea, 0x00, 0x04, 0x00, 0x00}); // jmp far 0x0000:0400
  } else {
    emit({0xfa});                           // cli
    emit({0x31, 0xc0});                     // xor ax, ax
    emit({0x8e, 0xd8});                     // mov ds, ax
    emit({0x8e, 0xc0});                     // mov es, ax
    emit({0x8e, 0xd0});                     // mov ss, ax
    emit({0xbc, 0x00, 0x20});               // mov sp, 0x2000
    emit_out8(0x14, 0x01);                  // enable the LCD panel driver
    emit_out8(0x16, 0x9e);                  // 159 scanlines per frame
    emit_out8(0x17, 0x9b);                  // hardware vertical sync timing
    if (color) emit_out8(0x60, 0x0a);       // Color SRAM and I/O wait timing
    emit_out8(0xb5, 0x40);                  // select the action-button row

    // Public WonderSwan EEPROM interfaces define EWEN through the internal
    // command/control ports. Standard cartridges then protect the owner and
    // telemetry area; footer version bit 7 explicitly opts out so software
    // that manages that area can retain write access.
    emit_out8(0xbc, color ? 0x00 : 0x30);
    emit_out8(0xbd, color ? 0x13 : 0x01);
    emit_out8(0xbe, 0x40);                  // EWEN
    if (protect_owner_area) emit_out8(0xbe, 0x80);

    emit_ram_handoff_bytes();
    emit({0xb9, 0x00, 0x00});               // mov cx, 0
    emit({0xba, 0x01, 0x00});               // mov dx, 1
    emit({0xbb, static_cast<uint8_t>(color ? 0x43 : 0x40), 0x00});
    emit({0xbd, 0x00, 0x00});               // mov bp, 0
    emit({0xbe, static_cast<uint8_t>(color ? 0x35 : 0x3d),
          static_cast<uint8_t>(color ? 0x04 : 0x02)});  // mov si, handoff value
    emit({0xbf, static_cast<uint8_t>(color ? 0x0b : 0x0d), 0x04});
    emit({0xb8, 0x00, static_cast<uint8_t>(color ? 0xfe : 0xff)});
    emit({0x8e, 0xd8});                     // mov ds, ax
    emit({0xb8, static_cast<uint8_t>(color ? 0x86 : 0x82), 0xf0});
    emit({0x50, 0x9d});                     // push ax; popf
    emit({0xb8, hardware_flags, 0xff});      // observable handoff accumulator
    emit({0xea, 0x00, 0x04, 0x00, 0x00});   // jmp far 0x0000:0400
  }

  constexpr size_t kStartupOffsetFromEnd = 256u;
  constexpr size_t kResetVectorOffsetFromEnd = 16u;
  static_assert(kStartupOffsetFromEnd > kResetVectorOffsetFromEnd);
  constexpr uint8_t reset_vector[] = {
      0xea, 0x00, 0x00, 0xf0, 0xff,       // jmp far 0xfff0:0000
  };
  if (boot.size() < kStartupOffsetFromEnd ||
      std::size(reset_vector) > kResetVectorOffsetFromEnd ||
      startup.size() > kStartupOffsetFromEnd - kResetVectorOffsetFromEnd) {
    return {};
  }
  std::copy(startup.begin(), startup.end(),
            boot.end() - kStartupOffsetFromEnd);
  std::copy(std::begin(reset_vector), std::end(reset_vector),
            boot.end() - kResetVectorOffsetFromEnd);
  return boot;
}

std::vector<uint8_t> deterministic_rtc(uint64_t unix_seconds) {
  const auto timestamp = static_cast<std::time_t>(unix_seconds);
  std::tm utc{};
  if (!gmtime_r(&timestamp, &utc)) return {};

  const auto bcd = [](int value) {
    return static_cast<uint8_t>(((value / 10) << 4) | (value % 10));
  };
  std::vector<uint8_t> rtc(18u, 0);
  rtc[0] = bcd((utc.tm_year + 1900) % 100);
  rtc[1] = bcd(utc.tm_mon + 1);
  rtc[2] = bcd(utc.tm_mday);
  rtc[3] = bcd(utc.tm_wday);
  rtc[4] = bcd(utc.tm_hour);
  rtc[5] = bcd(utc.tm_min);
  rtc[6] = bcd(utc.tm_sec);
  rtc[7] = 0x40;  // Valid status, 24-hour clock.
  for (size_t index = 0; index < 8; ++index) {
    rtc[8 + index] = static_cast<uint8_t>(unix_seconds >> (index * 8));
  }
  return rtc;
}

class AresBackend final : public SwanEngineBackend, private ares::Platform {
 public:
  explicit AresBackend(const swan_engine_config_t& config)
      : config_(config) {}

  ~AresBackend() override {
    std::string ignored;
    unload(ignored);
  }

  const char* name() const override { return "ares"; }

  uint64_t capabilities() const override {
    return SWAN_CAPABILITY_ROM_INSPECTION |
           SWAN_CAPABILITY_EXECUTION |
           SWAN_CAPABILITY_AUDIO |
           SWAN_CAPABILITY_SAVE_STATES |
           SWAN_CAPABILITY_PERSISTENCE |
           SWAN_CAPABILITY_DEBUGGER |
           SWAN_CAPABILITY_POCKET_CHALLENGE_V2;
  }

  swan_result_t load(std::span<const uint8_t> rom,
                     const swan_rom_info_t& info,
                     std::string& error) override {
    unload(error);
    error.clear();

    {
      std::lock_guard lock(active_mutex_);
      if (active_ && active_ != this) {
        error = "ares currently supports one live WonderSwan instance";
        return SWAN_RESULT_UNSUPPORTED;
      }
      active_ = this;
      ares::platform = this;
    }

    const auto selected_open_ipl_model =
        open_ipl_model(config_.preferred_model, info);
    const char* selected_model = model_name(selected_open_ipl_model);
    const bool is_pocket_challenge =
        selected_open_ipl_model == OpenIPLModel::PocketChallengeV2;
    system_pak_ = std::make_shared<vfs::directory>();
    game_pak_ = std::make_shared<vfs::directory>();

    const bool is_color_hardware = color_model(selected_open_ipl_model);
    const bool word_width = (rom[rom.size() - 4] & 4) != 0;
    // Public cartridge metadata assigns footer version bit 7 to software that
    // intentionally retains write access to the internal owner/telemetry area.
    const bool protect_owner_area = (rom[rom.size() - 7] & 0x80u) == 0;
    const auto boot = swan_song_open_ipl(
        selected_open_ipl_model, word_width, protect_owner_area);
    if (boot.empty()) {
      error = "SwanSong Open IPL exceeded its reserved boot-ROM window";
      release_active();
      return SWAN_RESULT_INTERNAL_ERROR;
    }
    system_pak_->append("boot.rom", std::span<const uint8_t>(boot));
    if (!is_pocket_challenge) {
      const size_t console_size = is_color_hardware ? 2048u : 128u;
      if (!append_persistence(*system_pak_, "save.eeprom", console_size,
                              SWAN_PERSISTENCE_CONSOLE_EEPROM, error)) {
        release_active();
        return SWAN_RESULT_INVALID_ARGUMENT;
      }
    }

    game_pak_->setAttribute("title", "SwanSong");
    const bool vertical = !is_pocket_challenge &&
                          (rom[rom.size() - 4] & 1) != 0;
    game_pak_->setAttribute("orientation", vertical ? "vertical" : "horizontal");
    game_pak_->setAttribute(
        "board", is_pocket_challenge ? "KARNAK"
                                     : info.mapper ? "2003" : "2001");
    game_pak_->setAttribute("width",
                            word_width ? "16" : "8");
    if (is_pocket_challenge) {
      if (auto staged = staged_persistence_.find(SWAN_PERSISTENCE_CARTRIDGE_FLASH);
          staged != staged_persistence_.end()) {
        if (staged->second.size() != rom.size() &&
            staged->second.size() != info.mapped_size) {
          error = "Pocket Challenge V2 flash size does not match the cartridge";
          release_active();
          return SWAN_RESULT_INVALID_ARGUMENT;
        }
        game_pak_->append("program.flash",
                          std::span<const uint8_t>(staged->second));
      } else {
        game_pak_->append("program.flash", rom);
      }
    } else {
      game_pak_->append("program.rom", rom);
    }

    const size_t storage_size = save_size(info.save_type);
    if (storage_size) {
      const bool is_eeprom = save_is_eeprom(info.save_type);
      if (!append_persistence(
              *game_pak_, is_eeprom ? "save.eeprom" : "save.ram",
              storage_size,
              is_eeprom ? SWAN_PERSISTENCE_CARTRIDGE_EEPROM
                         : SWAN_PERSISTENCE_CARTRIDGE_RAM,
              error)) {
        release_active();
        return SWAN_RESULT_INVALID_ARGUMENT;
      }
    }
    if (info.has_rtc &&
        config_.rtc_mode == SWAN_RTC_MODE_DETERMINISTIC &&
        !staged_persistence_.contains(SWAN_PERSISTENCE_RTC)) {
      auto rtc = deterministic_rtc(config_.rtc_seed_unix_seconds);
      if (rtc.empty()) {
        error = "the deterministic RTC seed is not a valid UTC timestamp";
        release_active();
        return SWAN_RESULT_INVALID_ARGUMENT;
      }
      staged_persistence_[SWAN_PERSISTENCE_RTC] = std::move(rtc);
    }
    if (info.has_rtc &&
        !append_persistence(*game_pak_, "time.rtc", 18u,
                            SWAN_PERSISTENCE_RTC, error)) {
      release_active();
      return SWAN_RESULT_INVALID_ARGUMENT;
    }

    if (!ares::WonderSwan::load(root_, selected_model)) {
      release_active();
      error = "ares rejected the selected WonderSwan model";
      return SWAN_RESULT_INTERNAL_ERROR;
    }
    if (auto port = root_->find<ares::Node::Port>("Cartridge Slot")) {
      port->allocate();
      port->connect();
    } else {
      root_->unload();
      root_.reset();
      release_active();
      error = "ares did not expose a WonderSwan cartridge slot";
      return SWAN_RESULT_INTERNAL_ERROR;
    }

    // The footer describes the cartridge's initial presentation. Keep that
    // seed separately so ares can remain in Automatic mode and honor later
    // LCD_ICON orientation changes made by the running game.
    initial_vertical_ = vertical;

    // The host applies its own optional LCD response profile. Keep the core
    // output deterministic and pixel-exact so save-state replay and captures
    // are not coupled to an unserialized frontend blending buffer.
    if (auto blending = root_->find<ares::Node::Setting::Boolean>(
            "PPU/Screen/Interframe Blending")) {
      blending->setValue(false);
    }

    loaded_ = true;
    staged_persistence_.clear();
    root_->power();
    initialize_frontend_presentation();
    return SWAN_RESULT_OK;
  }

  swan_result_t unload(std::string& error) override {
    if (root_) {
      root_->save();
      root_->unload();
      root_.reset();
    }
    loaded_ = false;
    initial_vertical_ = false;
    system_pak_.reset();
    game_pak_.reset();
    input_mask_.store(0, std::memory_order_relaxed);
    {
      std::lock_guard lock(video_mutex_);
      video_.clear();
      video_width_ = video_height_ = video_stride_ = 0;
      frame_number_ = 0;
    }
    {
      std::lock_guard lock(audio_mutex_);
      audio_.clear();
    }
    release_active();
    error.clear();
    return SWAN_RESULT_OK;
  }

  swan_result_t reset(std::string& error) override {
    if (!loaded_ || !root_) return SWAN_RESULT_NOT_LOADED;
    input_mask_.store(0, std::memory_order_relaxed);
    root_->power(true);
    initialize_frontend_presentation();
    {
      std::lock_guard lock(video_mutex_);
      video_.clear();
      video_width_ = video_height_ = video_stride_ = 0;
      frame_number_ = 0;
    }
    {
      std::lock_guard lock(audio_mutex_);
      audio_.clear();
    }
    error.clear();
    return SWAN_RESULT_OK;
  }

  swan_result_t set_input(uint32_t input_mask,
                          std::string& error) override {
    input_mask_.store(input_mask, std::memory_order_relaxed);
    error.clear();
    return SWAN_RESULT_OK;
  }

  swan_result_t run_frame(std::string& error) override {
    if (!loaded_ || !root_) return SWAN_RESULT_NOT_LOADED;

    uint64_t expected_frame;
    {
      std::lock_guard lock(video_mutex_);
      expected_frame = frame_number_ + 1;
    }
    {
      std::lock_guard lock(audio_mutex_);
      audio_.clear();
    }

    root_->run();

    std::unique_lock lock(video_mutex_);
    if (!video_ready_.wait_for(lock, kFrameTimeout, [&] {
          return frame_number_ >= expected_frame;
        })) {
      error = "ares completed a frame without producing video";
      return SWAN_RESULT_INTERNAL_ERROR;
    }
    error.clear();
    return SWAN_RESULT_OK;
  }

  swan_result_t video_frame(swan_video_frame_t& frame,
                            std::string& error) const override {
    if (!loaded_) return SWAN_RESULT_NOT_LOADED;
    std::lock_guard lock(video_mutex_);
    if (video_.empty()) {
      error = "ares has not produced a video frame yet";
      return SWAN_RESULT_INTERNAL_ERROR;
    }
    frame.pixels = video_.data();
    frame.byte_count = video_.size();
    frame.width = video_width_;
    frame.height = video_height_;
    frame.stride_bytes = video_stride_;
    frame.pixel_format = SWAN_PIXEL_FORMAT_BGRA8888;
    frame.orientation = video_height_ > video_width_
                            ? SWAN_ORIENTATION_VERTICAL
                            : SWAN_ORIENTATION_HORIZONTAL;
    frame.frame_number = frame_number_;
    error.clear();
    return SWAN_RESULT_OK;
  }

  swan_result_t audio_batch(swan_audio_batch_t& audio,
                            std::string& error) const override {
    if (!loaded_) return SWAN_RESULT_NOT_LOADED;
    std::lock_guard lock(audio_mutex_);
    audio.interleaved_samples = audio_.empty() ? nullptr : audio_.data();
    audio.frame_count = audio_.size() / 2;
    audio.channels = 2;
    audio.sample_rate = output_sample_rate();
    error.clear();
    return SWAN_RESULT_OK;
  }

  swan_result_t stage_persistence(swan_persistence_kind_t kind,
                                  std::span<const uint8_t> bytes,
                                  std::string& error) override {
    if (loaded_) {
      error = "persistent data must be staged before loading the ROM";
      return SWAN_RESULT_UNSUPPORTED;
    }
    if (!valid_persistence_kind(kind) || bytes.empty()) {
      error = "invalid persistent data region";
      return SWAN_RESULT_INVALID_ARGUMENT;
    }
    try {
      staged_persistence_[kind] = std::vector<uint8_t>(bytes.begin(), bytes.end());
    } catch (...) {
      error = "could not retain persistent data";
      return SWAN_RESULT_INTERNAL_ERROR;
    }
    error.clear();
    return SWAN_RESULT_OK;
  }

  swan_result_t persistence_size(swan_persistence_kind_t kind,
                                 size_t& size,
                                 std::string& error) override {
    if (!loaded_ || !root_) return SWAN_RESULT_NOT_LOADED;
    root_->save();
    auto file = persistence_file(kind);
    if (!file) {
      error = "the loaded cartridge does not expose that persistence region";
      return SWAN_RESULT_UNSUPPORTED;
    }
    size = static_cast<size_t>(file->size());
    error.clear();
    return SWAN_RESULT_OK;
  }

  swan_result_t read_persistence(swan_persistence_kind_t kind,
                                 std::span<uint8_t> bytes,
                                 size_t& size,
                                 std::string& error) override {
    if (!loaded_ || !root_) return SWAN_RESULT_NOT_LOADED;
    root_->save();
    auto file = persistence_file(kind);
    if (!file) {
      error = "the loaded cartridge does not expose that persistence region";
      return SWAN_RESULT_UNSUPPORTED;
    }
    size = static_cast<size_t>(file->size());
    if (bytes.size() < size) {
      error = "persistence output buffer is too small";
      return SWAN_RESULT_INVALID_ARGUMENT;
    }
    file->seek(0);
    file->read(bytes.data(), size);
    error.clear();
    return SWAN_RESULT_OK;
  }

  swan_result_t memory_size(swan_memory_region_t region,
                            size_t& size,
                            std::string& error) override {
    if (!loaded_ || !root_) return SWAN_RESULT_NOT_LOADED;
    if (region != SWAN_MEMORY_INTERNAL_RAM) {
      error = "the requested WonderSwan memory region is unsupported";
      return SWAN_RESULT_UNSUPPORTED;
    }
    size = ares::WonderSwan::SoC::ASWAN() ? 16u * 1024u : 64u * 1024u;
    error.clear();
    return SWAN_RESULT_OK;
  }

  swan_result_t read_memory(swan_memory_region_t region,
                            std::span<uint8_t> bytes,
                            size_t& size,
                            std::string& error) override {
    const auto size_result = memory_size(region, size, error);
    if (size_result != SWAN_RESULT_OK) return size_result;
    if (bytes.size() < size) {
      error = "memory output buffer is too small";
      return SWAN_RESULT_INVALID_ARGUMENT;
    }
    for (size_t address = 0; address < size; ++address) {
      bytes[address] = ares::WonderSwan::iram.read(static_cast<uint16_t>(address));
    }
    error.clear();
    return SWAN_RESULT_OK;
  }

  swan_result_t capture_state(std::vector<uint8_t>& state,
                              std::string& error) override {
    if (!loaded_ || !root_) return SWAN_RESULT_NOT_LOADED;
    auto serialized = root_->serialize(true);
    if (!serialized || serialized.size() == 0) {
      error = "ares could not synchronize a WonderSwan save state";
      return SWAN_RESULT_INTERNAL_ERROR;
    }
    try {
      state.assign(serialized.data(), serialized.data() + serialized.size());
    } catch (...) {
      error = "could not retain the serialized WonderSwan state";
      return SWAN_RESULT_INTERNAL_ERROR;
    }
    error.clear();
    return SWAN_RESULT_OK;
  }

  swan_result_t restore_state(std::span<const uint8_t> state,
                              std::string& error) override {
    if (!loaded_ || !root_) return SWAN_RESULT_NOT_LOADED;
    if (state.empty() || state.size() > std::numeric_limits<u32>::max()) {
      error = "save-state data has an invalid size";
      return SWAN_RESULT_INVALID_ARGUMENT;
    }
    serializer serialized(state.data(), static_cast<u32>(state.size()));
    if (!root_->unserialize(serialized)) {
      error = "save state is incompatible with this ares WonderSwan core";
      return SWAN_RESULT_UNSUPPORTED;
    }
    // Node sprites and screen rotation are frontend presentation state rather
    // than serialized pixels. Refresh them from the restored LCD/PPU state so
    // loading a state can also restore a runtime orientation change.
    ares::WonderSwan::ppu.updateIcons();
    ares::WonderSwan::ppu.updateOrientation();
    {
      std::lock_guard lock(audio_mutex_);
      audio_.clear();
    }
    error.clear();
    return SWAN_RESULT_OK;
  }

 private:
  void initialize_frontend_presentation() {
    if (!root_) return;
    // ares powers the PPU before the APU. The PPU's initial icon refresh
    // therefore observes zeroed volume/headphone state even though the APU
    // immediately establishes the model defaults afterward. Refresh the
    // frontend-only sprites once all emulated components have powered.
    ares::WonderSwan::ppu.updateIcons();
    auto orientation = root_->find<ares::Node::Setting::String>(
        "PPU/Screen/Orientation");
    if (!orientation) return;

    // PPU::power() resets the emulated orientation latch to horizontal. Seed
    // that latch from the cartridge metadata before the first video frame,
    // then leave the setting on Automatic so LCD_ICON writes rotate live.
    ares::WonderSwan::ppu.io.orientation = initial_vertical_ ? 1 : 0;
    orientation->setValue("Automatic");
    ares::WonderSwan::ppu.updateOrientation();
  }

  uint32_t output_sample_rate() const {
    return config_.output_sample_rate ? config_.output_sample_rate : 48'000u;
  }

  void release_active() {
    std::lock_guard lock(active_mutex_);
    if (active_ == this) {
      active_ = nullptr;
      if (ares::platform == this) ares::platform = nullptr;
    }
  }

  static bool valid_persistence_kind(swan_persistence_kind_t kind) {
    return kind >= SWAN_PERSISTENCE_CONSOLE_EEPROM &&
           kind <= SWAN_PERSISTENCE_RTC;
  }

  bool append_persistence(vfs::directory& directory,
                          const char* name,
                          size_t expected_size,
                          swan_persistence_kind_t kind,
                          std::string& error) {
    if (auto staged = staged_persistence_.find(kind);
        staged != staged_persistence_.end()) {
      if (staged->second.size() != expected_size) {
        error = "persistent data size does not match the loaded cartridge";
        return false;
      }
      if (!directory.append(name, std::span<const uint8_t>(staged->second))) {
        return false;
      }
      if (auto file = directory.read(name)) file->setAttribute("loaded", true);
      return true;
    }
    return directory.append(name, expected_size);
  }

  std::shared_ptr<vfs::file> persistence_file(swan_persistence_kind_t kind) {
    switch (kind) {
      case SWAN_PERSISTENCE_CONSOLE_EEPROM:
        return system_pak_ ? system_pak_->read("save.eeprom") : nullptr;
      case SWAN_PERSISTENCE_CARTRIDGE_RAM:
        return game_pak_ ? game_pak_->read("save.ram") : nullptr;
      case SWAN_PERSISTENCE_CARTRIDGE_EEPROM:
        return game_pak_ ? game_pak_->read("save.eeprom") : nullptr;
      case SWAN_PERSISTENCE_CARTRIDGE_FLASH:
        return game_pak_ ? game_pak_->read("program.flash") : nullptr;
      case SWAN_PERSISTENCE_RTC:
        return game_pak_ ? game_pak_->read("time.rtc") : nullptr;
    }
    return nullptr;
  }

  std::shared_ptr<vfs::directory> pak(ares::Node::Object node) override {
    if (root_ && node.get() == root_.get()) return system_pak_;
    return game_pak_;
  }

  auto rtcTime() -> u64 override {
    if (config_.rtc_mode == SWAN_RTC_MODE_DETERMINISTIC) {
      return config_.rtc_seed_unix_seconds;
    }
    return chrono::timestamp();
  }

  void attach(ares::Node::Object node) override {
    if (auto stream = node->cast<ares::Node::Audio::Stream>()) {
      stream->setResamplerFrequency(output_sample_rate());
    }
  }

  void video(ares::Node::Video::Screen,
             const u32* data,
             u32 pitch,
             u32 width,
             u32 height) override {
    std::lock_guard lock(video_mutex_);
    video_width_ = width;
    video_height_ = height;
    video_stride_ = width * sizeof(uint32_t);
    video_.resize(static_cast<size_t>(video_stride_) * height);
    for (uint32_t row = 0; row < height; ++row) {
      std::memcpy(video_.data() + static_cast<size_t>(row) * video_stride_,
                  reinterpret_cast<const uint8_t*>(data) +
                      static_cast<size_t>(row) * pitch,
                  video_stride_);
    }
    ++frame_number_;
    video_ready_.notify_all();
  }

  void audio(ares::Node::Audio::Stream stream) override {
    std::lock_guard lock(audio_mutex_);
    while (stream->pending()) {
      f64 samples[2] = {0.0, 0.0};
      const u32 channels = stream->read(samples);
      const float left = static_cast<float>(std::clamp(samples[0], -1.0, 1.0));
      const float right = static_cast<float>(std::clamp(
          channels > 1 ? samples[1] : samples[0], -1.0, 1.0));
      audio_.push_back(left);
      audio_.push_back(right);
    }
  }

  void input(ares::Node::Input::Input node) override {
    auto button = node->cast<ares::Node::Input::Button>();
    if (!button) return;

    const auto name = node->name();
    uint32_t bits = 0;
    if (name == "Y1") bits = SWAN_INPUT_Y1;
    else if (name == "Y2") bits = SWAN_INPUT_Y2;
    else if (name == "Y3") bits = SWAN_INPUT_Y3;
    else if (name == "Y4") bits = SWAN_INPUT_Y4;
    else if (name == "X1") bits = SWAN_INPUT_X1;
    else if (name == "X2") bits = SWAN_INPUT_X2;
    else if (name == "X3") bits = SWAN_INPUT_X3;
    else if (name == "X4") bits = SWAN_INPUT_X4;
    else if (name == "B") bits = SWAN_INPUT_B;
    else if (name == "A") bits = SWAN_INPUT_A;
    else if (name == "Start") bits = SWAN_INPUT_START;
    else if (name == "Volume") bits = SWAN_INPUT_VOLUME;
    else if (name == "Up") {
      bits = SWAN_INPUT_POCKET_CHALLENGE_UP | SWAN_INPUT_X1;
    } else if (name == "Right") {
      bits = SWAN_INPUT_POCKET_CHALLENGE_RIGHT | SWAN_INPUT_X2;
    } else if (name == "Down") {
      bits = SWAN_INPUT_POCKET_CHALLENGE_DOWN | SWAN_INPUT_X3;
    } else if (name == "Left") {
      bits = SWAN_INPUT_POCKET_CHALLENGE_LEFT | SWAN_INPUT_X4;
    } else if (name == "Pass") {
      bits = SWAN_INPUT_POCKET_CHALLENGE_PASS | SWAN_INPUT_B;
    } else if (name == "Circle") {
      bits = SWAN_INPUT_POCKET_CHALLENGE_CIRCLE | SWAN_INPUT_A;
    } else if (name == "Clear") {
      bits = SWAN_INPUT_POCKET_CHALLENGE_CLEAR | SWAN_INPUT_START;
    } else if (name == "View") {
      bits = SWAN_INPUT_POCKET_CHALLENGE_VIEW | SWAN_INPUT_VOLUME;
    } else if (name == "Escape") {
      bits = SWAN_INPUT_POCKET_CHALLENGE_ESCAPE;
    } else if (name == "Power") {
      bits = SWAN_INPUT_POWER;
    }

    button->setValue((input_mask_.load(std::memory_order_relaxed) & bits) != 0);
  }

  inline static std::mutex active_mutex_;
  inline static AresBackend* active_ = nullptr;

  swan_engine_config_t config_{};
  ares::Node::System root_;
  std::shared_ptr<vfs::directory> system_pak_;
  std::shared_ptr<vfs::directory> game_pak_;
  std::map<swan_persistence_kind_t, std::vector<uint8_t>> staged_persistence_;
  std::atomic<uint32_t> input_mask_{0};
  bool loaded_ = false;
  bool initial_vertical_ = false;

  mutable std::mutex video_mutex_;
  mutable std::condition_variable video_ready_;
  std::vector<uint8_t> video_;
  uint32_t video_width_ = 0;
  uint32_t video_height_ = 0;
  uint32_t video_stride_ = 0;
  uint64_t frame_number_ = 0;

  mutable std::mutex audio_mutex_;
  std::vector<float> audio_;
};

}  // namespace

std::unique_ptr<SwanEngineBackend> create_swan_engine_backend(
    const swan_engine_config_t& config) {
  return std::make_unique<AresBackend>(config);
}

#endif
