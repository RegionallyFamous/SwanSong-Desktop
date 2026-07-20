#include <ares/ares.hpp>
#include "v30mz.hpp"

#include <array>
#include <cstdint>
#include <cstdio>
#include <vector>

namespace {

struct OriginFact {
  u16 bank = 0;
  u32 physical = 0;
  u32 cartridgeOffset = 0;
};

struct ConsumedByte {
  u32 generation = 0;
  u32 originID = 0;
  u16 segment = 0;
  u16 offset = 0;
  u8 value = 0;
};

struct ControlCPU final : ares::V30MZ {
  std::array<std::array<u8, 0x10000>, 3> banks{};
  std::vector<OriginFact> origins{{}};
  std::vector<ConsumedByte> consumed;
  u16 mapperBank = 1;
  bool callbackInvalid = false;

  auto step(u32 = 1) -> void override {}
  auto width(n20) -> u32 override { return Byte; }
  auto speed(n20) -> n32 override { return 1; }

  auto read(n20 address) -> n8 override {
    auto physical = static_cast<u32>(address) & 0xfffff;
    if(physical >= 0x20000 && physical <= 0x2ffff) {
      return banks[mapperBank][physical & 0xffff];
    }
    return 0;
  }

  auto readPrefetch(n20 address, u32& origin) -> n8 override {
    auto physical = static_cast<u32>(address) & 0xfffff;
    origins.push_back({
      mapperBank,
      physical,
      static_cast<u32>(mapperBank) * 0x10000 + (physical & 0xffff),
    });
    origin = static_cast<u32>(origins.size() - 1);
    return read(address);
  }

  auto write(n20, n8) -> void override {}
  auto in(n16) -> n8 override { return 0; }
  auto out(n16 port, n8) -> void override {
    if(static_cast<u16>(port) == 0x00c0) mapperBank = 2;
  }
  auto ioWidth(n16) -> u32 override { return Byte; }
  auto ioSpeed(n16) -> n32 override { return 1; }

  auto provenanceInstructionFetch(
    u64 origin,
    u16 segment,
    u16 offset,
    u8 value
  ) -> void override {
    consumed.push_back({
      static_cast<u32>(origin >> 32),
      static_cast<u32>(origin),
      segment,
      offset,
      value,
    });
  }

  auto provenancePrefetchInvalid() -> void override {
    callbackInvalid = true;
  }

  auto resetAtCartridgeWindow() -> void {
    power();
    PS = 0x2000;
    PC = 0x0000;
    DS0 = 0x2000;
    mapperBank = 1;
    flush();
    consumed.clear();
  }

  auto isSingleContiguousOriginRun() const -> bool {
    if(consumed.empty() || callbackInvalid || prefetchOriginInvalid) return false;
    const auto generation = consumed.front().generation;
    const auto firstID = consumed.front().originID;
    if(firstID == 0 || firstID >= origins.size()) return false;
    const auto first = origins[firstID];
    for(u32 index = 0; index < consumed.size(); index++) {
      const auto& byte = consumed[index];
      if(byte.generation != generation || byte.originID == 0 ||
         byte.originID >= origins.size()) return false;
      const auto& fact = origins[byte.originID];
      if(fact.bank != first.bank ||
         fact.cartridgeOffset != first.cartridgeOffset + index ||
         byte.offset != static_cast<u16>(consumed.front().offset + index)) {
        return false;
      }
    }
    return true;
  }
};

auto mix(u64& digest, u64 value) -> void {
  digest ^= value;
  digest *= 1099511628211ull;
}

auto runPositive(u64& digest) -> bool {
  ControlCPU cpu;
  cpu.banks[1][0x0000] = 0xe6;  //OUT imm8, AL
  cpu.banks[1][0x0001] = 0xc0;  //fixture mapper port
  cpu.banks[1][0x0002] = 0xa0;  //MOV AL, moffs8
  cpu.banks[1][0x0003] = 0x00;
  cpu.banks[1][0x0004] = 0x01;
  cpu.banks[1][0x0005] = 0xf4;
  cpu.banks[2][0x0002] = 0xcc;  //must not replace retained code
  cpu.banks[2][0x0100] = 0x5a;  //must be read after the remap
  cpu.resetAtCartridgeWindow();

  cpu.instruction();
  if(cpu.mapperBank != 2) return false;
  cpu.consumed.clear();
  cpu.instruction();

  if(cpu.consumed.size() != 3 || !cpu.isSingleContiguousOriginRun()) return false;
  if(cpu.AL != cpu.banks[2][0x0100]) return false;
  for(const auto& byte : cpu.consumed) {
    const auto& fact = cpu.origins[byte.originID];
    if(fact.bank != 1) return false;
    mix(digest, byte.generation);
    mix(digest, fact.bank);
    mix(digest, fact.cartridgeOffset);
  }
  mix(digest, cpu.mapperBank);
  return true;
}

auto runMixedStop(u64& digest) -> bool {
  ControlCPU cpu;
  cpu.banks[1][0x0000] = 0xb0;  //MOV AL, imm8
  cpu.banks[2][0x0001] = 0x7f;
  cpu.resetAtCartridgeWindow();

  cpu.prefetch();
  cpu.mapperBank = 2;
  cpu.prefetch();
  cpu.consumed.clear();
  cpu.instruction();

  if(cpu.consumed.size() != 2 || cpu.isSingleContiguousOriginRun()) return false;
  const auto& first = cpu.origins[cpu.consumed[0].originID];
  const auto& second = cpu.origins[cpu.consumed[1].originID];
  if(first.bank == second.bank) return false;
  mix(digest, first.bank);
  mix(digest, second.bank);
  mix(digest, cpu.consumed.size());
  return true;
}

}  // namespace

int main() {
  u64 digest = 1469598103934665603ull;
  if(!runPositive(digest)) {
    std::fputs("positive consumed-prefetch remap control failed\n", stderr);
    return 1;
  }
  if(!runMixedStop(digest)) {
    std::fputs("mixed-origin STOP control failed\n", stderr);
    return 1;
  }
  std::printf(
    "PASS consumed-prefetch-v1 retained-origin=1 mixed-origin-stop=1 trace=%016llx\n",
    static_cast<unsigned long long>(digest)
  );
  return 0;
}
