#include "swan_engine.h"

// When SWAN_ARES_ENGINE_DIR is set, SwiftPM compiles this tiny module and
// resolves the public C ABI from the CMake-built dylib.
const unsigned swan_engine_swift_module_anchor = SWAN_ENGINE_ABI_VERSION;
