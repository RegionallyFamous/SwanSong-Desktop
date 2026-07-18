import CSwanEngine
import Foundation

public struct ROMMetadata: Codable, Hashable, Sendable {
    public let fileSize: UInt64
    public let mappedSize: UInt64
    public let storedChecksum: UInt16
    public let computedChecksum: UInt16
    public let isColor: Bool
    public let saveType: UInt8
    public let mapper: UInt8
    public let romSizeCode: UInt8
    public let checksumIsValid: Bool
    public let footerIsValid: Bool
    public let usesCompactLayout: Bool
    public let hasRTC: Bool
}

public struct EngineCapabilities: OptionSet, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static let romInspection = Self(rawValue: UInt64(SWAN_CAPABILITY_ROM_INSPECTION))
    public static let execution = Self(rawValue: UInt64(SWAN_CAPABILITY_EXECUTION))
    public static let audio = Self(rawValue: UInt64(SWAN_CAPABILITY_AUDIO))
    public static let saveStates = Self(rawValue: UInt64(SWAN_CAPABILITY_SAVE_STATES))
    public static let persistence = Self(rawValue: UInt64(SWAN_CAPABILITY_PERSISTENCE))
    public static let debugger = Self(rawValue: UInt64(SWAN_CAPABILITY_DEBUGGER))
    public static let structuredTrace = Self(rawValue: UInt64(SWAN_CAPABILITY_STRUCTURED_TRACE))
    public static let pocketChallengeV2 = Self(rawValue: UInt64(SWAN_CAPABILITY_POCKET_CHALLENGE_V2))
    public static let displayProvenance = Self(
        rawValue: UInt64(SWAN_CAPABILITY_DISPLAY_PROVENANCE)
    )
    public static let displaySourceProvenance = Self(
        rawValue: UInt64(SWAN_CAPABILITY_DISPLAY_SOURCE_PROVENANCE)
    )
    public static let displaySourceComponentSelection = Self(
        rawValue: UInt64(SWAN_CAPABILITY_DISPLAY_SOURCE_COMPONENT_SELECTION)
    )
    public static let executedSourceReadContext = Self(
        rawValue: UInt64(SWAN_CAPABILITY_EXECUTED_SOURCE_READ_CONTEXT)
    )
    public static let displaySpriteAttributeProvenance = Self(
        rawValue: UInt64(SWAN_CAPABILITY_DISPLAY_SPRITE_ATTRIBUTE_PROVENANCE)
    )
}

public struct EngineInput: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let y1 = Self(rawValue: UInt32(SWAN_INPUT_Y1))
    public static let y2 = Self(rawValue: UInt32(SWAN_INPUT_Y2))
    public static let y3 = Self(rawValue: UInt32(SWAN_INPUT_Y3))
    public static let y4 = Self(rawValue: UInt32(SWAN_INPUT_Y4))
    public static let x1 = Self(rawValue: UInt32(SWAN_INPUT_X1))
    public static let x2 = Self(rawValue: UInt32(SWAN_INPUT_X2))
    public static let x3 = Self(rawValue: UInt32(SWAN_INPUT_X3))
    public static let x4 = Self(rawValue: UInt32(SWAN_INPUT_X4))
    public static let b = Self(rawValue: UInt32(SWAN_INPUT_B))
    public static let a = Self(rawValue: UInt32(SWAN_INPUT_A))
    public static let start = Self(rawValue: UInt32(SWAN_INPUT_START))
    public static let volume = Self(rawValue: UInt32(SWAN_INPUT_VOLUME))
    public static let power = Self(rawValue: UInt32(SWAN_INPUT_POWER))

    // Pocket Challenge V2 has a different physical keypad. Dedicated bits
    // keep all nine controls independently recordable in deterministic routes.
    public static let pocketChallengeUp = Self(
        rawValue: UInt32(SWAN_INPUT_POCKET_CHALLENGE_UP)
    )
    public static let pocketChallengeRight = Self(
        rawValue: UInt32(SWAN_INPUT_POCKET_CHALLENGE_RIGHT)
    )
    public static let pocketChallengeDown = Self(
        rawValue: UInt32(SWAN_INPUT_POCKET_CHALLENGE_DOWN)
    )
    public static let pocketChallengeLeft = Self(
        rawValue: UInt32(SWAN_INPUT_POCKET_CHALLENGE_LEFT)
    )
    public static let pocketChallengePass = Self(
        rawValue: UInt32(SWAN_INPUT_POCKET_CHALLENGE_PASS)
    )
    public static let pocketChallengeCircle = Self(
        rawValue: UInt32(SWAN_INPUT_POCKET_CHALLENGE_CIRCLE)
    )
    public static let pocketChallengeClear = Self(
        rawValue: UInt32(SWAN_INPUT_POCKET_CHALLENGE_CLEAR)
    )
    public static let pocketChallengeView = Self(
        rawValue: UInt32(SWAN_INPUT_POCKET_CHALLENGE_VIEW)
    )
    public static let pocketChallengeEscape = Self(
        rawValue: UInt32(SWAN_INPUT_POCKET_CHALLENGE_ESCAPE)
    )
}

