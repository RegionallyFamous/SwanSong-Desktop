#include "swan_engine.h"

#include <algorithm>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <random>
#include <vector>

namespace {

constexpr size_t kMaximumInputBytes = 17u * 1024u * 1024u;
constexpr size_t kMaximumCoverageEdges = 1u << 20;
bool seen_coverage[kMaximumCoverageEdges]{};
bool found_new_coverage = false;

}  // namespace

extern "C" __attribute__((no_sanitize("coverage")))
void __sanitizer_cov_trace_pc_guard_init(uint32_t* start, uint32_t* stop) {
  if (start == stop || *start != 0) return;
  uint32_t identifier = 1;
  for (uint32_t* guard = start; guard < stop; ++guard) {
    *guard = identifier++;
  }
}

extern "C" __attribute__((no_sanitize("coverage")))
void __sanitizer_cov_trace_pc_guard(uint32_t* guard) {
  const size_t identifier = *guard;
  if (identifier == 0 || identifier >= kMaximumCoverageEdges) return;
  if (!seen_coverage[identifier]) {
    seen_coverage[identifier] = true;
    found_new_coverage = true;
  }
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  swan_rom_info_t information{};
  information.struct_size = sizeof(information);
  (void)swan_inspect_rom(data, size, &information);
  return 0;
}

int main(int argc, char** argv) {
  const int seconds = argc == 2 ? std::max(1, std::atoi(argv[1])) : 10;
  std::mt19937_64 random(0x5357414e534f4e47ULL);
  std::vector<std::vector<uint8_t>> corpus = {
      {},
      std::vector<uint8_t>(15, 0),
      std::vector<uint8_t>(16, 0),
      std::vector<uint8_t>(64u * 1024u, 0),
  };
  const auto deadline = std::chrono::steady_clock::now()
      + std::chrono::seconds(seconds);
  size_t executions = 0;

  while (std::chrono::steady_clock::now() < deadline) {
    std::vector<uint8_t> candidate = corpus[random() % corpus.size()];
    const size_t mutations = 1 + random() % 16;
    for (size_t mutation = 0; mutation < mutations; ++mutation) {
      const uint64_t operation = random() % 4;
      if (operation == 0 && candidate.size() < kMaximumInputBytes) {
        const size_t count = std::min<size_t>(
            1 + random() % 64,
            kMaximumInputBytes - candidate.size());
        const size_t offset = candidate.empty() ? 0 : random() % (candidate.size() + 1);
        candidate.insert(candidate.begin() + offset, count, static_cast<uint8_t>(random()));
      } else if (operation == 1 && !candidate.empty()) {
        candidate[random() % candidate.size()] ^= static_cast<uint8_t>(1u << (random() % 8));
      } else if (operation == 2 && !candidate.empty()) {
        candidate[random() % candidate.size()] = static_cast<uint8_t>(random());
      } else if (operation == 3 && !candidate.empty()) {
        const size_t offset = random() % candidate.size();
        const size_t count = std::min<size_t>(1 + random() % 32, candidate.size() - offset);
        candidate.erase(candidate.begin() + offset, candidate.begin() + offset + count);
      }
    }

    found_new_coverage = false;
    LLVMFuzzerTestOneInput(candidate.data(), candidate.size());
    ++executions;
    if (found_new_coverage && corpus.size() < 4096) {
      corpus.push_back(std::move(candidate));
    }
  }

  std::cout << "PASS " << executions << " executions, " << corpus.size()
            << " coverage-guided corpus entries\n";
  return 0;
}
