#include <ares/ares.hpp>
#include "v30mz.hpp"

#include <algorithm>
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

struct SealedInstruction {
  std::vector<ConsumedByte> bytes;
  u8 terminalOpcode = 0;
  bool continuing = false;
};

struct ControlCPU final : ares::V30MZ {
  std::array<std::array<u8, 0x10000>, 3> banks{};
  std::vector<OriginFact> origins{{}};
  std::vector<ConsumedByte> consumed;
  std::vector<ConsumedByte> schedulerPass;
  std::vector<ConsumedByte> retainedPrefixes;
  std::vector<SealedInstruction> sealed;
  std::vector<u64> discardedOrigins;
  u16 mapperBank = 1;
  u32 flushGeneration = 0;
  u32 flushCount = 0;
  bool callbackInvalid = false;
  bool boundaryInvalid = false;

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
    ConsumedByte byte{
      static_cast<u32>(origin >> 32),
      static_cast<u32>(origin),
      segment,
      offset,
      value,
    };
    consumed.push_back(byte);
    schedulerPass.push_back(byte);
  }

  auto provenanceInstructionBoundary(
    u8 terminalOpcode,
    u64 terminalOrigin,
    bool continuing
  ) -> void override {
    if(schedulerPass.empty() ||
       schedulerPass.front().originID != static_cast<u32>(terminalOrigin) ||
       schedulerPass.front().generation != static_cast<u32>(terminalOrigin >> 32) ||
       schedulerPass.front().value != terminalOpcode) {
      boundaryInvalid = true;
      schedulerPass.clear();
      retainedPrefixes.clear();
      return;
    }
    const bool prefix = terminalOpcode == 0x26 || terminalOpcode == 0x2e ||
                        terminalOpcode == 0x36 || terminalOpcode == 0x3e ||
                        terminalOpcode == 0xf0 || terminalOpcode == 0xf2 ||
                        terminalOpcode == 0xf3;
    if(prefix) {
      if(!continuing || schedulerPass.size() != 1) boundaryInvalid = true;
      retainedPrefixes.insert(
        retainedPrefixes.end(), schedulerPass.begin(), schedulerPass.end()
      );
      schedulerPass.clear();
      return;
    }
    SealedInstruction instruction;
    instruction.bytes = retainedPrefixes;
    instruction.bytes.insert(
      instruction.bytes.end(), schedulerPass.begin(), schedulerPass.end()
    );
    instruction.terminalOpcode = terminalOpcode;
    instruction.continuing = continuing;
    sealed.push_back(std::move(instruction));
    schedulerPass.clear();
    if(!continuing) retainedPrefixes.clear();
  }

  auto provenancePrefetchDiscard(u64 origin) -> void override {
    discardedOrigins.push_back(origin);
  }

  auto provenancePrefetchFlush(u32 generation) -> void override {
    flushGeneration = generation;
    flushCount++;
    retainedPrefixes.clear();
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
    schedulerPass.clear();
    retainedPrefixes.clear();
    sealed.clear();
    discardedOrigins.clear();
    flushGeneration = prefetchGeneration;
    flushCount = 0;
    callbackInvalid = false;
    boundaryInvalid = false;
  }

  auto isSingleContiguousOriginRun() const -> bool {
    if(consumed.empty() || callbackInvalid || boundaryInvalid || prefetchOriginInvalid) return false;
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

auto runPrefixRepeat(u64& digest) -> bool {
  ControlCPU cpu;
  cpu.banks[1][0x0000] = 0xf3;  //REP
  cpu.banks[1][0x0001] = 0xa4;  //MOVSB
  cpu.banks[1][0x0002] = 0xf4;  //HLT
  cpu.resetAtCartridgeWindow();
  cpu.CW = 2;
  cpu.DS0 = 0;
  cpu.DS1 = 0;
  cpu.IX = 0;
  cpu.IY = 0;

  cpu.instruction();  //prefix scheduler pass
  if(!cpu.sealed.empty() || cpu.retainedPrefixes.size() != 1) return false;
  cpu.instruction();  //first REP element
  cpu.instruction();  //second REP element

  if(cpu.boundaryInvalid || cpu.callbackInvalid || cpu.sealed.size() != 2) return false;
  const auto& first = cpu.sealed[0];
  const auto& second = cpu.sealed[1];
  if(!first.continuing || second.continuing ||
     first.terminalOpcode != 0xa4 || second.terminalOpcode != 0xa4 ||
     first.bytes.size() != 2 || second.bytes.size() != 2) return false;
  if(first.bytes[0].value != 0xf3 || second.bytes[0].value != 0xf3 ||
     first.bytes[1].value != 0xa4 || second.bytes[1].value != 0xa4) return false;
  if(first.bytes[0].originID != second.bytes[0].originID ||
     first.bytes[1].originID != second.bytes[1].originID) return false;
  for(const auto& byte : first.bytes) {
    if(byte.originID == 0 || byte.originID >= cpu.origins.size()) return false;
    const auto& fact = cpu.origins[byte.originID];
    if(fact.bank != 1) return false;
    mix(digest, byte.generation);
    mix(digest, fact.cartridgeOffset);
  }
  mix(digest, first.continuing);
  mix(digest, second.continuing);
  return true;
}

auto runRepeatDiscard(u64& digest) -> bool {
  ControlCPU cpu;
  cpu.banks[1][0x0000] = 0xf3;  //REP
  cpu.banks[1][0x0001] = 0xa4;  //MOVSB
  cpu.banks[1][0x0002] = 0xf4;  //HLT
  cpu.resetAtCartridgeWindow();
  cpu.CW = 64;
  cpu.DS0 = 0;
  cpu.DS1 = 0;
  cpu.IX = 0;
  cpu.IY = 0;

  cpu.instruction();  //prefix scheduler pass
  for(u32 index = 0; index < 64; index++) cpu.instruction();

  if(cpu.callbackInvalid || cpu.boundaryInvalid ||
     cpu.discardedOrigins.empty() || cpu.sealed.size() != 64) return false;
  for(const auto token : cpu.discardedOrigins) {
    const auto generation = static_cast<u32>(token >> 32);
    const auto originID = static_cast<u32>(token);
    if(generation == 0 || originID == 0 || originID >= cpu.origins.size()) {
      return false;
    }
    if(std::any_of(cpu.consumed.begin(), cpu.consumed.end(),
        [&](const auto& byte) {
          return byte.generation == generation && byte.originID == originID;
        })) return false;
  }
  mix(digest, cpu.discardedOrigins.size());
  mix(digest, static_cast<u32>(cpu.discardedOrigins.front()));
  return true;
}

auto runFlushClearsRepeatContext(u64& digest) -> bool {
  ControlCPU cpu;
  cpu.banks[1][0x0000] = 0xf3;  //REP
  cpu.banks[1][0x0001] = 0xa4;  //MOVSB
  cpu.banks[1][0x0100] = 0x90;  //synthetic interrupt-handler NOP
  cpu.resetAtCartridgeWindow();
  cpu.CW = 2;
  cpu.DS0 = 0;
  cpu.DS1 = 0;
  cpu.IX = 0;
  cpu.IY = 0;

  cpu.instruction();  //prefix scheduler pass
  cpu.instruction();  //first REP element
  if(cpu.retainedPrefixes.size() != 1 || cpu.sealed.size() != 1 ||
     !cpu.sealed.front().continuing) return false;

  const auto priorGeneration = cpu.prefetchGeneration;
  cpu.state.prefix = 0;
  cpu.prefixFlush();
  cpu.PS = 0x2000;
  cpu.PC = 0x0100;
  cpu.flush();
  if(cpu.flushCount != 1 || cpu.flushGeneration != cpu.prefetchGeneration ||
     cpu.prefetchGeneration != priorGeneration + 1 ||
     !cpu.retainedPrefixes.empty()) return false;

  cpu.instruction();
  if(cpu.boundaryInvalid || cpu.callbackInvalid || cpu.sealed.size() != 2 ||
     cpu.sealed.back().bytes.size() != 1 ||
     cpu.sealed.back().terminalOpcode != 0x90) return false;
  mix(digest, cpu.flushGeneration);
  mix(digest, cpu.sealed.back().bytes.size());
  return true;
}

auto runQueueMismatchStop(u64& digest) -> bool {
  ControlCPU cpu;
  cpu.banks[1][0x0000] = 0x90;  //NOP
  cpu.resetAtCartridgeWindow();
  cpu.prefetch();
  cpu.PFO.flush();
  cpu.instruction();
  if(!cpu.callbackInvalid || !cpu.prefetchOriginInvalid) return false;
  mix(digest, cpu.callbackInvalid);
  mix(digest, cpu.prefetchOriginInvalid);
  return true;
}

auto runRestoreInvalidationStop(u64& digest) -> bool {
  ControlCPU cpu;
  cpu.banks[1][0x0000] = 0x90;  //NOP
  cpu.banks[1][0x0001] = 0xf4;  //HLT
  cpu.resetAtCartridgeWindow();
  cpu.prefetch();

  if(cpu.PF.size() != 1 || cpu.PFO.size() != 1) return false;
  const auto savedByte = cpu.PF.peek();
  const auto savedOrigin = cpu.PFO.peek();

  nall::serializer snapshot;
  cpu.serialize(snapshot);
  if(snapshot.size() == 0) return false;

  cpu.PF.flush();
  cpu.PFO.flush();
  cpu.callbackInvalid = false;
  cpu.prefetchOriginInvalid = false;

  nall::serializer restore(snapshot.data(), snapshot.size());
  cpu.serialize(restore);
  if(!cpu.callbackInvalid || !cpu.prefetchOriginInvalid) return false;
  if(cpu.PF.size() != 1 || cpu.PFO.size() != 1 ||
     cpu.PF.peek() != savedByte || cpu.PFO.peek() != savedOrigin) return false;

  cpu.consumed.clear();
  cpu.schedulerPass.clear();
  cpu.instruction();
  if(cpu.consumed.size() != 1 || cpu.isSingleContiguousOriginRun()) return false;

  mix(digest, savedByte);
  mix(digest, static_cast<u32>(savedOrigin >> 32));
  mix(digest, cpu.callbackInvalid);
  mix(digest, cpu.prefetchOriginInvalid);
  return true;
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
  if(!runPrefixRepeat(digest)) {
    std::fputs("prefix/REP logical-boundary control failed\n", stderr);
    return 1;
  }
  if(!runRepeatDiscard(digest)) {
    std::fputs("REP discarded-origin pruning control failed\n", stderr);
    return 1;
  }
  if(!runFlushClearsRepeatContext(digest)) {
    std::fputs("prefetch flush generation/context control failed\n", stderr);
    return 1;
  }
  if(!runQueueMismatchStop(digest)) {
    std::fputs("prefetch queue mismatch STOP control failed\n", stderr);
    return 1;
  }
  if(!runRestoreInvalidationStop(digest)) {
    std::fputs("save-state restore invalidation STOP control failed\n", stderr);
    return 1;
  }
  std::printf(
    "PASS consumed-prefetch-v4 retained-origin=1 mixed-origin-stop=1 prefix-rep=1 rep-discard=1 flush-generation=1 queue-mismatch-stop=1 restore-invalidation-stop=1 trace=%016llx\n",
    static_cast<unsigned long long>(digest)
  );
  return 0;
}