public struct EngineVideoFrame: Sendable {
    public let pixels: Data
    public let width: Int
    public let height: Int
    public let strideBytes: Int
    public let isVertical: Bool
    public let number: UInt64

    public init(
        pixels: Data,
        width: Int,
        height: Int,
        strideBytes: Int,
        isVertical: Bool,
        number: UInt64
    ) {
        self.pixels = pixels
        self.width = width
        self.height = height
        self.strideBytes = strideBytes
        self.isVertical = isVertical
        self.number = number
    }
}

public struct EngineAudioBatch: Sendable {
    public let interleavedSamples: [Float]
    public let channels: Int
    public let sampleRate: Int

    public var frameCount: Int {
        guard channels > 0 else { return 0 }
        return interleavedSamples.count / channels
    }
}

public struct EngineDisplayRectangle: Codable, Equatable, Sendable {
    public let x: UInt16
    public let y: UInt16
    public let width: UInt16
    public let height: UInt16

    public init(x: UInt16, y: UInt16, width: UInt16, height: UInt16) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum EngineDisplayLayer: String, Codable, Sendable {
    case backdrop
    case screen1
    case screen2
    case sprite

    fileprivate init(cValue: swan_display_layer_t) throws {
        switch cValue {
        case SWAN_DISPLAY_LAYER_BACKDROP: self = .backdrop
        case SWAN_DISPLAY_LAYER_SCREEN_1: self = .screen1
        case SWAN_DISPLAY_LAYER_SCREEN_2: self = .screen2
        case SWAN_DISPLAY_LAYER_SPRITE: self = .sprite
        default:
            throw SwanEngineError(
                code: Int32(SWAN_RESULT_INTERNAL_ERROR.rawValue),
                detail: "The engine returned an unknown display layer."
            )
        }
    }
}

public enum EngineDisplaySourceKind: String, Codable, Sendable {
    case none
    case tilemap
    case sprite

    fileprivate init(cValue: swan_display_source_kind_t) throws {
        switch cValue {
        case SWAN_DISPLAY_SOURCE_NONE: self = .none
        case SWAN_DISPLAY_SOURCE_TILEMAP: self = .tilemap
        case SWAN_DISPLAY_SOURCE_SPRITE: self = .sprite
        default:
            throw SwanEngineError(
                code: Int32(SWAN_RESULT_INTERNAL_ERROR.rawValue),
                detail: "The engine returned an unknown display source kind."
            )
        }
    }
}

/// One private renderer observation for a native game-raster pixel. Addresses
/// and CPU writer identities must stay inside the translation project; public
/// automation surfaces expose only hashes and aggregate counts.
public struct EngineDisplayOwnerSample: Codable, Equatable, Sendable {
    public let x: UInt16
    public let y: UInt16
    public let layer: EngineDisplayLayer
    public let sourceKind: EngineDisplaySourceKind
    public let cellAddress: UInt16
    public let tileIndex: UInt16
    public let cellAttributes: UInt32
    public let rasterAddress: UInt16
    public let rasterByteCount: UInt8
    public let paletteIndex: UInt8
    public let paletteColor: UInt8
    public let paletteByteCount: UInt8
    public let paletteAddress: UInt32
    public let cellWriterPC: UInt32
    public let rasterWriterPC: UInt32
    public let paletteWriterPC: UInt32
    public let oamAddress: UInt16?
    public let oamByteCount: UInt8?
    public let oamWriterPC: UInt32?

    fileprivate init(cValue: swan_display_owner_sample_t) throws {
        x = cValue.x
        y = cValue.y
        layer = try EngineDisplayLayer(cValue: cValue.layer)
        sourceKind = try EngineDisplaySourceKind(cValue: cValue.source_kind)
        cellAddress = cValue.cell_address
        tileIndex = cValue.tile_index
        cellAttributes = cValue.cell_attributes
        rasterAddress = cValue.raster_address
        rasterByteCount = cValue.raster_byte_count
        paletteIndex = cValue.palette_index
        paletteColor = cValue.palette_color
        paletteByteCount = cValue.palette_byte_count
        paletteAddress = cValue.palette_address
        cellWriterPC = cValue.cell_writer_pc
        rasterWriterPC = cValue.raster_writer_pc
        paletteWriterPC = cValue.palette_writer_pc
        if cValue.oam_byte_count > 0 {
            oamAddress = cValue.oam_address
            oamByteCount = cValue.oam_byte_count
            oamWriterPC = cValue.oam_writer_pc
        } else {
            oamAddress = nil
            oamByteCount = nil
            oamWriterPC = nil
        }
    }
}

public enum EngineDisplaySourceComponent:
    String, CaseIterable, Codable, Equatable, Hashable, Sendable
{
    case mapCell
    case raster
    case palette
    case spriteAttribute

    fileprivate init(cValue: swan_display_source_component_t) throws {
        switch cValue {
        case SWAN_DISPLAY_SOURCE_COMPONENT_MAP_CELL: self = .mapCell
        case SWAN_DISPLAY_SOURCE_COMPONENT_RASTER: self = .raster
        case SWAN_DISPLAY_SOURCE_COMPONENT_PALETTE: self = .palette
        case SWAN_DISPLAY_SOURCE_COMPONENT_SPRITE_ATTRIBUTE: self = .spriteAttribute
        default:
            throw SwanEngineError(
                code: Int32(SWAN_RESULT_INTERNAL_ERROR.rawValue),
                detail: "The engine returned an unknown upstream source component."
            )
        }
    }

    fileprivate var cMask: UInt32 {
        switch self {
        case .mapCell: UInt32(SWAN_DISPLAY_SOURCE_COMPONENT_MASK_MAP_CELL)
        case .raster: UInt32(SWAN_DISPLAY_SOURCE_COMPONENT_MASK_RASTER)
        case .palette: UInt32(SWAN_DISPLAY_SOURCE_COMPONENT_MASK_PALETTE)
        case .spriteAttribute:
            UInt32(SWAN_DISPLAY_SOURCE_COMPONENT_MASK_SPRITE_ATTRIBUTE)
        }
    }
}

func engineDisplaySourceComponents(
    sourceKind: EngineDisplaySourceKind,
    rasterByteCount: UInt8,
    paletteByteCount: UInt8,
    oamByteCount: UInt8 = 0
) -> [EngineDisplaySourceComponent] {
    var components: [EngineDisplaySourceComponent] = []
    if sourceKind == .tilemap { components.append(.mapCell) }
    if sourceKind != .none, rasterByteCount > 0 { components.append(.raster) }
    if paletteByteCount > 0 { components.append(.palette) }
    if sourceKind == .sprite, oamByteCount > 0 { components.append(.spriteAttribute) }
    return components
}

func engineDisplaySourceComponents(
    for sample: EngineDisplayOwnerSample
) -> [EngineDisplaySourceComponent] {
    engineDisplaySourceComponents(
        sourceKind: sample.sourceKind,
        rasterByteCount: sample.rasterByteCount,
        paletteByteCount: sample.paletteByteCount,
        oamByteCount: sample.oamByteCount ?? 0
    )
}

public enum EngineDisplaySourceScope: String, Codable, Sendable {
    case selected
    case outsideConsumer

    fileprivate init(cValue: swan_display_source_scope_t) throws {
        switch cValue {
        case SWAN_DISPLAY_SOURCE_SCOPE_SELECTED: self = .selected
        case SWAN_DISPLAY_SOURCE_SCOPE_OUTSIDE_CONSUMER: self = .outsideConsumer
        default:
            throw SwanEngineError(
                code: Int32(SWAN_RESULT_INTERNAL_ERROR.rawValue),
                detail: "The engine returned an unknown upstream source scope."
            )
        }
    }
}

/// One private dataflow edge from a final display byte to a half-open range in
/// the original cartridge file. Emulated addresses and exact ROM offsets must
/// remain inside the translation project.
public struct EngineExecutedSourceReadContext: Codable, Equatable, Sendable {
    public let immediateCaller: UInt32
    public let callerSegment: UInt16
    public let callerOffset: UInt16
    public let operandSegment: UInt16
    public let operandOffset: UInt16
    public let mapperWindow: UInt16
    public let mapperBank: UInt16
    public let resolvedCartridgeOperand: UInt32

    fileprivate init(cValue: swan_display_source_trace_t) {
        immediateCaller = cValue.immediate_caller
        callerSegment = cValue.caller_segment
        callerOffset = cValue.caller_offset
        operandSegment = cValue.operand_segment
        operandOffset = cValue.operand_offset
        mapperWindow = cValue.mapper_window
        mapperBank = cValue.mapper_bank
        resolvedCartridgeOperand = cValue.resolved_cartridge_operand
    }
}

public enum EngineDisplaySourceConservativeReason: String, Codable, Equatable, Sendable {
    case unclassifiedInstruction

    fileprivate init(cValue: swan_display_source_conservative_reason_t) throws {
        switch cValue {
        case SWAN_DISPLAY_SOURCE_CONSERVATIVE_UNCLASSIFIED_INSTRUCTION:
            self = .unclassifiedInstruction
        default:
            throw SwanEngineError(
                code: Int32(SWAN_RESULT_INTERNAL_ERROR.rawValue),
                detail: "The engine returned an unknown conservative-dataflow reason."
            )
        }
    }
}

/// Private identity of the first instruction that forced otherwise physical
/// cartridge lineage to remain conservative. Never expose these CPU values
/// through an automation response.
public struct EngineDisplaySourceConservativeOrigin: Codable, Equatable, Sendable {
    public let reason: EngineDisplaySourceConservativeReason
    public let origin20Bit: UInt32
    public let segment: UInt16
    public let offset: UInt16

    fileprivate init(cValue: swan_display_source_trace_t) throws {
        reason = try EngineDisplaySourceConservativeReason(
            cValue: cValue.conservative_reason
        )
        origin20Bit = cValue.conservative_origin
        segment = cValue.conservative_origin_segment
        offset = cValue.conservative_origin_offset
        let expected = UInt32(
            ((UInt64(segment) << 4) + UInt64(offset)) & 0xF_FFFF
        )
        guard origin20Bit == expected else {
            throw SwanEngineError(
                code: Int32(SWAN_RESULT_INTERNAL_ERROR.rawValue),
                detail: "The engine returned an inconsistent conservative-dataflow origin."
            )
        }
    }
}

public struct EngineDisplaySourceTrace: Codable, Equatable, Sendable {
    public let x: UInt16
    public let y: UInt16
    public let scope: EngineDisplaySourceScope
    public let component: EngineDisplaySourceComponent
    public let sourceAddress: UInt32
    public let sourceByteCount: UInt16
    public let minimumInstructionHops: UInt16
    public let maximumInstructionHops: UInt16
    public let cartridgeOffset: UInt32
    public let cartridgeLength: UInt32
    public let hasExactRange: Bool
    public let isTransformed: Bool
    public let hasUnknownDependency: Bool
    public let rangeSetOverflowed: Bool
    public let usesConservativeDataflow: Bool
    public let executedReadContext: EngineExecutedSourceReadContext?
    public let conservativeOrigin: EngineDisplaySourceConservativeOrigin?

    fileprivate init(cValue: swan_display_source_trace_t) throws {
        x = cValue.x
        y = cValue.y
        scope = try EngineDisplaySourceScope(cValue: cValue.scope)
        component = try EngineDisplaySourceComponent(cValue: cValue.component)
        sourceAddress = cValue.source_address
        sourceByteCount = cValue.source_byte_count
        minimumInstructionHops = cValue.minimum_instruction_hops
        maximumInstructionHops = cValue.maximum_instruction_hops
        cartridgeOffset = cValue.cartridge_offset
        cartridgeLength = cValue.cartridge_length
        let flags = cValue.flags
        hasExactRange = flags & UInt32(SWAN_DISPLAY_SOURCE_FLAG_EXACT) != 0
        isTransformed = flags & UInt32(SWAN_DISPLAY_SOURCE_FLAG_TRANSFORMED) != 0
        hasUnknownDependency = flags & UInt32(SWAN_DISPLAY_SOURCE_FLAG_UNKNOWN_DEPENDENCY) != 0
        rangeSetOverflowed = flags & UInt32(SWAN_DISPLAY_SOURCE_FLAG_RANGE_OVERFLOW) != 0
        usesConservativeDataflow = flags
            & UInt32(SWAN_DISPLAY_SOURCE_FLAG_CONSERVATIVE_DATAFLOW) != 0
        if cValue.read_context_flags
            & UInt32(SWAN_DISPLAY_SOURCE_READ_CONTEXT_EXECUTED) != 0 {
            executedReadContext = EngineExecutedSourceReadContext(cValue: cValue)
        } else {
            executedReadContext = nil
        }
        if cValue.conservative_reason != SWAN_DISPLAY_SOURCE_CONSERVATIVE_NONE {
            conservativeOrigin = try EngineDisplaySourceConservativeOrigin(cValue: cValue)
        } else {
            conservativeOrigin = nil
        }
        guard usesConservativeDataflow == (conservativeOrigin != nil) else {
            throw SwanEngineError(
                code: Int32(SWAN_RESULT_INTERNAL_ERROR.rawValue),
                detail: "The engine returned inconsistent conservative-dataflow evidence."
            )
        }
    }
}

public enum EnginePersistenceKind: String, CaseIterable, Codable, Sendable {
    case consoleEEPROM
    case cartridgeRAM
    case cartridgeEEPROM
    case cartridgeFlash
    case rtc

    fileprivate var cValue: swan_persistence_kind_t {
        switch self {
        case .consoleEEPROM: SWAN_PERSISTENCE_CONSOLE_EEPROM
        case .cartridgeRAM: SWAN_PERSISTENCE_CARTRIDGE_RAM
        case .cartridgeEEPROM: SWAN_PERSISTENCE_CARTRIDGE_EEPROM
        case .cartridgeFlash: SWAN_PERSISTENCE_CARTRIDGE_FLASH
        case .rtc: SWAN_PERSISTENCE_RTC
        }
    }
}

public struct EnginePersistence: Sendable {
    public var regions: [EnginePersistenceKind: Data]

    public init(regions: [EnginePersistenceKind: Data] = [:]) {
        self.regions = regions
    }
}

public enum EngineMemoryRegion: String, CaseIterable, Codable, Sendable {
    case internalRAM

    fileprivate var cValue: swan_memory_region_t {
        switch self {
        case .internalRAM: SWAN_MEMORY_INTERNAL_RAM
        }
    }
}

public struct SwanEngineError: LocalizedError, Equatable, Sendable {
    public let code: Int32
    public let detail: String

    public var errorDescription: String? { detail }

    var displaySourceProbeFailure: EngineDisplaySourceProbeFailure? {
        code == Int32(SWAN_RESULT_SOURCE_RANGE_OVERFLOW.rawValue)
            ? .selectedRangeUnionOverflow
            : nil
    }
}

enum EngineDisplaySourceProbeFailure: Equatable, Sendable {
    case selectedRangeUnionOverflow
}

/// Selects how a WonderSwan cartridge's real-time clock observes host time.
/// Normal play uses the Mac's clock; deterministic mode is intended for
/// repeatable translation, capture, and regression-test sessions.
public enum EngineRTCMode: Equatable, Sendable {
    case wallClock
    case deterministic(seedUnixSeconds: UInt64)
}

/// The WonderSwan-family hardware configuration used for a live session.
///
/// Automatic preserves the normal behavior of selecting monochrome or Color
/// hardware from the cartridge footer. Pocket Challenge V2 must be selected
/// explicitly because its cartridges share the WonderSwan footer format while
/// requiring Benesse's input matrix and KARNAK mapper.
public enum EngineHardwareModel: String, CaseIterable, Codable, Hashable, Sendable {
    case automatic
    case wonderSwan
    case wonderSwanColor
    case swanCrystal
    case pocketChallengeV2

    fileprivate var cValue: swan_model_t {
        switch self {
        case .automatic: SWAN_MODEL_AUTOMATIC
        case .wonderSwan: SWAN_MODEL_WONDERSWAN
        case .wonderSwanColor: SWAN_MODEL_WONDERSWAN_COLOR
        case .swanCrystal: SWAN_MODEL_SWANCRYSTAL
        case .pocketChallengeV2: SWAN_MODEL_POCKET_CHALLENGE_V2
        }
    }

    fileprivate init?(cValue: swan_model_t) {
        switch cValue {
        case SWAN_MODEL_AUTOMATIC: self = .automatic
        case SWAN_MODEL_WONDERSWAN: self = .wonderSwan
        case SWAN_MODEL_WONDERSWAN_COLOR: self = .wonderSwanColor
        case SWAN_MODEL_SWANCRYSTAL: self = .swanCrystal
        case SWAN_MODEL_POCKET_CHALLENGE_V2: self = .pocketChallengeV2
        default: return nil
        }
    }
}

public final class EngineSession: @unchecked Sendable {
    package let handle: OpaquePointer
    public let rtcMode: EngineRTCMode
    public let hardwareModel: EngineHardwareModel

    public init(
        sampleRate: UInt32 = 48_000,
        rtcMode: EngineRTCMode = .wallClock,
        hardwareModel: EngineHardwareModel = .automatic
    ) throws {
        let cRTCMode: swan_rtc_mode_t
        let rtcSeed: UInt64
        switch rtcMode {
        case .wallClock:
            cRTCMode = SWAN_RTC_MODE_WALL_CLOCK
            rtcSeed = 0
        case let .deterministic(seedUnixSeconds):
            guard seedUnixSeconds > 0, seedUnixSeconds <= UInt64(Int64.max) else {
                throw SwanEngineError(
                    code: Int32(SWAN_RESULT_INVALID_ARGUMENT.rawValue),
                    detail: "Deterministic RTC seed must be a positive Unix timestamp representable by Int64."
                )
            }
            cRTCMode = SWAN_RTC_MODE_DETERMINISTIC
            rtcSeed = seedUnixSeconds
        }
        var config = swan_engine_config_t(
            struct_size: UInt32(MemoryLayout<swan_engine_config_t>.size),
            abi_version: UInt32(SWAN_ENGINE_ABI_VERSION),
            preferred_model: hardwareModel.cValue,
            output_sample_rate: sampleRate,
            rtc_mode: cRTCMode,
            reserved: 0,
            rtc_seed_unix_seconds: rtcSeed
        )
        guard let handle = swan_engine_create(&config) else {
            throw SwanEngineError(
                code: Int32(SWAN_RESULT_ABI_MISMATCH.rawValue),
                detail: String(cString: swan_result_message(SWAN_RESULT_ABI_MISMATCH))
            )
        }
        self.handle = handle
        self.rtcMode = rtcMode
        self.hardwareModel = hardwareModel
    }

    deinit {
        swan_engine_destroy(handle)
    }

    public var backendName: String {
        String(cString: swan_engine_backend_name(handle))
    }

    public var buildID: String {
        String(cString: swan_engine_build_id(handle))
    }

    public var capabilities: EngineCapabilities {
        EngineCapabilities(rawValue: swan_engine_capabilities(handle))
    }

    /// The concrete hardware selected by the live backend, or nil before a
    /// cartridge has loaded. Automatic resolves to monochrome or Color here.
    public var activeHardwareModel: EngineHardwareModel? {
        var model = SWAN_MODEL_AUTOMATIC
        guard swan_engine_active_model(handle, &model) == SWAN_RESULT_OK else {
            return nil
        }
        return EngineHardwareModel(cValue: model)
    }

    public static func inspect(rom data: Data) throws -> ROMMetadata {
        var info = swan_rom_info_t()
        let result = data.withUnsafeBytes { bytes in
            swan_inspect_rom(
                bytes.bindMemory(to: UInt8.self).baseAddress,
                bytes.count,
                &info
            )
        }
        try check(result)
        return metadata(from: info)
    }

    @discardableResult
    public func load(rom data: Data) throws -> ROMMetadata {
        var info = swan_rom_info_t()
        let result = data.withUnsafeBytes { bytes in
            swan_engine_load_rom(
                handle,
                bytes.bindMemory(to: UInt8.self).baseAddress,
                bytes.count,
                &info
            )
        }
        try check(result)
        return Self.metadata(from: info)
    }

    public func runFrame() throws {
        try check(swan_engine_run_frame(handle))
    }

    public func unload() throws {
        try check(swan_engine_unload(handle))
    }

    public func reset() throws {
        try check(swan_engine_reset(handle))
    }

    public func setInput(_ input: EngineInput) throws {
        try check(swan_engine_set_input(handle, input.rawValue))
    }

    public func videoFrame() throws -> EngineVideoFrame {
        var frame = swan_video_frame_t()
        try check(swan_engine_video_frame(handle, &frame))
        guard let pixels = frame.pixels, frame.byte_count > 0 else {
            throw SwanEngineError(
                code: Int32(SWAN_RESULT_INTERNAL_ERROR.rawValue),
                detail: "The engine returned an empty video frame."
            )
        }
        return EngineVideoFrame(
            pixels: Data(bytes: pixels, count: frame.byte_count),
            width: Int(frame.width),
            height: Int(frame.height),
            strideBytes: Int(frame.stride_bytes),
            isVertical: frame.orientation == SWAN_ORIENTATION_VERTICAL,
            number: frame.frame_number
        )
    }

    public func audioBatch() throws -> EngineAudioBatch {
        var audio = swan_audio_batch_t()
        try check(swan_engine_audio_batch(handle, &audio))
        let sampleCount = Int(audio.frame_count) * Int(audio.channels)
        let samples: [Float]
        if let source = audio.interleaved_samples, sampleCount > 0 {
            samples = Array(UnsafeBufferPointer(start: source, count: sampleCount))
        } else {
            samples = []
        }
        return EngineAudioBatch(
            interleavedSamples: samples,
            channels: Int(audio.channels),
            sampleRate: Int(audio.sample_rate)
        )
    }

    public func displayOwnerProbe(
        rectangle: EngineDisplayRectangle
    ) throws -> [EngineDisplayOwnerSample] {
        guard capabilities.contains(.displayProvenance) else {
            throw SwanEngineError(
                code: Int32(SWAN_RESULT_UNSUPPORTED.rawValue),
                detail: "The active engine does not support display provenance."
            )
        }
        var cRectangle = swan_display_rectangle_t(
            struct_size: UInt32(MemoryLayout<swan_display_rectangle_t>.size),
            x: rectangle.x,
            y: rectangle.y,
            width: rectangle.width,
            height: rectangle.height
        )
        let expected = Int(rectangle.width) * Int(rectangle.height)
        var raw = [swan_display_owner_sample_t](
            repeating: swan_display_owner_sample_t(),
            count: expected
        )
        var count = 0
        let result = raw.withUnsafeMutableBufferPointer { buffer in
            swan_engine_display_owner_probe(
                handle,
                &cRectangle,
                buffer.baseAddress,
                buffer.count,
                &count
            )
        }
        try check(result)
        guard count == expected else {
            throw SwanEngineError(
                code: Int32(SWAN_RESULT_INTERNAL_ERROR.rawValue),
                detail: "The engine returned incomplete display provenance."
            )
        }
        return try raw.prefix(count).map(EngineDisplayOwnerSample.init(cValue:))
    }

    public func displaySourceProbe(
        rectangle: EngineDisplayRectangle,
        components: [EngineDisplaySourceComponent] = EngineDisplaySourceComponent.allCases
    ) throws -> [EngineDisplaySourceTrace] {
        guard capabilities.contains(.displaySourceProvenance) else {
            throw SwanEngineError(
                code: Int32(SWAN_RESULT_UNSUPPORTED.rawValue),
                detail: "The active engine does not support upstream display-source provenance."
            )
        }
        guard capabilities.contains(.displaySourceComponentSelection) else {
            throw SwanEngineError(
                code: Int32(SWAN_RESULT_UNSUPPORTED.rawValue),
                detail: "The active engine does not support component-selective source probes."
            )
        }
        guard !components.isEmpty, Set(components).count == components.count else {
            throw SwanEngineError(
                code: Int32(SWAN_RESULT_INVALID_ARGUMENT.rawValue),
                detail: "Source probe components must be nonempty and unique."
            )
        }
        if components.contains(.spriteAttribute),
           !capabilities.contains(.displaySpriteAttributeProvenance) {
            throw SwanEngineError(
                code: Int32(SWAN_RESULT_UNSUPPORTED.rawValue),
                detail: "The active engine does not support sprite-attribute provenance."
            )
        }
        var cRectangle = swan_display_rectangle_t(
            struct_size: UInt32(MemoryLayout<swan_display_rectangle_t>.size),
            x: rectangle.x,
            y: rectangle.y,
            width: rectangle.width,
            height: rectangle.height
        )
        var options = swan_display_source_probe_options_t(
            struct_size: UInt32(MemoryLayout<swan_display_source_probe_options_t>.size),
            selected_component_mask: components.reduce(0) { $0 | $1.cMask }
        )
        var count = 0
        try check(swan_engine_display_source_probe(
            handle,
            &cRectangle,
            &options,
            nil,
            0,
            &count
        ))
        guard count <= 262_144 else {
            throw SwanEngineError(
                code: Int32(SWAN_RESULT_INTERNAL_ERROR.rawValue),
                detail: "The engine exceeded the bounded upstream source-trace limit."
            )
        }
        var raw = [swan_display_source_trace_t](
            repeating: swan_display_source_trace_t(),
            count: count
        )
        var written = 0
        let result = raw.withUnsafeMutableBufferPointer { buffer in
            swan_engine_display_source_probe(
                handle,
                &cRectangle,
                &options,
                buffer.baseAddress,
                buffer.count,
                &written
            )
        }
        try check(result)
        guard written == count else {
            throw SwanEngineError(
                code: Int32(SWAN_RESULT_INTERNAL_ERROR.rawValue),
                detail: "The engine returned incomplete upstream source provenance."
            )
        }
        return try raw.prefix(written).map(EngineDisplaySourceTrace.init(cValue:))
    }

    public func stagePersistence(_ persistence: EnginePersistence) throws {
        for (kind, data) in persistence.regions where !data.isEmpty {
            let result = data.withUnsafeBytes { bytes in
                swan_engine_stage_persistence(
                    handle,
                    kind.cValue,
                    bytes.bindMemory(to: UInt8.self).baseAddress,
                    bytes.count
                )
            }
            try check(result)
        }
    }

    public func capturePersistence() throws -> EnginePersistence {
        var regions: [EnginePersistenceKind: Data] = [:]
        for kind in EnginePersistenceKind.allCases {
            var size = 0
            let sizeResult = swan_engine_persistence_size(handle, kind.cValue, &size)
            if sizeResult == SWAN_RESULT_UNSUPPORTED { continue }
            try check(sizeResult)
            guard size > 0 else { continue }

            var data = Data(count: size)
            var written = 0
            let readResult = data.withUnsafeMutableBytes { bytes in
                swan_engine_read_persistence(
                    handle,
                    kind.cValue,
                    bytes.bindMemory(to: UInt8.self).baseAddress,
                    bytes.count,
                    &written
                )
            }
            if readResult == SWAN_RESULT_UNSUPPORTED { continue }
            try check(readResult)
            if written < data.count { data.removeSubrange(written...) }
            regions[kind] = data
        }
        return EnginePersistence(regions: regions)
    }

    public func captureState() throws -> Data {
        var size = 0
        try check(swan_engine_capture_state(handle, nil, 0, &size))
        guard size > 0 else {
            throw SwanEngineError(
                code: Int32(SWAN_RESULT_INTERNAL_ERROR.rawValue),
                detail: "The engine returned an empty save state."
            )
        }
        var state = Data(count: size)
        var written = 0
        let result = state.withUnsafeMutableBytes { bytes in
            swan_engine_capture_state(
                handle,
                bytes.bindMemory(to: UInt8.self).baseAddress,
                bytes.count,
                &written
            )
        }
        try check(result)
        if written < state.count { state.removeSubrange(written...) }
        return state
    }

    public func captureMemory(_ region: EngineMemoryRegion) throws -> Data {
        var size = 0
        try check(swan_engine_memory_size(handle, region.cValue, &size))
        guard size > 0 else {
            throw SwanEngineError(
                code: Int32(SWAN_RESULT_INTERNAL_ERROR.rawValue),
                detail: "The engine returned an empty memory region."
            )
        }
        var data = Data(count: size)
        var written = 0
        let result = data.withUnsafeMutableBytes { bytes in
            swan_engine_read_memory(
                handle,
                region.cValue,
                bytes.bindMemory(to: UInt8.self).baseAddress,
                bytes.count,
                &written
            )
        }
        try check(result)
        if written < data.count { data.removeSubrange(written...) }
        return data
    }

    public func restoreState(_ state: Data) throws {
        let result = state.withUnsafeBytes { bytes in
            swan_engine_restore_state(
                handle,
                bytes.bindMemory(to: UInt8.self).baseAddress,
                bytes.count
            )
        }
        try check(result)
    }

    private static func metadata(from info: swan_rom_info_t) -> ROMMetadata {
        ROMMetadata(
            fileSize: info.file_size,
            mappedSize: info.mapped_size,
            storedChecksum: info.stored_checksum,
            computedChecksum: info.computed_checksum,
            isColor: info.color != 0,
            saveType: info.save_type,
            mapper: info.mapper,
            romSizeCode: info.rom_size_code,
            checksumIsValid: info.checksum_valid != 0,
            footerIsValid: info.footer_valid != 0,
            usesCompactLayout: info.compact_layout != 0,
            hasRTC: info.has_rtc != 0
        )
    }

    private static func check(_ result: swan_result_t) throws {
        guard result == SWAN_RESULT_OK else {
            throw SwanEngineError(
                code: Int32(result.rawValue),
                detail: String(cString: swan_result_message(result))
            )
        }
    }

    private func check(_ result: swan_result_t) throws {
        guard result == SWAN_RESULT_OK else {
            let backendDetail = String(cString: swan_engine_last_error(handle))
            throw SwanEngineError(
                code: Int32(result.rawValue),
                detail: backendDetail.isEmpty
                    ? String(cString: swan_result_message(result))
                    : backendDetail
            )
        }
    }
}

public actor EmulationRunner {
    package let engine: EngineSession

    public init(
        sampleRate: UInt32 = 48_000,
        rtcMode: EngineRTCMode = .wallClock,
        hardwareModel: EngineHardwareModel = .automatic
    ) throws {
        engine = try EngineSession(
            sampleRate: sampleRate,
            rtcMode: rtcMode,
            hardwareModel: hardwareModel
        )
    }

    public var activeHardwareModel: EngineHardwareModel? {
        engine.activeHardwareModel
    }

    public func load(rom data: Data) throws -> ROMMetadata {
        try engine.load(rom: data)
    }

    public func stagePersistence(_ persistence: EnginePersistence) throws {
        try engine.stagePersistence(persistence)
    }

    public func nextFrame(input: EngineInput = []) throws -> (
        video: EngineVideoFrame,
        audio: EngineAudioBatch
    ) {
        try engine.setInput(input)
        try engine.runFrame()
        return (try engine.videoFrame(), try engine.audioBatch())
    }

    public func reset() throws {
        try engine.reset()
    }

    public func capturePersistence() throws -> EnginePersistence {
        try engine.capturePersistence()
    }

    public func captureState() throws -> Data {
        try engine.captureState()
    }

    public func captureMemory(_ region: EngineMemoryRegion) throws -> Data {
        try engine.captureMemory(region)
    }

    public func restoreState(_ state: Data) throws {
        try engine.restoreState(state)
    }

    public func stop() throws {
        try engine.unload()
    }
}
