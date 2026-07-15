import CSwanEngine
import Darwin
import Foundation
import SwanSongKit

private struct CheckFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) throws {
    guard condition() else { throw CheckFailure(message: message) }
}

private func makeROM(
    color: Bool = false,
    vertical: Bool = false,
    saveType: UInt8 = 0x01,
    mapper: UInt8 = 0
) -> Data {
    var bytes = [UInt8](repeating: 0, count: 128 * 1024)
    let footer = bytes.count - 16
    bytes[footer + 0] = 0xea
    bytes[footer + 7] = color ? 1 : 0
    bytes[footer + 10] = 0x00
    bytes[footer + 11] = saveType
    bytes[footer + 12] = vertical ? 0x05 : 0x04
    bytes[footer + 13] = mapper
    let checksum = bytes[..<(bytes.count - 2)].reduce(UInt16(0)) {
        $0 &+ UInt16($1)
    }
    bytes[bytes.count - 2] = UInt8(truncatingIfNeeded: checksum)
    bytes[bytes.count - 1] = UInt8(truncatingIfNeeded: checksum >> 8)
    return Data(bytes)
}

private func makeRouteFrame(
    number: UInt64,
    width: Int = 2,
    height: Int = 2,
    paddingByte: UInt8 = 0,
    changedVisibleByte: UInt8? = nil
) -> EngineVideoFrame {
    let visibleBytes = width * 4
    let stride = visibleBytes + 4
    var pixels = Data()
    for row in 0..<height {
        var visible = Data((0..<visibleBytes).map {
            UInt8(truncatingIfNeeded: Int(number) + row + $0)
        })
        if row == 0, let changedVisibleByte {
            visible[0] = changedVisibleByte
        }
        pixels.append(visible)
        pixels.append(Data(repeating: paddingByte, count: stride - visibleBytes))
    }
    return EngineVideoFrame(
        pixels: pixels,
        width: width,
        height: height,
        strideBytes: stride,
        isVertical: false,
        number: number
    )
}

@main
private struct SwanSongChecks {
    static func main() async throws {
        try checkCapabilities()
        try checkPocketChallengeV2BoundaryContract()
        try checkROMInspection()
        try checkCompactRejection()
        try checkBackendTruth()
        try checkFreshBootDeterminism()
        try checkDeterministicRTC()
        try await checkRunnerFreshBootDeterminism()
        try checkBootROMStaging()
        try checkLibraryRoundTrip()
        try checkGameConfidence()
        try checkDataRootContainmentPolicy()
        try checkFirmwareStore()
        try checkFirmwareImporter()
        try checkBatchGameImport()
        try checkGameArtworkStore()
        try checkLibraryQuery()
        try checkSaveRoundTrip()
        try checkTransactionalSaveFailure()
        try await checkConcurrentSaveSerialization()
        try checkCartridgeSaveReplacement()
        try checkFramePacingPolicy()
        try checkPlayerControlPolicy()
        try checkFrameAdvanceGate()
        try checkRewindBuffer()
        try checkPlayerLaunchStages()
        try checkPlayerFailureState()
        try await checkPlayerSessionFinalization()
        try await checkPlayerSessionRetirementDeadline()
        try checkFrameActivityMonitor()
        try checkDisplayProfiles()
        try checkPlayerWindowLayout()
        try checkControllerProfiles()
        try checkPocketSaveCodec()
        try checkFrameDifferential()
        try checkTranslationVisualDivergence()
        try checkEngineFramePNGCodec()
        try checkTranslationLabFoundations()
        try checkTranslationRAMTextScanner()
        try checkTranslationRAMPointerScanner()
        try checkStateStoreRoundTrip()
        print("PASS SwanSong macOS engine boundary and library checks")
    }

    private static func checkEngineFramePNGCodec() throws {
        let supportedShapes = [
            (224, 157),
            (157, 224),
            (237, 144),
            (144, 237),
            (224, 144),
            (144, 224),
        ]
        for (shapeIndex, shape) in supportedShapes.enumerated() {
            let (width, height) = shape
            let visibleStride = width * 4
            let sourceStride = visibleStride + 12
            var sourcePixels = Data(count: sourceStride * height)
            sourcePixels.withUnsafeMutableBytes { raw in
                let bytes = raw.bindMemory(to: UInt8.self)
                for y in 0..<height {
                    for x in 0..<width {
                        let offset = y * sourceStride + x * 4
                        bytes[offset] = UInt8(truncatingIfNeeded: x * 7 + y * 17 + shapeIndex)
                        bytes[offset + 1] = UInt8(truncatingIfNeeded: x * 13 + y * 3 + 29)
                        bytes[offset + 2] = UInt8(truncatingIfNeeded: x * 5 + y * 11 + 71)
                        bytes[offset + 3] = 255
                    }
                    for offset in (y * sourceStride + visibleStride)..<((y + 1) * sourceStride) {
                        bytes[offset] = 0xa5
                    }
                }
            }
            let frameNumber = UInt64(10_000 + shapeIndex)
            let source = EngineVideoFrame(
                pixels: sourcePixels,
                width: width,
                height: height,
                strideBytes: sourceStride,
                isVertical: height > width,
                number: frameNumber
            )
            let png = try EngineFramePNGCodec.encode(source)
            let decoded = try EngineFramePNGCodec.decode(png, frameNumber: frameNumber)

            var packedSource = Data(count: visibleStride * height)
            packedSource.withUnsafeMutableBytes { destinationRaw in
                sourcePixels.withUnsafeBytes { sourceRaw in
                    guard
                        let destination = destinationRaw.baseAddress,
                        let source = sourceRaw.baseAddress
                    else { return }
                    for y in 0..<height {
                        memcpy(
                            destination.advanced(by: y * visibleStride),
                            source.advanced(by: y * sourceStride),
                            visibleStride
                        )
                    }
                }
            }
            try expect(decoded.width == width, "PNG codec changed frame width for \(width)×\(height)")
            try expect(decoded.height == height, "PNG codec changed frame height for \(width)×\(height)")
            try expect(decoded.strideBytes == visibleStride, "PNG codec returned a padded frame")
            try expect(decoded.isVertical == (height > width), "PNG codec changed frame orientation")
            try expect(decoded.number == frameNumber, "PNG codec changed the supplied frame number")
            try expect(decoded.pixels == packedSource, "PNG codec changed BGRA pixels for \(width)×\(height)")
        }

        do {
            _ = try EngineFramePNGCodec.decode(Data([0x00, 0x01, 0x02]), frameNumber: 0)
            throw CheckFailure(message: "PNG codec accepted malformed data")
        } catch EngineFramePNGCodecError.invalidPNG {
            // Expected.
        }

        let onePixelPNG = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )!
        do {
            _ = try EngineFramePNGCodec.decode(onePixelPNG, frameNumber: 0)
            throw CheckFailure(message: "PNG codec accepted a 1×1 preview")
        } catch EngineFramePNGCodecError.unsupportedDimensions(width: 1, height: 1) {
            // Expected.
        }
    }

    private static func checkCapabilities() throws {
        let engine = try EngineSession()
        try expect(!engine.buildID.isEmpty, "engine build identity is missing")
        try expect(engine.capabilities.contains(.romInspection), "ROM inspection capability is missing")
        if engine.backendName == "ares" {
            try expect(engine.capabilities.contains(.execution), "ares execution capability is missing")
            try expect(engine.capabilities.contains(.audio), "ares audio capability is missing")
            try expect(engine.capabilities.contains(.persistence), "ares persistence capability is missing")
            try expect(engine.capabilities.contains(.saveStates), "ares save-state capability is missing")
            try expect(engine.capabilities.contains(.debugger), "ares RAM capture capability is missing")
            try expect(
                engine.capabilities.contains(.pocketChallengeV2),
                "ares Pocket Challenge V2 capability is missing"
            )
        } else {
            try expect(!engine.capabilities.contains(.execution), "stub must not claim execution")
            try expect(engine.backendName == "ares adapter pending", "backend name mismatch")
        }
    }

    private static func checkPocketChallengeV2BoundaryContract() throws {
        let models = EngineHardwareModel.allCases
        try expect(
            Set(models.map(\.rawValue)) == Set([
                "automatic",
                "wonderSwan",
                "wonderSwanColor",
                "swanCrystal",
                "pocketChallengeV2",
            ]),
            "hardware-model identities are incomplete or unstable"
        )
        let encoded = try JSONEncoder().encode(models)
        let decoded = try JSONDecoder().decode(
            [EngineHardwareModel].self,
            from: encoded
        )
        try expect(
            decoded == models,
            "hardware-model identities did not survive Codable round-trip"
        )

        let pcv2 = try EngineSession(hardwareModel: .pocketChallengeV2)
        try expect(
            pcv2.hardwareModel == .pocketChallengeV2,
            "EngineSession discarded the explicitly configured PCV2 model"
        )
        try expect(
            pcv2.activeHardwareModel == nil,
            "EngineSession reported an active PCV2 model before loading a cartridge"
        )

        let semanticInputs: [EngineInput] = [
            .pocketChallengeUp,
            .pocketChallengeRight,
            .pocketChallengeDown,
            .pocketChallengeLeft,
            .pocketChallengePass,
            .pocketChallengeCircle,
            .pocketChallengeClear,
            .pocketChallengeView,
            .pocketChallengeEscape,
        ]
        let semanticBits = semanticInputs.map(\.rawValue)
        try expect(
            semanticBits.allSatisfy { $0.nonzeroBitCount == 1 }
                && Set(semanticBits).count == semanticBits.count,
            "PCV2 semantic inputs are not independent one-bit identities"
        )
        let legacyBits: Set<UInt32> = [
            EngineInput.y1.rawValue,
            EngineInput.y2.rawValue,
            EngineInput.y3.rawValue,
            EngineInput.y4.rawValue,
            EngineInput.x1.rawValue,
            EngineInput.x2.rawValue,
            EngineInput.x3.rawValue,
            EngineInput.x4.rawValue,
            EngineInput.b.rawValue,
            EngineInput.a.rawValue,
            EngineInput.start.rawValue,
            EngineInput.volume.rawValue,
            EngineInput.power.rawValue,
        ]
        try expect(
            Set(semanticBits).isDisjoint(with: legacyBits),
            "PCV2 semantic inputs collide with legacy WonderSwan controls"
        )
    }

    private static func checkPlayerControlPolicy() throws {
        func policy(
            interactive: Bool = true,
            hasFrame: Bool = true,
            stateOperationIsBusy: Bool = false,
            comparisonIsActive: Bool = false,
            comparisonIsTransitioning: Bool = false,
            recordingIsPreparing: Bool = false,
            recordingIsActive: Bool = false
        ) -> PlayerControlPolicy {
            PlayerControlPolicy(
                playerIsInteractive: interactive,
                hasCurrentFrame: hasFrame,
                stateOperationIsBusy: stateOperationIsBusy,
                translationComparisonIsActive: comparisonIsActive,
                translationComparisonIsTransitioning: comparisonIsTransitioning,
                translationRouteRecordingIsPreparing: recordingIsPreparing,
                translationRouteIsRecording: recordingIsActive
            )
        }

        let normalGameplay = policy()
        try expect(normalGameplay.canTogglePause, "normal gameplay pause should be available")
        try expect(normalGameplay.canResetGame, "normal gameplay reset should be available")
        try expect(normalGameplay.canToggleFastForward, "normal gameplay fast-forward should be available")

        let unavailableBaselines = [
            policy(interactive: false),
            policy(hasFrame: false),
            policy(stateOperationIsBusy: true),
        ]
        for unavailable in unavailableBaselines {
            try expect(!unavailable.canTogglePause, "pause bypassed a base player requirement")
            try expect(!unavailable.canResetGame, "reset bypassed a base player requirement")
            try expect(!unavailable.canToggleFastForward, "fast-forward bypassed a base player requirement")
        }

        let deterministicTranslationStates = [
            policy(comparisonIsActive: true),
            policy(comparisonIsTransitioning: true),
            policy(recordingIsPreparing: true),
            policy(recordingIsActive: true),
        ]
        for locked in deterministicTranslationStates {
            try expect(
                locked.deterministicTranslationControlLockIsActive,
                "deterministic translation state did not activate its control lock"
            )
            try expect(!locked.canTogglePause, "pause mutated a deterministic translation run")
            try expect(!locked.canResetGame, "reset mutated a deterministic translation run")
            try expect(!locked.canToggleFastForward, "fast-forward mutated a deterministic translation run")
        }
    }

    private static func checkFrameAdvanceGate() throws {
        var gate = FrameAdvanceGate()
        try expect(!gate.consume(whilePaused: true), "an empty frame-step queue advanced")
        try expect(gate.request(), "the first frame-step request was rejected")
        try expect(gate.request(), "the second frame-step request was coalesced")
        try expect(gate.pendingCount == 2, "frame-step requests were not queued exactly")
        try expect(!gate.consume(whilePaused: false), "frame stepping advanced while playback was running")
        try expect(gate.pendingCount == 2, "a running frame consumed a paused step request")
        try expect(gate.consume(whilePaused: true), "the first paused frame-step was not consumed")
        try expect(gate.consume(whilePaused: true), "the second paused frame-step was not consumed")
        try expect(!gate.hasPendingRequest, "the frame-step queue did not drain")
        _ = gate.request()
        gate.reset()
        try expect(!gate.hasPendingRequest, "reset preserved a stale frame-step request")
    }

    private static func checkRewindBuffer() throws {
        func frame(number: UInt64, marker: UInt8 = 0x44) -> EngineVideoFrame {
            EngineVideoFrame(
                pixels: Data(repeating: marker, count: 8),
                width: 2,
                height: 1,
                strideBytes: 8,
                isVertical: false,
                number: number
            )
        }

        func checkpoint(
            frameNumber: UInt64,
            stateByteCount: Int = 8,
            marker: UInt8 = 0x44
        ) throws -> RewindCheckpoint {
            try RewindCheckpoint(
                state: Data(repeating: marker, count: stateByteCount),
                previewFrame: frame(number: frameNumber, marker: marker)
            )
        }

        let standard = RewindBufferConfiguration.standard
        try expect(standard.retentionSeconds == 30, "rewind default is not a 30-second window")
        try expect(
            standard.frameRateNumerator == 4_000
                && standard.frameRateDenominator == 53,
            "rewind default lost the WonderSwan nominal frame rate"
        )
        try expect(
            standard.maximumFrameSpan == 2_264,
            "rewind default frame-span conversion changed"
        )
        try expect(
            standard.maximumByteCount == 48 * 1_024 * 1_024,
            "rewind default hard byte cap changed"
        )
        try expect(
            abs(standard.nominalFramesPerSecond - (4_000.0 / 53.0)) < 0.000_001,
            "rewind nominal frame rate is imprecise"
        )

        do {
            _ = try RewindBufferConfiguration(retentionSeconds: 0)
            throw CheckFailure(message: "rewind accepted zero retention")
        } catch RewindBufferConfigurationError.invalidRetentionSeconds {
            // Expected.
        }
        do {
            _ = try RewindBufferConfiguration(frameRateNumerator: 0)
            throw CheckFailure(message: "rewind accepted a zero frame-rate numerator")
        } catch RewindBufferConfigurationError.invalidFrameRate {
            // Expected.
        }
        do {
            _ = try RewindBufferConfiguration(frameRateDenominator: 0)
            throw CheckFailure(message: "rewind accepted a zero frame-rate denominator")
        } catch RewindBufferConfigurationError.invalidFrameRate {
            // Expected.
        }
        do {
            _ = try RewindBufferConfiguration(maximumByteCount: 0)
            throw CheckFailure(message: "rewind accepted a zero byte cap")
        } catch RewindBufferConfigurationError.invalidMaximumByteCount {
            // Expected.
        }
        do {
            _ = try RewindBufferConfiguration(
                retentionSeconds: UInt64.max,
                frameRateNumerator: 2,
                frameRateDenominator: 1
            )
            throw CheckFailure(message: "rewind retention arithmetic overflowed")
        } catch RewindBufferConfigurationError.retentionFrameSpanOverflow {
            // Expected.
        }
        do {
            _ = try RewindBufferConfiguration(
                retentionSeconds: 1,
                frameRateNumerator: 1,
                frameRateDenominator: 2
            )
            throw CheckFailure(message: "rewind accepted a sub-frame retention window")
        } catch RewindBufferConfigurationError.retentionWindowTooSmall {
            // Expected.
        }

        do {
            _ = try RewindCheckpoint(state: Data(), previewFrame: frame(number: 1))
            throw CheckFailure(message: "rewind accepted an empty engine state")
        } catch RewindCheckpointError.emptyState {
            // Expected.
        }
        do {
            _ = try RewindCheckpoint(
                state: Data([0x01]),
                previewFrame: EngineVideoFrame(
                    pixels: Data(repeating: 0, count: 7),
                    width: 2,
                    height: 1,
                    strideBytes: 8,
                    isVertical: false,
                    number: 1
                )
            )
            throw CheckFailure(message: "rewind accepted a truncated preview frame")
        } catch RewindCheckpointError.invalidPreviewFrame {
            // Expected.
        }

        let mutationConfiguration = try RewindBufferConfiguration(
            retentionSeconds: 3,
            frameRateNumerator: 10,
            frameRateDenominator: 1,
            maximumByteCount: 64
        )
        var mutationBuffer = RewindBuffer(configuration: mutationConfiguration)
        try expect(
            mutationBuffer.isEmpty
                && mutationBuffer.count == 0
                && mutationBuffer.totalPayloadByteCount == 0
                && mutationBuffer.retainedFrameRange == nil,
            "a fresh rewind buffer was not empty"
        )
        try expect(
            mutationBuffer.checkpoint(nearestToFrame: 1) == nil
                && mutationBuffer.checkpoint(atOrBeforeFrame: 1) == nil
                && mutationBuffer.checkpoint(secondsBack: 1) == nil,
            "an empty rewind buffer returned a checkpoint"
        )

        for frameNumber in [UInt64(100), 110, 120, 130] {
            let result = try mutationBuffer.append(
                checkpoint(frameNumber: frameNumber)
            )
            try expect(
                !result.replacedExistingCheckpoint
                    && result.evictedCheckpointCount == 0
                    && result.checkpointWasRetained,
                "an in-window rewind append reported the wrong mutation"
            )
        }
        try expect(
            mutationBuffer.checkpoints.map(\.frameNumber) == [100, 110, 120, 130]
                && mutationBuffer.totalPayloadByteCount == 64,
            "rewind appends lost chronological order or exact byte accounting"
        )

        let retentionEviction = try mutationBuffer.append(checkpoint(frameNumber: 140))
        try expect(
            retentionEviction.evictedCheckpointCount == 1
                && retentionEviction.checkpointWasRetained
                && mutationBuffer.checkpoints.map(\.frameNumber) == [110, 120, 130, 140]
                && mutationBuffer.retainedFrameRange == 110...140,
            "rewind did not evict the oldest checkpoint at its time boundary"
        )

        let replacement = try mutationBuffer.append(
            checkpoint(frameNumber: 120, marker: 0xaa)
        )
        try expect(
            replacement.replacedExistingCheckpoint
                && replacement.evictedCheckpointCount == 0
                && replacement.checkpointWasRetained
                && mutationBuffer.count == 4
                && mutationBuffer.checkpoint(nearestToFrame: 120)?.state.first == 0xaa,
            "same-frame rewind replacement was not deterministic"
        )

        let unchangedFrames = mutationBuffer.checkpoints.map(\.frameNumber)
        let unchangedByteCount = mutationBuffer.totalPayloadByteCount
        do {
            _ = try mutationBuffer.append(checkpoint(frameNumber: 125))
            throw CheckFailure(message: "rewind inserted an implicit historical branch")
        } catch RewindBufferError.outOfOrderFrame(attempted: 125, latest: 140) {
            // Expected.
        }
        try expect(
            mutationBuffer.checkpoints.map(\.frameNumber) == unchangedFrames
                && mutationBuffer.totalPayloadByteCount == unchangedByteCount,
            "a rejected historical append mutated rewind history"
        )

        let evictedReplacement = try mutationBuffer.append(
            checkpoint(frameNumber: 110, stateByteCount: 56, marker: 0xbb)
        )
        try expect(
            evictedReplacement.replacedExistingCheckpoint
                && evictedReplacement.evictedCheckpointCount == 1
                && !evictedReplacement.checkpointWasRetained
                && mutationBuffer.checkpoints.map(\.frameNumber) == [120, 130, 140]
                && mutationBuffer.totalPayloadByteCount == 48,
            "oldest-first byte eviction did not handle a large historical replacement"
        )

        let beforeOversize = mutationBuffer.checkpoints
        do {
            _ = try mutationBuffer.append(
                checkpoint(frameNumber: 150, stateByteCount: 57)
            )
            throw CheckFailure(message: "rewind accepted a checkpoint above its byte cap")
        } catch RewindBufferError.checkpointExceedsByteLimit(actual: 65, maximum: 64) {
            // Expected.
        }
        try expect(
            mutationBuffer.checkpoints == beforeOversize
                && mutationBuffer.totalPayloadByteCount == 48,
            "an oversized checkpoint mutated rewind history"
        )

        let retentionConfiguration = try RewindBufferConfiguration(
            retentionSeconds: 3,
            frameRateNumerator: 10,
            frameRateDenominator: 1,
            maximumByteCount: 1_024
        )
        var retentionBuffer = RewindBuffer(configuration: retentionConfiguration)
        _ = try retentionBuffer.append(checkpoint(frameNumber: 100))
        _ = try retentionBuffer.append(checkpoint(frameNumber: 130))
        try expect(
            retentionBuffer.checkpoints.map(\.frameNumber) == [100, 130],
            "rewind evicted a checkpoint exactly on the retention boundary"
        )
        let beyondBoundary = try retentionBuffer.append(checkpoint(frameNumber: 131))
        try expect(
            beyondBoundary.evictedCheckpointCount == 1
                && retentionBuffer.checkpoints.map(\.frameNumber) == [130, 131],
            "rewind retained history beyond its configured time window"
        )

        let byteConfiguration = try RewindBufferConfiguration(
            retentionSeconds: 10,
            frameRateNumerator: 10,
            frameRateDenominator: 1,
            maximumByteCount: 32
        )
        var byteBuffer = RewindBuffer(configuration: byteConfiguration)
        _ = try byteBuffer.append(checkpoint(frameNumber: 10))
        _ = try byteBuffer.append(checkpoint(frameNumber: 20))
        let byteEviction = try byteBuffer.append(checkpoint(frameNumber: 30))
        try expect(
            byteEviction.evictedCheckpointCount == 1
                && byteBuffer.checkpoints.map(\.frameNumber) == [20, 30]
                && byteBuffer.totalPayloadByteCount == 32,
            "rewind byte-cap eviction was not oldest-first and exact"
        )

        let lookupConfiguration = try RewindBufferConfiguration(
            retentionSeconds: 10,
            frameRateNumerator: 10,
            frameRateDenominator: 1,
            maximumByteCount: 256
        )
        var lookupBuffer = RewindBuffer(configuration: lookupConfiguration)
        for frameNumber in [UInt64(100), 110, 130] {
            _ = try lookupBuffer.append(checkpoint(frameNumber: frameNumber))
        }
        try expect(
            lookupBuffer.checkpoint(nearestToFrame: 99)?.frameNumber == 100
                && lookupBuffer.checkpoint(nearestToFrame: 105)?.frameNumber == 100
                && lookupBuffer.checkpoint(nearestToFrame: 106)?.frameNumber == 110
                && lookupBuffer.checkpoint(nearestToFrame: 125)?.frameNumber == 130
                && lookupBuffer.checkpoint(nearestToFrame: 999)?.frameNumber == 130,
            "rewind nearest-frame selection or its older tie-break changed"
        )
        try expect(
            lookupBuffer.checkpoint(atOrBeforeFrame: 99) == nil
                && lookupBuffer.checkpoint(atOrBeforeFrame: 100)?.frameNumber == 100
                && lookupBuffer.checkpoint(atOrBeforeFrame: 129)?.frameNumber == 110
                && lookupBuffer.checkpoint(atOrBeforeFrame: 999)?.frameNumber == 130,
            "rewind at-or-before selection crossed its requested frame"
        )
        try expect(
            lookupBuffer.checkpoint(secondsBack: 0)?.frameNumber == 130
                && lookupBuffer.checkpoint(secondsBack: 1.5)?.frameNumber == 110
                && lookupBuffer.checkpoint(secondsBack: 2)?.frameNumber == 110
                && lookupBuffer.checkpoint(secondsBack: 2, fromFrame: 150)?.frameNumber == 130
                && lookupBuffer.checkpoint(secondsBack: 100)?.frameNumber == 100,
            "rewind seconds-back selection did not use emulated time deterministically"
        )
        try expect(
            lookupBuffer.checkpoint(secondsBack: -1) == nil
                && lookupBuffer.checkpoint(secondsBack: .nan) == nil
                && lookupBuffer.checkpoint(secondsBack: .infinity) == nil,
            "rewind accepted an invalid seconds-back offset"
        )

        try expect(
            lookupBuffer.truncate(afterFrame: 999) == 0,
            "rewind truncated a branch beyond its latest checkpoint"
        )
        try expect(
            lookupBuffer.truncate(afterFrame: 110) == 1
                && lookupBuffer.checkpoints.map(\.frameNumber) == [100, 110]
                && lookupBuffer.totalPayloadByteCount == 32,
            "rewind branch truncation did not preserve its selected checkpoint"
        )
        _ = try lookupBuffer.append(checkpoint(frameNumber: 115, marker: 0xcc))
        try expect(
            lookupBuffer.checkpoints.map(\.frameNumber) == [100, 110, 115],
            "rewind did not accept a new future after explicit branch truncation"
        )
        try expect(
            lookupBuffer.truncate(afterFrame: 99) == 3
                && lookupBuffer.isEmpty
                && lookupBuffer.totalPayloadByteCount == 0,
            "rewind did not clear a branch truncated before its oldest checkpoint"
        )
        _ = try lookupBuffer.append(checkpoint(frameNumber: 200))
        lookupBuffer.reset()
        try expect(
            lookupBuffer.isEmpty
                && lookupBuffer.totalPayloadByteCount == 0
                && lookupBuffer.retainedFrameRange == nil,
            "rewind reset retained checkpoint state"
        )
    }

    private static func checkFrameActivityMonitor() throws {
        func frame(
            number: UInt64,
            flat: Bool,
            changedSamples: Int = 0,
            inverted: Bool = false
        ) -> EngineVideoFrame {
            let width = 224
            let height = 144
            let stride = width * 4
            var pixels = Data(repeating: 0xff, count: stride * height)
            if !flat {
                let columns = 16
                let rows = 12
                for row in 0..<rows {
                    let y = row * (height - 1) / (rows - 1)
                    for column in 0..<columns where (row + column).isMultiple(of: 2) != inverted {
                        let x = column * (width - 1) / (columns - 1)
                        let offset = y * stride + x * 4
                        pixels[offset] = 0
                        pixels[offset + 1] = 0
                        pixels[offset + 2] = 0
                    }
                }
                for sample in 0..<min(changedSamples, columns * rows) {
                    let row = sample / columns
                    let column = sample % columns
                    let y = row * (height - 1) / (rows - 1)
                    let x = column * (width - 1) / (columns - 1)
                    let offset = y * stride + x * 4
                    pixels[offset] = 0x7f
                    pixels[offset + 1] = 0x7f
                    pixels[offset + 2] = 0x7f
                }
            }
            return EngineVideoFrame(
                pixels: pixels,
                width: width,
                height: height,
                strideBytes: stride,
                isVertical: false,
                number: number
            )
        }

        var monitor = FrameActivityMonitor(
            attentionThreshold: 3,
            lowMotionAttentionThreshold: 3
        )
        try expect(!monitor.observe(frame(number: 1, flat: true)).needsAttention, "one flat frame triggered a warning")
        try expect(!monitor.observe(frame(number: 2, flat: true)).needsAttention, "two flat frames triggered a warning")
        let flatWarning = monitor.observe(frame(number: 3, flat: true))
        try expect(flatWarning.issue == .flatColor, "the flat-frame threshold was not classified")
        let active = monitor.observe(frame(number: 4, flat: false))
        try expect(!active.needsAttention, "visible video activity did not clear the warning")
        try expect(active.consecutiveUniformFrames == 0, "visible activity did not reset the flat-frame streak")

        try expect(
            !monitor.observe(frame(number: 5, flat: false)).needsAttention,
            "one static patterned frame triggered a warning"
        )
        try expect(
            !monitor.observe(frame(number: 6, flat: false, changedSamples: 2)).needsAttention,
            "minor raster movement warned before its slower threshold"
        )
        let lowMotionWarning = monitor.observe(
            frame(number: 7, flat: false, changedSamples: 1)
        )
        try expect(
            lowMotionWarning.issue == .lowMotion,
            "a mostly static non-flat raster was not classified as low motion"
        )
        let moving = monitor.observe(
            frame(number: 8, flat: false, inverted: true)
        )
        try expect(
            moving.hasMeaningfulMotion && !moving.needsAttention,
            "meaningful raster movement did not clear the low-motion warning"
        )
        monitor.reset()
        try expect(
            monitor.consecutiveUniformFrames == 0
                && monitor.consecutiveLowMotionFrames == 0,
            "video activity reset preserved stale frame counters"
        )
    }

    private static func checkPlayerLaunchStages() throws {
        let stages = PlayerLaunchStage.allCases
        try expect(
            stages == [
                .closingPreviousSession,
                .verifyingGame,
                .startingEngine,
                .loadingStartupFile,
                .restoringSave,
                .startingSystem,
                .waitingForFirstFrame,
            ],
            "player launch milestones changed order"
        )
        try expect(
            zip(stages, stages.dropFirst()).allSatisfy { left, right in
                left.progress > 0
                    && left.progress < right.progress
                    && right.progress < 1
            },
            "player launch progress is not strictly increasing and bounded"
        )
    }

    private static func checkPlayerFailureState() throws {
        let gameID = UUID()
        let launch = PlayerFailureState(
            gameID: gameID,
            gameTitle: "GunPey EX",
            detail: "The engine rejected the startup request.",
            phase: .launch
        )
        try expect(
            launch.headline == "Couldn’t Start “GunPey EX”",
            "launch failure lost its contextual headline"
        )
        try expect(launch.statusTitle == "Couldn’t start", "launch failure status is ambiguous")
        try expect(!launch.preservesLastFrame, "launch failure unexpectedly preserves a frame")
        try expect(
            launch.summary.contains("before the first picture"),
            "launch failure summary lost its first-frame context"
        )

        let playback = PlayerFailureState(
            gameID: gameID,
            gameTitle: "GunPey EX",
            detail: "The emulation core stopped.",
            phase: .playback
        )
        try expect(
            playback.headline == "“GunPey EX” Stopped Unexpectedly",
            "playback failure lost its contextual headline"
        )
        try expect(
            playback.accessibilityAnnouncement.contains("last rendered frame"),
            "failure accessibility announcement omitted its recovery context"
        )
        try expect(
            !playback.accessibilityAnnouncement.contains("The emulation core stopped."),
            "failure accessibility announcement reads raw diagnostics automatically"
        )
        try expect(
            playback.preservesLastFrame
                && playback.summary.contains("last rendered frame"),
            "playback failure no longer promises retained visual evidence"
        )
        try expect(launch.id != playback.id, "distinct failures reused an identity")
    }

    private static func checkPlayerSessionFinalization() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let blockedSaveRoot = root.appendingPathComponent("Saves", isDirectory: true)
        try Data("not a directory".utf8).write(to: blockedSaveRoot)
        let store = GameSaveStore(rootURL: blockedSaveRoot)
        let finalization = PlayerSessionFinalization()
        do {
            try store.save(
                EnginePersistence(regions: [.cartridgeRAM: Data([0x51])]),
                gameID: UUID()
            )
            throw CheckFailure(message: "blocked final-save destination unexpectedly accepted a write")
        } catch {
            await finalization.record(
                PlayerSessionPersistenceFailure(
                    gameTitle: "Final Save Fixture",
                    detail: error.localizedDescription
                )
            )
        }

        let firstFailure = await finalization.persistenceFailure()
        try expect(firstFailure?.gameTitle == "Final Save Fixture", "final-save failure lost its game identity")
        try expect(firstFailure?.detail.isEmpty == false, "final-save failure lost its diagnostic")

        await finalization.record(
            PlayerSessionPersistenceFailure(
                gameTitle: "Later Failure",
                detail: "must not replace the first failure"
            )
        )
        let retainedFailure = await finalization.persistenceFailure()
        try expect(
            retainedFailure == firstFailure,
            "a later teardown error replaced the actionable first save failure"
        )

        let inherited = PlayerSessionFinalization()
        if let firstFailure { await inherited.record(firstFailure) }
        let inheritedFailure = await inherited.persistenceFailure()
        try expect(
            inheritedFailure == firstFailure,
            "rapid session handoff did not preserve the final-save failure"
        )

        let transactionalRoot = root.appendingPathComponent("Transactional", isDirectory: true)
        let transactionalStore = GameSaveStore(rootURL: transactionalRoot)
        let transactionalGameID = UUID()
        let committed = EnginePersistence(regions: [
            .consoleEEPROM: Data(repeating: 0x31, count: 128),
            .cartridgeRAM: Data(repeating: 0x41, count: 64),
        ])
        try transactionalStore.save(committed, gameID: transactionalGameID)
        let transactionalFinalization = PlayerSessionFinalization()
        guard setenv("SWAN_SONG_TEST_SAVE_FAILURE_AFTER_WRITES", "1", 1) == 0 else {
            throw CheckFailure(message: "final-save failure injection could not be enabled")
        }
        let transactionalSaveError: Error?
        do {
            try transactionalStore.save(
                EnginePersistence(regions: [
                    .consoleEEPROM: Data(repeating: 0x91, count: 128),
                    .cartridgeRAM: Data(repeating: 0xa1, count: 64),
                ]),
                gameID: transactionalGameID
            )
            transactionalSaveError = nil
        } catch {
            transactionalSaveError = error
        }
        unsetenv("SWAN_SONG_TEST_SAVE_FAILURE_AFTER_WRITES")
        guard let transactionalSaveError else {
            throw CheckFailure(message: "transactional final-save failure did not fire")
        }
        await transactionalFinalization.record(
            PlayerSessionPersistenceFailure(
                gameTitle: "Transactional Fixture",
                detail: transactionalSaveError.localizedDescription
            )
        )
        let transactionalFailure = await transactionalFinalization.persistenceFailure()
        try expect(
            transactionalFailure?.gameTitle == "Transactional Fixture",
            "transactional final-save failure was not retained for shutdown recovery"
        )
        let retainedGeneration = try transactionalStore.load(gameID: transactionalGameID)
        try expect(
            retainedGeneration.regions == committed.regions,
            "failed final save replaced the previous complete generation"
        )
    }

    private static func checkPlayerSessionRetirementDeadline() async throws {
        let completed = Task<Void, Never> {}
        let completedBeforeDeadline = await PlayerSessionRetirement.finishes(
            completed,
            within: .milliseconds(100)
        )
        try expect(
            completedBeforeDeadline,
            "a completed emulation session missed the termination deadline"
        )

        let delayed = Task<Void, Never> {
            try? await Task.sleep(for: .milliseconds(150))
        }
        let finishedBeforeDeadline = await PlayerSessionRetirement.finishes(
            delayed,
            within: .milliseconds(10)
        )
        try expect(
            !finishedBeforeDeadline,
            "a blocked emulation session bypassed the termination deadline"
        )
        delayed.cancel()
        await delayed.value
    }

    private static func checkROMInspection() throws {
        let info = try EngineSession.inspect(
            rom: makeROM(color: true, saveType: 0x20, mapper: 1)
        )
        try expect(info.fileSize == 128 * 1024, "file size mismatch")
        try expect(info.mappedSize == 128 * 1024, "mapped size mismatch")
        try expect(info.isColor, "Color flag was lost")
        try expect(info.saveType == 0x20, "save type mismatch")
        try expect(info.mapper == 1 && info.hasRTC, "RTC mapper mismatch")
        try expect(info.checksumIsValid && info.footerIsValid, "valid footer was rejected")
        try expect(!info.usesCompactLayout, "power-of-two ROM marked compact")

        var checksumBrokenHomebrew = makeROM()
        checksumBrokenHomebrew[0] = 0x7f
        let compatible = try GameROMValidationPolicy.validateLibraryImage(
            checksumBrokenHomebrew
        )
        try expect(
            !compatible.checksumIsValid,
            "library validation stopped accepting structurally sane checksum-broken ROMs"
        )
        do {
            _ = try GameROMValidationPolicy.validateLibraryImage(
                Data(repeating: 0, count: 128 * 1_024)
            )
            throw CheckFailure(message: "power-of-two junk passed library ROM validation")
        } catch LibraryGameImportError.invalidGame {
            // Expected.
        }
    }

    private static func checkCompactRejection() throws {
        do {
            _ = try EngineSession.inspect(
                rom: Data(repeating: 0, count: 3 * 64 * 1024)
            )
            throw CheckFailure(message: "invalid compact ROM was accepted")
        } catch is SwanEngineError {
            return
        }
    }

    private static func checkBackendTruth() throws {
        let engine = try EngineSession()
        do {
            try engine.stageBootROM(Data(repeating: 0xa5, count: 32))
            throw CheckFailure(message: "an invalid boot ROM size crossed the engine boundary")
        } catch is SwanEngineError {
            // Expected: only the exact 4 KiB and 8 KiB firmware shapes are accepted.
        }
        if engine.capabilities.contains(.execution) {
            var console = Data(repeating: 0, count: 128)
            console[0] = 0x5a
            try engine.stagePersistence(
                EnginePersistence(regions: [.consoleEEPROM: console])
            )
        }
        _ = try engine.load(rom: makeROM())
        if engine.capabilities.contains(.execution) {
            try engine.runFrame()
            let frame = try engine.videoFrame()
            let audio = try engine.audioBatch()
            try expect(frame.width > 0 && frame.height > 0, "live backend returned an empty frame")
            try expect(frame.pixels.count == frame.strideBytes * frame.height, "video byte count mismatch")
            try expect(audio.channels == 2 && audio.sampleRate == 48_000, "audio format mismatch")
            let ram = try engine.captureMemory(.internalRAM)
            try expect(ram.count == 16 * 1024, "mono internal RAM capture size mismatch")
            let persistence = try engine.capturePersistence()
            try expect(
                persistence.regions[.consoleEEPROM]?.first == 0x5a,
                "console EEPROM did not survive the engine boundary"
            )
            let state = try engine.captureState()
            try expect(state.count > 532, "live backend returned a truncated save state")
            try engine.runFrame()
            let expectedReplay = try engine.videoFrame()
            try engine.restoreState(state)
            try engine.runFrame()
            let actualReplay = try engine.videoFrame()
            try expect(
                contentPixels(expectedReplay) == contentPixels(actualReplay),
                "save-state replay changed the game framebuffer"
            )
            var incompatible = state
            incompatible[5] ^= 0xff
            do {
                try engine.restoreState(incompatible)
                throw CheckFailure(message: "incompatible save-state version was accepted")
            } catch let error as SwanEngineError {
                try expect(
                    error.code == Int32(SWAN_RESULT_UNSUPPORTED.rawValue),
                    "incompatible state returned the wrong error"
                )
            }
            try engine.reset()
            try engine.setInput([])
            try engine.runFrame()
            let resetFrame = try engine.videoFrame()
            try expect(
                resetFrame.number == 1,
                "engine reset did not restart deterministic frame numbering"
            )
            return
        }
        do {
            try engine.runFrame()
            throw CheckFailure(message: "pending backend claimed to execute a frame")
        } catch let error as SwanEngineError {
            try expect(
                error.code == Int32(SWAN_RESULT_BACKEND_UNAVAILABLE.rawValue),
                "unexpected pending-backend error"
            )
        }
    }

    private static func checkDataRootContainmentPolicy() throws {
        let fileManager = FileManager.default
        let sandbox = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(
            at: sandbox,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? fileManager.removeItem(at: sandbox) }

        let bundleURL = sandbox.appendingPathComponent(
            "SwanSong.app",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: bundleURL.appendingPathComponent("Contents", isDirectory: true),
            withIntermediateDirectories: true
        )
        let fallbackRoot = sandbox.appendingPathComponent("Fallback", isDirectory: true)
        let bundleCandidate = bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("PrivateData", isDirectory: true)

        let exactResolution = SwanSongDataRootPolicy.resolve(
            requestedRoot: bundleURL,
            bundleURL: bundleURL,
            fallbackRoot: fallbackRoot,
            fileManager: fileManager
        )
        try expect(
            exactResolution.source == .rejectedBundleContainedOverride
                && exactResolution.rootURL == fallbackRoot.standardizedFileURL,
            "an override equal to the app bundle was not rejected"
        )

        let nestedResolution = SwanSongDataRootPolicy.resolve(
            requestedRoot: bundleCandidate,
            bundleURL: bundleURL,
            fallbackRoot: fallbackRoot,
            fileManager: fileManager
        )
        try expect(
            nestedResolution.source == .rejectedBundleContainedOverride
                && nestedResolution.rootURL == fallbackRoot.standardizedFileURL,
            "an override nested inside the app bundle was not rejected"
        )

        let traversedCandidate = bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("..", isDirectory: true)
            .appendingPathComponent("MutableData", isDirectory: true)
        let traversedResolution = SwanSongDataRootPolicy.resolve(
            requestedRoot: traversedCandidate,
            bundleURL: bundleURL,
            fallbackRoot: fallbackRoot,
            fileManager: fileManager
        )
        try expect(
            traversedResolution.source == .rejectedBundleContainedOverride,
            "a standardized path inside the app bundle was not rejected"
        )

        let bundleLink = sandbox.appendingPathComponent("bundle-link", isDirectory: true)
        try fileManager.createSymbolicLink(at: bundleLink, withDestinationURL: bundleURL)
        let symlinkedCandidate = bundleLink
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("LinkedData", isDirectory: true)
        let symlinkedResolution = SwanSongDataRootPolicy.resolve(
            requestedRoot: symlinkedCandidate,
            bundleURL: bundleURL,
            fallbackRoot: fallbackRoot,
            fileManager: fileManager
        )
        try expect(
            symlinkedResolution.source == .rejectedBundleContainedOverride,
            "a symlink-resolved path inside the app bundle was not rejected"
        )

        let nearPrefixRoot = sandbox
            .appendingPathComponent("SwanSong.app.backup", isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
        let nearPrefixResolution = SwanSongDataRootPolicy.resolve(
            requestedRoot: nearPrefixRoot,
            bundleURL: bundleURL,
            fallbackRoot: fallbackRoot,
            fileManager: fileManager
        )
        try expect(
            nearPrefixResolution.source == .environmentOverride
                && nearPrefixResolution.rootURL == nearPrefixRoot.standardizedFileURL,
            "component-aware containment rejected a similarly prefixed external path"
        )

        try expect(
            !fileManager.fileExists(atPath: bundleCandidate.path)
                && !fileManager.fileExists(atPath: fallbackRoot.path),
            "data-root resolution changed the filesystem before a store write"
        )
        try WonderSwanFirmwareStore(
            rootURL: nestedResolution.rootURL
                .appendingPathComponent("Firmware", isDirectory: true)
        ).prepareStorage()
        try ManagedGameStore(
            rootURL: nestedResolution.rootURL
                .appendingPathComponent("Games", isDirectory: true)
        ).prepareStorage()
        try expect(
            !fileManager.fileExists(atPath: bundleCandidate.path),
            "a rejected bundle-contained root received store writes"
        )
        try expect(
            fileManager.fileExists(
                atPath: fallbackRoot.appendingPathComponent("Firmware").path
            ) && fileManager.fileExists(
                atPath: fallbackRoot.appendingPathComponent("Games").path
            ),
            "rejected bundle-contained roots did not fall back before writes"
        )

        let externalRoot = sandbox.appendingPathComponent("ExternalData", isDirectory: true)
        let externalResolution = SwanSongDataRootPolicy.resolve(
            requestedRoot: externalRoot,
            bundleURL: bundleURL,
            fallbackRoot: fallbackRoot,
            fileManager: fileManager
        )
        try expect(
            externalResolution.source == .environmentOverride
                && externalResolution.rootURL == externalRoot.standardizedFileURL,
            "a normal external diagnostics root was not preserved"
        )
        try expect(
            !fileManager.fileExists(atPath: externalRoot.path),
            "external data-root resolution wrote before store preparation"
        )
        try WonderSwanFirmwareStore(
            rootURL: externalResolution.rootURL
                .appendingPathComponent("Firmware", isDirectory: true)
        ).prepareStorage()
        try ManagedGameStore(
            rootURL: externalResolution.rootURL
                .appendingPathComponent("Games", isDirectory: true)
        ).prepareStorage()
        try expect(
            fileManager.fileExists(
                atPath: externalRoot.appendingPathComponent("Firmware").path
            ) && fileManager.fileExists(
                atPath: externalRoot.appendingPathComponent("Games").path
            ),
            "normal external diagnostics roots no longer support store writes"
        )
    }

    private static func checkFirmwareStore() throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: sandbox,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let root = sandbox.appendingPathComponent("Firmware", isDirectory: true)
        let store = WonderSwanFirmwareStore(rootURL: root)

        func fixture(
            _ kind: WonderSwanFirmwareKind,
            fill: UInt8,
            target: UInt32
        ) -> Data {
            var data = Data(repeating: fill, count: kind.expectedByteCount)
            let vector = data.count - 16
            let segment = target >> 4
            let offset = target & 0x0f
            data[vector] = 0xea
            data[vector + 1] = UInt8(offset & 0xff)
            data[vector + 2] = UInt8((offset >> 8) & 0xff)
            data[vector + 3] = UInt8(segment & 0xff)
            data[vector + 4] = UInt8((segment >> 8) & 0xff)
            return data
        }

        func expectUnsafeStorage(
            _ message: String,
            _ operation: () throws -> Void
        ) throws {
            do {
                try operation()
                throw CheckFailure(message: message)
            } catch WonderSwanFirmwareError.unsafeStorage {
                // Expected.
            }
        }

        try store.prepareStorage()
        try store.prepareStorage()

        let monochrome = fixture(.monochrome, fill: 0x90, target: 0x0f_fff0)
        let monoKind = try store.install(monochrome)
        try expect(monoKind == .monochrome, "4 KiB firmware was not identified as WonderSwan")
        try expect(store.isInstalled(.monochrome), "installed WonderSwan firmware was not reported")
        let loadedMonochrome = try store.load(.monochrome)
        try expect(loadedMonochrome == monochrome, "WonderSwan firmware did not round-trip")

        let color = fixture(.color, fill: 0x91, target: 0x0f_e000)
        let colorKind = try store.install(color)
        try expect(colorKind == .color, "8 KiB firmware was not identified as WonderSwan Color")
        try expect(store.isInstalled(.color), "installed Color firmware was not reported")
        let loadedColor = try store.load(.color)
        try expect(loadedColor == color, "Color firmware did not round-trip")

        let monochromeReplacement = fixture(
            .monochrome,
            fill: 0x92,
            target: 0x0f_f100
        )
        let invalidMonochromeTarget = fixture(
            .monochrome,
            fill: 0x93,
            target: 0x0f_e000
        )
        do {
            _ = try store.install(invalidMonochromeTarget)
            throw CheckFailure(message: "firmware with an out-of-range reset target was accepted")
        } catch WonderSwanFirmwareError.missingResetVector {
            // Expected.
        }
        let preservedMonochrome = try Data(
            contentsOf: store.fileURL(for: .monochrome)
        )
        try expect(
            preservedMonochrome == monochrome,
            "failed firmware validation destroyed the installed image"
        )
        _ = try store.install(monochromeReplacement)
        let loadedReplacement = try store.load(.monochrome)
        try expect(
            loadedReplacement == monochromeReplacement,
            "valid firmware replacement did not commit"
        )

        do {
            _ = try store.install(Data(repeating: 0, count: 8 * 1_024))
            throw CheckFailure(message: "an empty firmware image was accepted")
        } catch WonderSwanFirmwareError.emptyImage {
            // Expected.
        }
        do {
            _ = try store.install(Data(repeating: 0x5a, count: 6 * 1_024))
            throw CheckFailure(message: "an unsupported firmware size was accepted")
        } catch WonderSwanFirmwareError.unsupportedSize {
            // Expected.
        }
        do {
            var invalidVector = Data(repeating: 0x90, count: 4 * 1_024)
            invalidVector[invalidVector.count - 1] = 0xea
            _ = try store.install(invalidVector)
            throw CheckFailure(message: "firmware without a reset vector was accepted")
        } catch WonderSwanFirmwareError.missingResetVector {
            // Expected.
        }

        let colorURL = store.fileURL(for: .color)
        try Data(color.dropLast()).write(to: colorURL, options: [.atomic])
        do {
            _ = try store.load(.color)
            throw CheckFailure(message: "truncated installed firmware was accepted")
        } catch WonderSwanFirmwareError.sizeMismatch {
            // Expected.
        }
        _ = try store.install(color)
        let invalidColorTarget = fixture(.color, fill: 0x94, target: 0x01_0000)
        try invalidColorTarget.write(to: colorURL, options: [.atomic])
        do {
            _ = try store.load(.color)
            throw CheckFailure(message: "corrupt installed firmware was accepted")
        } catch WonderSwanFirmwareError.missingResetVector {
            // Expected.
        }
        _ = try store.install(color)

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: root.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: colorURL.path
        )
        let repairedColor = try store.load(.color)
        try expect(
            repairedColor == color,
            "permission repair changed the installed firmware"
        )

        let rootPermissions = try FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as? NSNumber
        try expect(rootPermissions?.intValue == 0o700, "firmware folder permissions were not private")
        let rootOwner = try FileManager.default.attributesOfItem(atPath: root.path)[.ownerAccountID] as? NSNumber
        try expect(rootOwner?.uint32Value == getuid(), "firmware folder was not owned by the current user")
        let colorAttributes = try FileManager.default.attributesOfItem(atPath: colorURL.path)
        let colorPermissions = colorAttributes[.posixPermissions] as? NSNumber
        try expect(colorPermissions?.intValue == 0o600, "firmware file permissions were not private")
        let colorOwner = colorAttributes[.ownerAccountID] as? NSNumber
        try expect(colorOwner?.uint32Value == getuid(), "firmware file was not owned by the current user")

        let rootTarget = sandbox.appendingPathComponent("root-target", isDirectory: true)
        let linkedRoot = sandbox.appendingPathComponent("linked-root", isDirectory: true)
        try FileManager.default.createDirectory(at: rootTarget, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: rootTarget)
        try expectUnsafeStorage("a symlink firmware root was accepted") {
            try WonderSwanFirmwareStore(rootURL: linkedRoot).prepareStorage()
        }

        let parentTarget = sandbox.appendingPathComponent("parent-target", isDirectory: true)
        let linkedParent = sandbox.appendingPathComponent("linked-parent", isDirectory: true)
        try FileManager.default.createDirectory(at: parentTarget, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: linkedParent, withDestinationURL: parentTarget)
        let parentSymlinkStore = WonderSwanFirmwareStore(
            rootURL: linkedParent.appendingPathComponent("Firmware", isDirectory: true)
        )
        try expectUnsafeStorage("a symlink firmware parent was accepted") {
            try parentSymlinkStore.prepareStorage()
        }

        let destinationRoot = sandbox.appendingPathComponent(
            "destination-storage",
            isDirectory: true
        )
        let destinationStore = WonderSwanFirmwareStore(rootURL: destinationRoot)
        try destinationStore.prepareStorage()
        let destinationTarget = sandbox.appendingPathComponent("destination-target.bin")
        let destinationSentinel = Data("do not replace".utf8)
        try destinationSentinel.write(to: destinationTarget)
        try FileManager.default.createSymbolicLink(
            at: destinationStore.fileURL(for: .monochrome),
            withDestinationURL: destinationTarget
        )
        try expectUnsafeStorage("a symlink firmware destination was accepted") {
            _ = try destinationStore.install(monochrome)
        }
        let destinationData = try Data(contentsOf: destinationTarget)
        try expect(
            destinationData == destinationSentinel,
            "a rejected firmware destination modified its symlink target"
        )

        let temporaryFiles = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".firmware-install-") }
        try expect(temporaryFiles.isEmpty, "firmware installation left temporary files behind")

        try store.remove(.monochrome)
        try store.remove(.monochrome)
        try expect(!store.isInstalled(.monochrome), "removed WonderSwan firmware remained installed")
    }

    private static func checkFirmwareImporter() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }

        func fixture(_ kind: WonderSwanFirmwareKind, fill: UInt8) -> Data {
            var data = Data(repeating: fill, count: kind.expectedByteCount)
            let vector = data.count - 16
            data[vector] = 0xea
            data[vector + 1] = 0x00
            data[vector + 2] = 0x00
            data[vector + 3] = 0xff
            data[vector + 4] = 0xff
            return data
        }

        func makeZIP(_ inputs: [URL], at destination: URL) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.arguments = ["-q", "-j", destination.path] + inputs.map(\.path)
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            try expect(process.terminationStatus == 0, "firmware ZIP fixture could not be created")
        }

        let color = fixture(.color, fill: 0x71)
        let colorURL = root.appendingPathComponent("[BIOS] Color Startup.rom")
        try color.write(to: colorURL)
        let directColor = try WonderSwanFirmwareImporter.data(from: colorURL)
        try expect(
            directColor == color,
            "direct firmware importer changed a valid startup file"
        )

        let colorZIP = root.appendingPathComponent("Color Startup.zip")
        try makeZIP([colorURL], at: colorZIP)
        let zippedColor = try WonderSwanFirmwareImporter.data(from: colorZIP)
        try expect(
            zippedColor == color,
            "single-image ZIP importer did not preserve its startup file"
        )

        let monochrome = fixture(.monochrome, fill: 0x72)
        let monochromeURL = root.appendingPathComponent("Mono.rom")
        try monochrome.write(to: monochromeURL)
        let monochromeZIP = root.appendingPathComponent("Mono.zip")
        try makeZIP([monochromeURL], at: monochromeZIP)
        let zippedMonochrome = try WonderSwanFirmwareImporter.data(from: monochromeZIP)
        try expect(
            zippedMonochrome == monochrome,
            "single-image monochrome ZIP did not preserve its startup file"
        )

        let ambiguousZIP = root.appendingPathComponent("Ambiguous.zip")
        try makeZIP([colorURL, monochromeURL], at: ambiguousZIP)
        do {
            _ = try WonderSwanFirmwareImporter.data(from: ambiguousZIP)
            throw CheckFailure(message: "ambiguous firmware ZIP was accepted")
        } catch WonderSwanFirmwareImportError.ambiguousArchive {
            // Expected.
        }

        let linkedURL = root.appendingPathComponent("Linked.rom")
        try FileManager.default.createSymbolicLink(
            at: linkedURL,
            withDestinationURL: colorURL
        )
        do {
            _ = try WonderSwanFirmwareImporter.data(from: linkedURL)
            throw CheckFailure(message: "symlink startup file was accepted")
        } catch WonderSwanFirmwareImportError.invalidDirectFile {
            // Expected.
        }

        let wrongSizeURL = root.appendingPathComponent("Too Large.rom")
        try Data(repeating: 0x44, count: 16 * 1_024).write(to: wrongSizeURL)
        do {
            _ = try WonderSwanFirmwareImporter.data(from: wrongSizeURL)
            throw CheckFailure(message: "oversized direct startup file was accepted")
        } catch WonderSwanFirmwareError.unsupportedSize {
            // Expected.
        }

        let corruptURL = root.appendingPathComponent("Corrupt exact size.rom")
        try Data(repeating: 0x44, count: WonderSwanFirmwareKind.color.expectedByteCount)
            .write(to: corruptURL)
        let corrupt = try WonderSwanFirmwareImporter.data(from: corruptURL)
        do {
            _ = try WonderSwanFirmwareStore.kind(for: corrupt)
            throw CheckFailure(message: "corrupt exact-size startup data passed end-to-end validation")
        } catch WonderSwanFirmwareError.emptyImage {
            // Expected: the importer preflights the file shape; the store owns
            // final content validation immediately before its atomic install.
        }
    }

    private static func checkFreshBootDeterminism() throws {
        let fixtureROM: Data
        if let path = ProcessInfo.processInfo.environment["SWAN_SONG_FRESH_BOOT_ROM"] {
            fixtureROM = try LibraryGameImageImporter.image(
                from: URL(fileURLWithPath: path)
            ).data
        } else {
            fixtureROM = makeROM()
        }
        let fixtureFirmware = try ProcessInfo.processInfo.environment[
            "SWAN_SONG_FRESH_BOOT_FIRMWARE"
        ].map {
            try WonderSwanFirmwareImporter.data(
                from: URL(fileURLWithPath: $0)
            )
        }
        func endpoint() throws -> String? {
            let engine = try EngineSession()
            guard engine.capabilities.contains(.execution) else { return nil }
            if let fixtureFirmware { try engine.stageBootROM(fixtureFirmware) }
            _ = try engine.load(rom: fixtureROM)
            for _ in 1...30 {
                try engine.setInput([])
                try engine.runFrame()
            }
            return try TranslationRouteCheckpoint.fingerprint(engine.videoFrame())
        }

        let first = try endpoint()
        let second = try endpoint()
        if let first, let second {
            try expect(first == second, "two fresh ares boots reached different frame-30 pixels")
        }
    }

    private static func checkDeterministicRTC() throws {
        let seed: UInt64 = 946_684_800  // 2000-01-01 00:00:00 UTC
        let defaultEngine = try EngineSession()
        try expect(
            defaultEngine.rtcMode == .wallClock,
            "the default engine RTC mode no longer follows wall-clock time"
        )

        do {
            _ = try EngineSession(rtcMode: .deterministic(seedUnixSeconds: 0))
            throw CheckFailure(message: "a zero deterministic RTC seed was accepted")
        } catch let error as SwanEngineError {
            try expect(
                error.code == Int32(SWAN_RESULT_INVALID_ARGUMENT.rawValue),
                "an invalid deterministic RTC seed returned the wrong error"
            )
        }

        struct Snapshot {
            let frame: EngineVideoFrame
            let state: Data
            let rtc: Data
        }
        func snapshot(seed: UInt64) throws -> Snapshot? {
            let engine = try EngineSession(
                rtcMode: .deterministic(seedUnixSeconds: seed)
            )
            guard engine.capabilities.contains(.execution) else { return nil }
            defer { try? engine.unload() }
            _ = try engine.load(rom: makeROM(saveType: 0x00, mapper: 1))
            for _ in 0..<20 {
                try engine.setInput([])
                try engine.runFrame()
            }
            let frame = try engine.videoFrame()
            let state = try engine.captureState()
            let rtc = try XCTUnwrap(
                engine.capturePersistence().regions[.rtc]
            )
            return Snapshot(frame: frame, state: state, rtc: rtc)
        }

        guard let first = try snapshot(seed: seed),
              let second = try snapshot(seed: seed),
              let changed = try snapshot(seed: seed + 86_400) else {
            return
        }
        try expect(
            contentPixels(first.frame) == contentPixels(second.frame),
            "equal deterministic RTC seeds changed same-frame video"
        )
        try expect(
            first.state == second.state,
            "equal deterministic RTC seeds changed same-frame emulator state"
        )
        try expect(
            first.rtc == second.rtc,
            "equal deterministic RTC seeds changed RTC persistence"
        )
        try expect(first.rtc.count == 18, "deterministic RTC persistence has the wrong size")
        let persistedTimestamp = first.rtc[8..<16].enumerated().reduce(UInt64(0)) {
            $0 | (UInt64($1.element) << UInt64($1.offset * 8))
        }
        try expect(
            persistedTimestamp == seed,
            "deterministic RTC persistence did not retain the configured seed"
        )
        try expect(
            first.rtc.prefix(8) == Data([0x00, 0x01, 0x01, 0x06, 0x00, 0x00, 0x00, 0x40]),
            "deterministic RTC registers were not initialized from UTC"
        )
        try expect(
            first.rtc != changed.rtc && first.state != changed.state,
            "changing the deterministic RTC seed did not change RTC-backed state"
        )
    }

    private static func checkRunnerFreshBootDeterminism() async throws {
        guard let path = ProcessInfo.processInfo.environment["SWAN_SONG_FRESH_BOOT_ROM"] else {
            return
        }
        let rom = try LibraryGameImageImporter.image(
            from: URL(fileURLWithPath: path)
        ).data
        let firmware = try ProcessInfo.processInfo.environment[
            "SWAN_SONG_FRESH_BOOT_FIRMWARE"
        ].map {
            try WonderSwanFirmwareImporter.data(
                from: URL(fileURLWithPath: $0)
            )
        }
        func endpoint() async throws -> String {
            let runner = try EmulationRunner()
            if let firmware { try await runner.stageBootROM(firmware) }
            _ = try await runner.load(rom: rom)
            var frame: EngineVideoFrame?
            for _ in 1...30 {
                frame = try await runner.nextFrame(input: []).video
            }
            let hash = try TranslationRouteCheckpoint.fingerprint(
                try XCTUnwrap(frame)
            )
            try await runner.stop()
            return hash
        }
        let first = try await endpoint()
        let second = try await endpoint()
        try expect(first == second, "two fresh EmulationRunner boots reached different frame-30 pixels")
    }

    private static func checkPlayerWindowLayout() throws {
        let visible = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let current = CGRect(x: 200, y: 110, width: 1_040, height: 680)

        let horizontal = PlayerWindowLayout.targetFrame(
            currentFrame: current,
            visibleFrame: visible,
            orientation: .horizontal
        )
        try expect(horizontal.size == CGSize(width: 1_040, height: 680), "horizontal fit lost its ideal size")
        try expect(abs(horizontal.midX - current.midX) < 0.5, "horizontal fit did not preserve the window center")
        try expect(abs(horizontal.midY - current.midY) < 0.5, "horizontal fit did not preserve the window center")

        let vertical = PlayerWindowLayout.targetFrame(
            currentFrame: current,
            visibleFrame: visible,
            orientation: .vertical
        )
        try expect(vertical.height > vertical.width, "vertical fit did not produce a portrait window")
        try expect(vertical.width == 700 && vertical.height == 860, "vertical fit lost its ideal size")
        try expect(visible.insetBy(dx: 20, dy: 20).contains(vertical), "vertical fit escaped the visible screen")

        let edgeWindow = CGRect(x: 1_300, y: 760, width: 1_040, height: 680)
        let clamped = PlayerWindowLayout.targetFrame(
            currentFrame: edgeWindow,
            visibleFrame: visible,
            orientation: .vertical
        )
        try expect(visible.insetBy(dx: 20, dy: 20).contains(clamped), "edge fit was not clamped to the visible screen")

        let compactVisible = CGRect(x: -800, y: 40, width: 700, height: 600)
        let compact = PlayerWindowLayout.targetFrame(
            currentFrame: CGRect(x: -760, y: 80, width: 620, height: 720),
            visibleFrame: compactVisible,
            orientation: .vertical
        )
        try expect(compact.width < 700 && compact.height < 860, "small-screen fit was not scaled down")
        try expect(compactVisible.insetBy(dx: 20, dy: 20).contains(compact), "small-screen fit escaped its display")
        let compactMinimum = PlayerWindowLayout.minimumSize(
            for: .vertical,
            visibleFrame: compactVisible
        )
        try expect(
            compactMinimum.width <= compact.width && compactMinimum.height <= compact.height,
            "small-screen minimum exceeded the fitted portrait target"
        )

        let restored = PlayerWindowLayout.restoredFrame(
            libraryFrame: CGRect(x: 100, y: 100, width: 1_040, height: 680),
            currentFrame: CGRect(x: 1_300, y: 820, width: 700, height: 860),
            visibleFrame: visible
        )
        try expect(visible.insetBy(dx: 20, dy: 20).contains(restored), "restored library window was not screen-clamped")
        try expect(restored.width == 1_040 && restored.height == 680, "library restore lost the saved size")
    }

    private static func checkBootROMStaging() throws {
        let canExecute = try { () -> Bool in
            let probe = try EngineSession()
            return probe.capabilities.contains(.execution)
        }()
        guard canExecute else { return }

        func bootROM(size: Int, runtimeOrientation: UInt8? = nil) -> Data {
            var data = Data(repeating: 0x90, count: size)
            var resetCode: [UInt8] = []
            if let runtimeOrientation {
                // mov al, value; out LCD_ICON, al
                resetCode += [0xb0, runtimeOrientation, 0xe6, 0x15]
            }
            // jmp far FFFF:0000 into the cartridge mapping.
            resetCode += [0xea, 0x00, 0x00, 0xff, 0xff]
            data.replaceSubrange(
                (data.count - 16)..<(data.count - 16 + resetCode.count),
                with: resetCode
            )
            return data
        }

        do {
            let mono = try EngineSession()
            try mono.stageBootROM(bootROM(size: 4 * 1_024))
            _ = try mono.load(rom: makeROM())
            do {
                try mono.stageBootROM(bootROM(size: 4 * 1_024))
                throw CheckFailure(message: "boot ROM staging after load was accepted")
            } catch let error as SwanEngineError {
                try expect(
                    error.code == Int32(SWAN_RESULT_UNSUPPORTED.rawValue),
                    "boot ROM staging after load returned the wrong error"
                )
            }
        }

        do {
            let color = try EngineSession()
            try color.stageBootROM(bootROM(size: 8 * 1_024))
            _ = try color.load(rom: makeROM(color: true))
        }

        do {
            let vertical = try EngineSession()
            try vertical.stageBootROM(bootROM(size: 4 * 1_024))
            _ = try vertical.load(rom: makeROM(vertical: true))
            try vertical.runFrame()
            let verticalFrame = try vertical.videoFrame()
            try expect(verticalFrame.isVertical, "vertical ROM metadata did not rotate the live framebuffer")
            try expect(verticalFrame.height > verticalFrame.width, "vertical framebuffer dimensions remained horizontal")
        }

        do {
            let rotatesVertical = try EngineSession()
            // LCD_ICON bit 1 requests vertical presentation at runtime.
            try rotatesVertical.stageBootROM(
                bootROM(size: 4 * 1_024, runtimeOrientation: 0x02)
            )
            _ = try rotatesVertical.load(rom: makeROM(vertical: false))
            try rotatesVertical.runFrame()
            let frame = try rotatesVertical.videoFrame()
            try expect(frame.isVertical, "runtime LCD_ICON vertical request was ignored")
            try expect(frame.height > frame.width, "runtime vertical request kept horizontal dimensions")
        }

        do {
            let rotatesHorizontal = try EngineSession()
            // LCD_ICON bit 2 requests horizontal presentation at runtime.
            try rotatesHorizontal.stageBootROM(
                bootROM(size: 4 * 1_024, runtimeOrientation: 0x04)
            )
            _ = try rotatesHorizontal.load(rom: makeROM(vertical: true))
            try rotatesHorizontal.runFrame()
            let frame = try rotatesHorizontal.videoFrame()
            try expect(!frame.isVertical, "runtime LCD_ICON horizontal request was ignored")
            try expect(frame.width > frame.height, "runtime horizontal request kept vertical dimensions")
        }

        do {
            let monoForColor = try EngineSession()
            try monoForColor.stageBootROM(bootROM(size: 4 * 1_024))
            do {
                _ = try monoForColor.load(rom: makeROM(color: true))
                throw CheckFailure(message: "4 KiB firmware was accepted for a Color game")
            } catch let error as SwanEngineError {
                try expect(
                    error.code == Int32(SWAN_RESULT_INVALID_ARGUMENT.rawValue),
                    "Color firmware mismatch returned the wrong error"
                )
            }
        }

        do {
            let colorForMono = try EngineSession()
            try colorForMono.stageBootROM(bootROM(size: 8 * 1_024))
            do {
                _ = try colorForMono.load(rom: makeROM())
                throw CheckFailure(message: "8 KiB firmware was accepted for a monochrome game")
            } catch let error as SwanEngineError {
                try expect(
                    error.code == Int32(SWAN_RESULT_INVALID_ARGUMENT.rawValue),
                    "monochrome firmware mismatch returned the wrong error"
                )
            }
        }
    }

    private static func checkLibraryRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = GameLibraryStore(
            fileURL: root.appendingPathComponent("Library.json")
        )
        let metadata = try EngineSession.inspect(rom: makeROM())
        let game = GameRecord(
            title: "Open Fixture",
            fileURL: URL(fileURLWithPath: "/tmp/open.ws"),
            metadata: metadata,
            isFavorite: true,
            compatibilityEvidence: GameCompatibilityEvidence(
                reachedVideoAt: Date(timeIntervalSince1970: 1_000),
                verdict: .works,
                note: "Played through the opening stage.",
                updatedAt: Date(timeIntervalSince1970: 2_000)
            )
        )
        let document = GameLibraryDocument(games: [game])
        try store.save(document)
        let loaded = try store.load()
        try expect(loaded == document, "library round trip mismatch")

        let encoded = try JSONEncoder().encode(document)
        guard var legacyObject = try JSONSerialization.jsonObject(with: encoded) as? [String: Any],
              var legacyGames = legacyObject["games"] as? [[String: Any]],
              !legacyGames.isEmpty else {
            throw CheckFailure(message: "could not construct a legacy library fixture")
        }
        legacyGames[0].removeValue(forKey: "addedAt")
        legacyGames[0].removeValue(forKey: "managedROM")
        legacyGames[0].removeValue(forKey: "sourceFileName")
        legacyGames[0].removeValue(forKey: "artworkPreference")
        legacyGames[0].removeValue(forKey: "compatibilityEvidence")
        legacyObject["games"] = legacyGames
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        try legacyData.write(to: store.fileURL, options: [.atomic])
        let migrated = try store.load()
        try expect(
            migrated.games.first?.addedAt == nil,
            "a pre-addedAt library did not decode backward-compatibly"
        )
        try expect(
            migrated.games.first?.managedROM == nil
                && migrated.games.first?.sourceFileName == nil
                && migrated.games.first?.artworkPreference == nil
                && migrated.games.first?.compatibilityEvidence == nil,
            "a schema-1 library did not decode the new optional fields backward-compatibly"
        )
    }

    private static func checkGameConfidence() throws {
        let reachedAt = Date(timeIntervalSince1970: 10_000)
        let reviewedAt = Date(timeIntervalSince1970: 20_000)
        let laterFrameAt = Date(timeIntervalSince1970: 30_000)

        let untested = GameCompatibilityEvidence()
        try expect(untested.status == .untested, "empty evidence was not untested")

        let reached = untested.recordingReachedVideo(at: reachedAt)
        try expect(
            reached.status == .reachedVideo && reached.reachedVideoAt == reachedAt,
            "reached-video evidence did not change its status"
        )
        try expect(
            reached.recordingReachedVideo(at: laterFrameAt) == reached,
            "reached-video evidence was not idempotent"
        )

        let works = reached.updatingVerdict(.works, at: reviewedAt)
        try expect(
            works.status == .confirmedWorks
                && works.reachedVideoAt == reachedAt
                && works.updatedAt == reviewedAt,
            "works verdict replaced or lost automatic evidence"
        )
        try expect(
            works.recordingReachedVideo(at: laterFrameAt).status == .confirmedWorks,
            "automatic video evidence overrode a user verdict"
        )

        let issues = works.updatingVerdict(.issues, at: laterFrameAt)
        try expect(issues.status == .reportedIssues, "issues verdict did not take precedence")
        let clearedVerdict = issues.updatingVerdict(nil, at: laterFrameAt)
        try expect(
            clearedVerdict.status == .reachedVideo
                && clearedVerdict.reachedVideoAt == reachedAt
                && clearedVerdict.updatedAt == nil,
            "clearing a verdict did not fall back to reached-video evidence"
        )

        let noted = reached.updatingNote("  Opening menu works.  ", at: reviewedAt)
        try expect(
            noted.note == "Opening menu works." && noted.updatedAt == reviewedAt,
            "compatibility note normalization or timestamp mismatch"
        )
        let clearedNote = noted.updatingNote(" \n ", at: laterFrameAt)
        try expect(
            clearedNote.note == nil && clearedNote.updatedAt == nil,
            "blank compatibility note did not clear the user report"
        )

        let confidence = GameConfidence(
            launchReadiness: .startupFileRequired,
            compatibility: .reportedIssues,
            romIntegrity: .checksumMismatch
        )
        try expect(
            confidence.launchReadiness == .startupFileRequired
                && confidence.compatibility == .reportedIssues
                && confidence.romIntegrity == .checksumMismatch,
            "game confidence collapsed its three independent axes"
        )

        let width = 237
        let height = 144
        let stride = width * 4
        var railOnly = Data(repeating: 0x44, count: stride * height)
        railOnly[224 * 4] = 0x99
        let railOnlyFrame = EngineVideoFrame(
            pixels: railOnly,
            width: width,
            height: height,
            strideBytes: stride,
            isVertical: false,
            number: 1
        )
        try expect(
            !GameConfidence.isNonUniformNativeGameRaster(railOnlyFrame),
            "hardware-icon rail was mistaken for reached game video"
        )
        var activeRaster = railOnly
        activeRaster[4] = 0x88
        let activeFrame = EngineVideoFrame(
            pixels: activeRaster,
            width: width,
            height: height,
            strideBytes: stride,
            isVertical: false,
            number: 2
        )
        try expect(
            GameConfidence.isNonUniformNativeGameRaster(activeFrame),
            "non-uniform native game video was not detected"
        )
    }

    private static func checkBatchGameImport() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        func makeZIP(
            _ relativePaths: [String],
            at destination: URL,
            from directory: URL = root,
            options: [String] = []
        ) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.currentDirectoryURL = directory
            process.arguments = ["-q"] + options + [destination.path] + relativePaths
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            try expect(process.terminationStatus == 0, "game ZIP fixture could not be created")
        }

        let alpha = root.appendingPathComponent("Alpha.ws")
        let beta = nested.appendingPathComponent("Beta.WSC")
        let hidden = root.appendingPathComponent(".Hidden.ws")
        let notes = root.appendingPathComponent("Notes.txt")
        try makeROM().write(to: alpha)
        try makeROM(color: true).write(to: beta)
        try makeROM().write(to: hidden)
        try Data("not a game".utf8).write(to: notes)

        let planner = GameImportPlanner()
        let recursive = try planner.files(in: root)
        try expect(recursive.count == 2, "recursive import discovery count mismatch")
        try expect(
            recursive.map(\.lastPathComponent) == ["Alpha.ws", "Beta.WSC"],
            "recursive import discovery was not deterministic or skipped visible games"
        )
        let shallow = try planner.files(in: root, recursively: false)
        try expect(
            shallow.map(\.lastPathComponent) == ["Alpha.ws"],
            "nonrecursive import discovery entered a subfolder or included a hidden file"
        )

        let planned = planner.plan([beta, alpha, alpha, notes])
        try expect(planned.duplicateCount == 1, "duplicate import selection was not collapsed")
        try expect(
            planned.files.map(\.lastPathComponent) == ["Alpha.ws", "Beta.WSC"],
            "explicit import selection was not deterministically ordered"
        )
        try expect(
            planned.unsupportedFiles.map(\.lastPathComponent) == ["Notes.txt"],
            "unsupported import selection was not isolated"
        )

        let managedRoot = root
            .appendingPathComponent("Managed", isDirectory: true)
            .appendingPathComponent("Games", isDirectory: true)
        let managedStore = ManagedGameStore(rootURL: managedRoot)
        let importer = GameBatchImporter(managedStore: managedStore)
        let initial = importer.importFiles([beta, alpha, alpha, notes], into: [])
        try expect(initial.addedCount == 2, "batch import did not add both valid games")
        try expect(initial.updatedCount == 0, "new batch import reported an update")
        try expect(initial.duplicateCount == 1, "batch import duplicate count mismatch")
        try expect(initial.failures.count == 1, "batch import did not aggregate unsupported files")
        try expect(initial.games.count == 2, "batch import library count mismatch")
        try expect(
            initial.games.allSatisfy { $0.managedROM != nil && managedStore.isManaged($0.fileURL) },
            "library import did not adopt private managed copies"
        )
        let rootAttributes = try FileManager.default.attributesOfItem(atPath: managedRoot.path)
        try expect(
            (rootAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700,
            "managed game folder permissions were not private"
        )
        for game in initial.games {
            let attributes = try FileManager.default.attributesOfItem(atPath: game.fileURL.path)
            try expect(
                (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
                "managed game file permissions were not private"
            )
            guard let reference = game.managedROM else {
                throw CheckFailure(message: "managed game reference was missing")
            }
            let expectedData = game.metadata.isColor ? makeROM(color: true) : makeROM()
            let loadedData = try managedStore.load(reference)
            try expect(
                loadedData == expectedData,
                "managed game bytes did not round-trip"
            )
        }

        var existing = initial.games
        guard let alphaIndex = existing.firstIndex(where: { !$0.metadata.isColor }) else {
            throw CheckFailure(message: "monochrome import was missing")
        }
        existing[alphaIndex].isFavorite = true
        let originalLastPlayedAt = Date(timeIntervalSince1970: 1_234)
        let originalAddedAt = Date(timeIntervalSince1970: 567)
        existing[alphaIndex].lastPlayedAt = originalLastPlayedAt
        existing[alphaIndex].addedAt = originalAddedAt
        let originalID = existing[alphaIndex].id
        let alias = root.appendingPathComponent("Alpha Alias.ws")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: alpha)
        let hardLink = root.appendingPathComponent("Alpha Hard Link.ws")
        try FileManager.default.linkItem(at: alpha, to: hardLink)
        let refreshed = importer.importFiles([alias, alpha, hardLink], into: existing)
        try expect(refreshed.addedCount == 0, "content aliases created a duplicate library record")
        try expect(refreshed.updatedCount == 1, "existing managed game was not refreshed")
        try expect(refreshed.duplicateCount == 1, "hard-link content was not deduplicated by SHA-256")
        try expect(refreshed.failures.count == 1, "a direct symbolic link was not rejected")
        guard let refreshedAlpha = refreshed.games.first(where: { $0.id == originalID }) else {
            throw CheckFailure(message: "refresh changed the existing game identity")
        }
        try expect(refreshedAlpha.isFavorite, "refresh discarded existing game preferences")
        try expect(
            refreshedAlpha.lastPlayedAt == originalLastPlayedAt,
            "refresh discarded the existing last-played date"
        )
        try expect(
            refreshedAlpha.addedAt == originalAddedAt,
            "refresh changed the existing added date"
        )

        let invalid = root.appendingPathComponent("Broken.ws")
        try Data(repeating: 0, count: 128 * 1024).write(to: invalid)
        let failed = importer.importFiles([invalid], into: refreshed.games)
        try expect(failed.successCount == 0, "invalid ROM was reported as imported")
        try expect(failed.failures.count == 1, "invalid ROM failure was not aggregated")
        try expect(
            failed.games.map(\.id) == refreshed.games.map(\.id),
            "failed batch import changed the library"
        )

        // A renamed Color ROM must never acquire PCV2 identity from either a
        // direct extension or an archive member. Exercise both accepted PCV2
        // spellings and prove the failure happens before managed publication.
        let pcv2MismatchFixture = root.appendingPathComponent(
            "PCV2 Color Mismatch",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: pcv2MismatchFixture,
            withIntermediateDirectories: true
        )
        let renamedColorPC2 = pcv2MismatchFixture.appendingPathComponent(
            "Renamed Color.pc2"
        )
        let renamedColorPCV2 = pcv2MismatchFixture.appendingPathComponent(
            "Renamed Color.pcv2"
        )
        let colorMismatchData = makeROM(color: true)
        try colorMismatchData.write(to: renamedColorPC2)
        try colorMismatchData.write(to: renamedColorPCV2)

        let renamedColorPC2ZIP = root.appendingPathComponent(
            "Renamed Color PC2.zip"
        )
        let renamedColorPCV2ZIP = root.appendingPathComponent(
            "Renamed Color PCV2.zip"
        )
        try makeZIP(
            [renamedColorPC2.lastPathComponent],
            at: renamedColorPC2ZIP,
            from: pcv2MismatchFixture
        )
        try makeZIP(
            [renamedColorPCV2.lastPathComponent],
            at: renamedColorPCV2ZIP,
            from: pcv2MismatchFixture
        )

        for source in [
            renamedColorPC2,
            renamedColorPCV2,
            renamedColorPC2ZIP,
            renamedColorPCV2ZIP,
        ] {
            do {
                _ = try LibraryGameImageImporter.image(from: source)
                throw CheckFailure(
                    message: "Color ROM renamed through \(source.pathExtension) was accepted as PCV2"
                )
            } catch LibraryGameImportError.invalidGame {
                // Expected before ManagedGameStore receives an image.
            }
        }

        let rejectedPCV2ManagedRoot = root
            .appendingPathComponent("Rejected PCV2", isDirectory: true)
            .appendingPathComponent("Games", isDirectory: true)
        let rejectedPCV2Importer = GameBatchImporter(
            managedStore: ManagedGameStore(rootURL: rejectedPCV2ManagedRoot)
        )
        let rejectedPCV2Batch = rejectedPCV2Importer.importFiles(
            [
                renamedColorPC2,
                renamedColorPCV2,
                renamedColorPC2ZIP,
                renamedColorPCV2ZIP,
            ],
            into: refreshed.games
        )
        try expect(
            rejectedPCV2Batch.successCount == 0
                && rejectedPCV2Batch.failures.count == 4
                && rejectedPCV2Batch.createdManagedReferences.isEmpty,
            "renamed Color PCV2 imports reached managed publication"
        )
        try expect(
            rejectedPCV2Batch.games.map(\.id) == refreshed.games.map(\.id),
            "renamed Color PCV2 imports changed the library"
        )
        try expect(
            !FileManager.default.fileExists(atPath: rejectedPCV2ManagedRoot.path)
                && !FileManager.default.fileExists(
                    atPath: rejectedPCV2ManagedRoot.deletingLastPathComponent().path
                ),
            "renamed Color PCV2 imports created a managed-game folder"
        )

        // ManagedGameStore is a second trust boundary. Forge every
        // incompatible explicit model/data pairing and prove validation runs
        // before the store creates either a canonical file or a temp orphan.
        let mismatchStoreRoot = root
            .appendingPathComponent("Model Mismatch", isDirectory: true)
            .appendingPathComponent("Games", isDirectory: true)
        let mismatchStore = ManagedGameStore(rootURL: mismatchStoreRoot)
        let monoMismatchData = makeROM()
        let monoMismatchMetadata = try GameROMValidationPolicy.validateLibraryImage(
            monoMismatchData
        )
        let colorMismatchMetadata = try GameROMValidationPolicy.validateLibraryImage(
            colorMismatchData
        )
        let mismatches: [(String, Data, ROMMetadata, EngineHardwareModel)] = [
            ("mono-as-color", monoMismatchData, monoMismatchMetadata, .wonderSwanColor),
            ("mono-as-crystal", monoMismatchData, monoMismatchMetadata, .swanCrystal),
            ("color-as-mono", colorMismatchData, colorMismatchMetadata, .wonderSwan),
            ("color-as-pcv2", colorMismatchData, colorMismatchMetadata, .pocketChallengeV2),
        ]
        for (name, data, metadata, hardwareModel) in mismatches {
            let image = LibraryGameImportImage(
                data: data,
                suggestedTitle: name,
                sourceFileName: "\(name).ws",
                metadata: metadata,
                sha256: ManagedGameStore.sha256(data),
                hardwareModel: hardwareModel
            )
            do {
                _ = try mismatchStore.install(image)
                throw CheckFailure(
                    message: "managed store accepted incompatible hardware model \(hardwareModel.rawValue)"
                )
            } catch ManagedGameStoreError.invalidROM {
                // Expected before prepareStorage() or temp-file creation.
            }
            try expect(
                !FileManager.default.fileExists(atPath: mismatchStoreRoot.path)
                    && !FileManager.default.fileExists(
                        atPath: mismatchStoreRoot.deletingLastPathComponent().path
                    ),
                "managed model mismatch created an orphaned store entry"
            )
        }

        let archiveFixture = root.appendingPathComponent("Archive Fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: archiveFixture, withIntermediateDirectories: true)
        let gammaData = makeROM(color: true, vertical: true, saveType: 0x20, mapper: 1)
        let gamma = archiveFixture.appendingPathComponent("[Gamma Game].wsc")
        let readme = archiveFixture.appendingPathComponent("Read Me.txt")
        try gammaData.write(to: gamma)
        try Data("private game archive".utf8).write(to: readme)
        let gammaZIP = root.appendingPathComponent("Gamma Collection.zip")
        try makeZIP(
            ["[Gamma Game].wsc", "Read Me.txt"],
            at: gammaZIP,
            from: archiveFixture
        )
        let archiveImage = try LibraryGameImageImporter.image(from: gammaZIP)
        try expect(archiveImage.data == gammaData, "bracketed ZIP member did not extract exactly")
        try expect(archiveImage.suggestedTitle == "[Gamma Game]", "ZIP member title was not preserved")

        let zipped = importer.importFiles([gammaZIP], into: refreshed.games)
        try expect(zipped.addedCount == 1, "one-game ZIP was not added")
        guard let gammaGame = zipped.games.first(where: { $0.title == "[Gamma Game]" }),
              let gammaReference = gammaGame.managedROM else {
            throw CheckFailure(message: "ZIP import did not create a managed game")
        }
        try expect(
            gammaGame.sourceFileName == gammaZIP.lastPathComponent,
            "ZIP source name was not retained for user-facing provenance"
        )
        let directDuplicate = importer.importFiles([gamma], into: zipped.games)
        try expect(
            directDuplicate.addedCount == 0 && directDuplicate.updatedCount == 1,
            "the same ROM imported directly and through ZIP did not deduplicate by content"
        )
        try expect(
            directDuplicate.games.first(where: { $0.managedROM?.sha256 == gammaReference.sha256 })?.id
                == gammaGame.id,
            "direct/ZIP deduplication changed the stable game identity"
        )
        let ambiguousZIP = root.appendingPathComponent("Ambiguous Games.zip")
        try makeZIP(["Alpha.ws", "Nested/Beta.WSC"], at: ambiguousZIP)
        do {
            _ = try LibraryGameImageImporter.image(from: ambiguousZIP)
            throw CheckFailure(message: "multiple-game ZIP was accepted")
        } catch LibraryGameImportError.ambiguousArchive {
            // Expected.
        }
        let noGameZIP = root.appendingPathComponent("No Game.zip")
        try makeZIP(["Notes.txt"], at: noGameZIP)
        do {
            _ = try LibraryGameImageImporter.image(from: noGameZIP)
            throw CheckFailure(message: "ZIP without a game was accepted")
        } catch LibraryGameImportError.noGameInArchive {
            // Expected.
        }
        let encryptedZIP = root.appendingPathComponent("Encrypted Game.zip")
        try makeZIP(
            ["Read Me.txt", "[Gamma Game].wsc"],
            at: encryptedZIP,
            from: archiveFixture,
            options: ["-P", "test-only-password"]
        )
        do {
            _ = try LibraryGameImageImporter.image(from: encryptedZIP)
            throw CheckFailure(message: "encrypted game ZIP was accepted")
        } catch LibraryGameImportError.encryptedArchive {
            // Expected.
        }
        let linkedMember = archiveFixture.appendingPathComponent("Linked Game.wsc")
        try FileManager.default.createSymbolicLink(
            at: linkedMember,
            withDestinationURL: archiveFixture.appendingPathComponent("[Gamma Game].wsc")
        )
        let linkedZIP = root.appendingPathComponent("Linked Game.zip")
        try makeZIP(
            ["Linked Game.wsc"],
            at: linkedZIP,
            from: archiveFixture,
            options: ["-y"]
        )
        do {
            _ = try LibraryGameImageImporter.image(from: linkedZIP)
            throw CheckFailure(message: "symbolic-link game member was accepted")
        } catch LibraryGameImportError.unsafeMember {
            // Expected.
        }

        try FileManager.default.removeItem(at: gammaZIP)
        try FileManager.default.removeItem(at: gamma)
        let sourceIndependentGamma = try managedStore.load(gammaReference)
        try expect(
            sourceIndependentGamma == gammaData,
            "managed ZIP game depended on its deleted source archive"
        )

        let sentinel = managedRoot.appendingPathComponent("notes.txt")
        try Data("keep me".utf8).write(to: sentinel)
        try managedStore.prune(retaining: directDuplicate.games.compactMap(\.managedROM))
        try expect(
            FileManager.default.fileExists(atPath: sentinel.path),
            "managed-game pruning deleted an unrelated sentinel file"
        )

        let gammaURL = try managedStore.url(for: gammaReference)
        var tampered = gammaData
        tampered[0] ^= 0xff
        try tampered.write(to: gammaURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: gammaURL.path
        )
        do {
            _ = try managedStore.load(gammaReference)
            throw CheckFailure(message: "tampered managed game passed integrity validation")
        } catch ManagedGameStoreError.changedManagedCopy {
            // Expected.
        }
        do {
            _ = try managedStore.install(archiveImage)
            throw CheckFailure(message: "install silently overwrote a tampered digest destination")
        } catch ManagedGameStoreError.changedManagedCopy {
            // Expected: an existing digest path must prove its bytes before reuse.
        }
        try expect(
            managedStore.health(of: gammaReference) == .changed,
            "tampered managed game did not report a changed health state"
        )

        let tamperedBeforeRejectedRepairs = try Data(contentsOf: gammaURL)
        let differentData = makeROM(color: true, vertical: false, saveType: 0x20, mapper: 1)
        let differentImage = LibraryGameImportImage(
            data: differentData,
            suggestedTitle: "Different Revision",
            sourceFileName: "Different Revision.wsc",
            metadata: try GameROMValidationPolicy.validateLibraryImage(differentData),
            sha256: ManagedGameStore.sha256(differentData)
        )
        do {
            _ = try managedStore.repair(differentImage, matching: gammaReference)
            throw CheckFailure(message: "a different ROM was accepted as a managed-game repair")
        } catch ManagedGameStoreError.wrongRepairImage {
            // Expected.
        }
        let destinationAfterDifferentRepair = try Data(contentsOf: gammaURL)
        try expect(
            destinationAfterDifferentRepair == tamperedBeforeRejectedRepairs,
            "a rejected different-ROM repair changed the managed destination"
        )

        let forgedMetadataImage = LibraryGameImportImage(
            data: archiveImage.data,
            suggestedTitle: archiveImage.suggestedTitle,
            sourceFileName: archiveImage.sourceFileName,
            metadata: differentImage.metadata,
            sha256: archiveImage.sha256
        )
        do {
            _ = try managedStore.repair(forgedMetadataImage, matching: gammaReference)
            throw CheckFailure(message: "repair accepted valid bytes with forged metadata")
        } catch ManagedGameStoreError.wrongRepairImage {
            // Expected.
        }
        let destinationAfterForgedRepair = try Data(contentsOf: gammaURL)
        try expect(
            destinationAfterForgedRepair == tamperedBeforeRejectedRepairs,
            "a rejected forged-metadata repair changed the managed destination"
        )

        let repairedFromZIP = try managedStore.repair(archiveImage, matching: gammaReference)
        try expect(repairedFromZIP == gammaURL, "repair changed the content-addressed game URL")
        let loadedAfterZIPRepair = try managedStore.load(gammaReference)
        try expect(loadedAfterZIPRepair == gammaData, "ZIP repair did not restore exact bytes")
        try expect(managedStore.health(of: gammaReference) == .healthy, "ZIP repair did not restore healthy status")
        let repairedAttributes = try FileManager.default.attributesOfItem(atPath: gammaURL.path)
        try expect(
            (repairedAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
            "repair did not restore private file permissions"
        )

        try FileManager.default.removeItem(at: gammaURL)
        try expect(managedStore.health(of: gammaReference) == .missing, "deleted managed game did not report missing")
        let directRepairSource = root.appendingPathComponent("Gamma Repair.wsc")
        try gammaData.write(to: directRepairSource)
        let directRepairImage = try LibraryGameImageImporter.image(from: directRepairSource)
        _ = try managedStore.repair(directRepairImage, matching: gammaReference)
        let loadedAfterDirectRepair = try managedStore.load(gammaReference)
        try expect(loadedAfterDirectRepair == gammaData, "direct repair did not restore exact bytes")

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: managedRoot.path
        )
        try expect(
            managedStore.health(of: gammaReference) == .changed,
            "non-private managed root did not report changed"
        )
        let publicRootAttributes = try FileManager.default.attributesOfItem(atPath: managedRoot.path)
        try expect(
            (publicRootAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o755,
            "read-only health scan silently changed managed-root permissions"
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: managedRoot.path
        )

        let sentinelTarget = root.appendingPathComponent("repair-symlink-target.bin")
        let sentinelBytes = Data("must not change".utf8)
        try sentinelBytes.write(to: sentinelTarget)
        try FileManager.default.removeItem(at: gammaURL)
        try FileManager.default.createSymbolicLink(at: gammaURL, withDestinationURL: sentinelTarget)
        do {
            _ = try managedStore.repair(directRepairImage, matching: gammaReference)
            throw CheckFailure(message: "repair replaced a symbolic-link destination")
        } catch ManagedGameStoreError.unsafeStorage {
            // Expected.
        }
        let sentinelAfterRejectedRepair = try Data(contentsOf: sentinelTarget)
        try expect(
            sentinelAfterRejectedRepair == sentinelBytes,
            "rejected symbolic-link repair changed its target"
        )
        try FileManager.default.removeItem(at: gammaURL)
        _ = try managedStore.repair(directRepairImage, matching: gammaReference)
        let repairTemps = try FileManager.default.contentsOfDirectory(
            at: managedRoot,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".game-repair-") }
        try expect(repairTemps.isEmpty, "managed-game repair left temporary files behind")

        let invalidGammaReference = ManagedGameReference(
            sha256: gammaReference.sha256,
            byteCount: 0,
            fileExtension: gammaReference.fileExtension
        )
        try expect(
            managedStore.health(of: invalidGammaReference) == .invalidReference,
            "invalid managed-game identity was reported as a repairable copy"
        )
        try managedStore.prune(retaining: [invalidGammaReference])
        try expect(
            FileManager.default.fileExists(atPath: gammaURL.path),
            "pruning an invalid library reference deleted its canonical managed bytes"
        )

        let unsafeTarget = root.appendingPathComponent("Unsafe Store Target", isDirectory: true)
        try FileManager.default.createDirectory(at: unsafeTarget, withIntermediateDirectories: true)
        let linkedStoreRoot = root.appendingPathComponent("Linked Games", isDirectory: true)
        try FileManager.default.createSymbolicLink(
            at: linkedStoreRoot,
            withDestinationURL: unsafeTarget
        )
        do {
            _ = try ManagedGameStore(rootURL: linkedStoreRoot).prepareStorage()
            throw CheckFailure(message: "symbolic-link managed-game root was accepted")
        } catch ManagedGameStoreError.unsafeStorage {
            // Expected.
        }
    }

    private static func checkGameArtworkStore() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GameArtworkStore(
            rootURL: root.appendingPathComponent("Artwork", isDirectory: true)
        )
        guard let png = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEUlEQVR4nGPkEpH7z8DAwAAABp0BPTRxJesAAAAASUVORK5CYII="
        ) else {
            throw CheckFailure(message: "artwork PNG fixture could not be decoded")
        }
        let gameID = UUID()
        let saved = try store.save(
            png,
            gameID: gameID,
            romChecksum: 0x1234,
            romFileSize: 128 * 1_024,
            frameNumber: 600,
            isVertical: false,
            source: .automatic
        )
        let loaded = try store.load(
            gameID: gameID,
            romChecksum: 0x1234,
            romFileSize: 128 * 1_024
        )
        try expect(loaded == saved, "library artwork did not round-trip")
        let stale = try store.load(
            gameID: gameID,
            romChecksum: 0x9999,
            romFileSize: 128 * 1_024
        )
        try expect(
            stale == nil,
            "artwork from a different ROM revision was reused"
        )
        let directoryAttributes = try FileManager.default.attributesOfItem(
            atPath: store.directoryURL(for: gameID).path
        )
        try expect(
            (directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700,
            "artwork directory permissions were not private"
        )
        try store.remove(gameID: gameID)
        let removed = try store.load(
            gameID: gameID,
            romChecksum: 0x1234,
            romFileSize: 128 * 1_024
        )
        try expect(
            removed == nil,
            "removed library artwork remained available"
        )
    }

    private static func checkLibraryQuery() throws {
        let monochrome = try EngineSession.inspect(rom: makeROM())
        let color = try EngineSession.inspect(rom: makeROM(color: true))
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)
        let games = [
            GameRecord(
                title: "Zeta Puzzle",
                fileURL: URL(fileURLWithPath: "/tmp/Zeta.ws"),
                metadata: monochrome,
                lastPlayedAt: older,
                addedAt: Date(timeIntervalSince1970: 100)
            ),
            GameRecord(
                title: "Alpha Color Quest",
                fileURL: URL(fileURLWithPath: "/tmp/Alpha.wsc"),
                metadata: color,
                lastPlayedAt: newer,
                isFavorite: true,
                addedAt: Date(timeIntervalSince1970: 300)
            ),
            GameRecord(
                title: "Beta Story",
                fileURL: URL(fileURLWithPath: "/tmp/Beta.ws"),
                metadata: monochrome,
                isFavorite: true,
                addedAt: Date(timeIntervalSince1970: 200)
            ),
        ]
        let query = GameLibraryQuery()

        try expect(
            query.games(in: games).map(\.title)
                == ["Alpha Color Quest", "Beta Story", "Zeta Puzzle"],
            "title sort was not localized and deterministic"
        )
        try expect(
            query.games(in: games, filter: .favorites).map(\.title)
                == ["Alpha Color Quest", "Beta Story"],
            "favorites filter included a nonfavorite game"
        )
        try expect(
            query.games(in: games, filter: .recentlyPlayed, sortedBy: .recentlyPlayed)
                .map(\.title) == ["Alpha Color Quest", "Zeta Puzzle"],
            "recent filter or play-date ordering was incorrect"
        )
        try expect(
            query.games(in: games, matching: "alpha color").map(\.title)
                == ["Alpha Color Quest"],
            "multi-term title search did not require every term"
        )
        try expect(
            query.games(in: games, matching: "wsc").map(\.title)
                == ["Alpha Color Quest"],
            "file-extension/platform search did not find the Color game"
        )
        try expect(
            query.games(in: games, sortedBy: .recentlyAdded).map(\.title)
                == ["Alpha Color Quest", "Beta Story", "Zeta Puzzle"],
            "recently-added ordering did not use durable import timestamps"
        )

        var mixedDateGames = games
        mixedDateGames[2].addedAt = nil
        try expect(
            query.games(in: mixedDateGames, sortedBy: .recentlyAdded).map(\.title)
                == ["Alpha Color Quest", "Zeta Puzzle", "Beta Story"],
            "legacy records were not placed after dated recently-added records"
        )

        let legacyGames = games.map { game in
            var legacy = game
            legacy.addedAt = nil
            return legacy
        }
        try expect(
            query.games(in: legacyGames, sortedBy: .recentlyAdded).map(\.title)
                == ["Beta Story", "Alpha Color Quest", "Zeta Puzzle"],
            "legacy recently-added ordering did not fall back to import order"
        )
    }

    private static func checkSaveRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = GameSaveStore(rootURL: root)
        let gameID = UUID()
        let expected = EnginePersistence(regions: [
            .cartridgeRAM: Data([0x01, 0x23, 0x45, 0x67]),
            .rtc: Data(repeating: 0xa5, count: 18),
        ])
        try store.save(expected, gameID: gameID)
        let loaded = try store.load(gameID: gameID)
        try expect(loaded.regions == expected.regions, "atomic save round trip mismatch")
    }

    private static func checkTransactionalSaveFailure() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GameSaveStore(rootURL: root)
        let gameID = UUID()
        let original = EnginePersistence(regions: [
            .consoleEEPROM: Data(repeating: 0x11, count: 128),
            .cartridgeRAM: Data(repeating: 0x22, count: 64),
            .rtc: Data(repeating: 0x33, count: 18),
        ])
        let replacement = EnginePersistence(regions: [
            .consoleEEPROM: Data(repeating: 0xaa, count: 128),
            .cartridgeRAM: Data(repeating: 0xbb, count: 64),
            .rtc: Data(repeating: 0xcc, count: 18),
        ])
        try store.save(original, gameID: gameID)

        func failsAfterFirstWrite(_ operation: () throws -> Void) throws -> Bool {
            guard setenv("SWAN_SONG_TEST_SAVE_FAILURE_AFTER_WRITES", "1", 1) == 0 else {
                throw CheckFailure(message: "save failure injection could not be enabled")
            }
            defer { unsetenv("SWAN_SONG_TEST_SAVE_FAILURE_AFTER_WRITES") }
            do {
                try operation()
                return false
            } catch {
                return true
            }
        }

        let didFail = try failsAfterFirstWrite {
            try store.save(replacement, gameID: gameID)
        }
        try expect(didFail, "injected multi-region save failure did not fire")
        let afterFailedSave = try store.load(gameID: gameID)
        try expect(
            afterFailedSave.regions == original.regions,
            "a failed multi-region save exposed a mixed or partial generation"
        )

        let snapshots = root
            .appendingPathComponent(gameID.uuidString, isDirectory: true)
            .appendingPathComponent(".snapshots", isDirectory: true)
        let remaining = try FileManager.default.contentsOfDirectory(
            at: snapshots,
            includingPropertiesForKeys: nil
        )
        try expect(
            remaining.count == 1 && !remaining[0].lastPathComponent.hasPrefix(".staging-"),
            "failed save left an incomplete snapshot beside the committed generation"
        )

        try store.save(replacement, gameID: gameID)
        let afterSuccessfulSave = try store.load(gameID: gameID)
        try expect(
            afterSuccessfulSave.regions == replacement.regions,
            "a successful save after rollback did not commit the complete generation"
        )

        let failedFirstSaveID = UUID()
        let failedFirstSave = try failsAfterFirstWrite {
            try store.save(replacement, gameID: failedFirstSaveID)
        }
        try expect(failedFirstSave, "injected first-save failure did not fire")
        try expect(
            !FileManager.default.fileExists(
                atPath: root.appendingPathComponent(failedFirstSaveID.uuidString).path
            ),
            "a failed first save exposed an incomplete game directory"
        )

        let beforeFailedImport = try store.load(gameID: gameID)
        let failedImport = try failsAfterFirstWrite {
            try store.replaceCartridgeSave(
                EnginePersistence(regions: [
                    .cartridgeEEPROM: Data(repeating: 0x77, count: 128),
                ]),
                gameID: gameID
            )
        }
        try expect(failedImport, "injected Pocket replacement failure did not fire")
        let afterFailedImport = try store.load(gameID: gameID)
        try expect(
            afterFailedImport.regions == beforeFailedImport.regions,
            "a failed Pocket replacement changed the committed save generation"
        )

        func failsAt(
            _ point: String,
            _ operation: () throws -> Void
        ) throws -> Bool {
            guard setenv("SWAN_SONG_TEST_SAVE_FAILURE_POINT", point, 1) == 0 else {
                throw CheckFailure(message: "save checkpoint injection could not be enabled")
            }
            defer { unsetenv("SWAN_SONG_TEST_SAVE_FAILURE_POINT") }
            do {
                try operation()
                return false
            } catch {
                return true
            }
        }

        let beforePublishFailure = try store.load(gameID: gameID)
        let publicationFailed = try failsAt("before-publish") {
            try store.save(original, gameID: gameID)
        }
        try expect(publicationFailed, "pre-publication failure injection did not fire")
        let afterPublicationFailure = try store.load(gameID: gameID)
        try expect(
            afterPublicationFailure.regions == beforePublishFailure.regions,
            "a snapshot-move failure changed the published save generation"
        )

        guard setenv("SWAN_SONG_TEST_SAVE_FAILURE_POINT", "cleanup", 1) == 0 else {
            throw CheckFailure(message: "cleanup failure injection could not be enabled")
        }
        try store.save(original, gameID: gameID)
        unsetenv("SWAN_SONG_TEST_SAVE_FAILURE_POINT")
        let afterCleanupFailure = try store.load(gameID: gameID)
        try expect(
            afterCleanupFailure.regions == original.regions,
            "cleanup failure was reported after a successful pointer commit"
        )
        try store.save(replacement, gameID: gameID)
        let postCleanupChildren = try FileManager.default.contentsOfDirectory(
            at: snapshots,
            includingPropertiesForKeys: nil
        )
        try expect(
            postCleanupChildren.count == 2
                && postCleanupChildren.allSatisfy {
                    !$0.lastPathComponent.hasPrefix(".staging-")
                },
            "a later successful save did not prune generations older than the recovery pair"
        )

        let legacyID = UUID()
        let legacyDirectory = root.appendingPathComponent(legacyID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        let legacyConsole = Data(repeating: 0x61, count: 128)
        let legacyRAM = Data(repeating: 0x62, count: 64)
        try legacyConsole.write(to: legacyDirectory.appendingPathComponent("console.eeprom"))
        try legacyRAM.write(to: legacyDirectory.appendingPathComponent("cartridge.ram"))
        try store.save(
            EnginePersistence(regions: [.rtc: Data(repeating: 0x63, count: 18)]),
            gameID: legacyID
        )
        let migrated = try store.load(gameID: legacyID)
        try expect(
            migrated.regions[.consoleEEPROM] == legacyConsole
                && migrated.regions[.cartridgeRAM] == legacyRAM
                && migrated.regions[.rtc] == Data(repeating: 0x63, count: 18),
            "legacy flat save migration did not preserve omitted regions"
        )
        try expect(
            !FileManager.default.fileExists(
                atPath: legacyDirectory.appendingPathComponent("console.eeprom").path
            ),
            "successful legacy migration retained a stale flat save alongside its snapshot"
        )

        func currentGeneration(for id: UUID) throws -> UUID {
            let pointer = root
                .appendingPathComponent(id.uuidString, isDirectory: true)
                .appendingPathComponent(".current-save.json")
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: pointer))
            guard let dictionary = object as? [String: Any],
                  let raw = dictionary["generation"] as? String,
                  let generation = UUID(uuidString: raw) else {
                throw CheckFailure(message: "save pointer did not expose its generation")
            }
            return generation
        }

        let corruptPointerID = UUID()
        let corruptPointerDirectory = root.appendingPathComponent(
            corruptPointerID.uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: corruptPointerDirectory,
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(
            to: corruptPointerDirectory.appendingPathComponent(".current-save.json")
        )
        do {
            _ = try store.load(gameID: corruptPointerID)
            throw CheckFailure(message: "corrupt save pointer unexpectedly loaded")
        } catch GameSaveStoreError.invalidSnapshotManifest {
            // Expected typed failure; it must not look like a missing ROM.
        }

        let recoveryID = UUID()
        try store.save(original, gameID: recoveryID)
        let previousGeneration = try currentGeneration(for: recoveryID)
        try store.save(replacement, gameID: recoveryID)
        let brokenGeneration = try currentGeneration(for: recoveryID)
        let recoverySnapshots = root
            .appendingPathComponent(recoveryID.uuidString, isDirectory: true)
            .appendingPathComponent(".snapshots", isDirectory: true)
        try FileManager.default.removeItem(
            at: recoverySnapshots.appendingPathComponent(brokenGeneration.uuidString)
        )
        let recoveredMissingGeneration = try store.loadWithStatus(gameID: recoveryID)
        let recoveredPointerGeneration = try currentGeneration(for: recoveryID)
        try expect(
            recoveredMissingGeneration.persistence.regions == original.regions
                && recoveredMissingGeneration.recoveredPreviousGeneration
                && recoveredPointerGeneration == previousGeneration,
            "missing current generation did not recover and repoint to the retained snapshot"
        )

        try store.save(replacement, gameID: recoveryID)
        let damagedRegionGeneration = try currentGeneration(for: recoveryID)
        try FileManager.default.removeItem(
            at: recoverySnapshots
                .appendingPathComponent(damagedRegionGeneration.uuidString, isDirectory: true)
                .appendingPathComponent("cartridge.ram")
        )
        let recoveredMissingRegion = try store.loadWithStatus(gameID: recoveryID)
        try expect(
            recoveredMissingRegion.persistence.regions == original.regions
                && recoveredMissingRegion.recoveredPreviousGeneration,
            "manifest validation accepted a partial snapshot instead of the recovery generation"
        )

        let noFallbackID = UUID()
        try store.save(original, gameID: noFallbackID)
        let noFallbackGeneration = try currentGeneration(for: noFallbackID)
        try FileManager.default.removeItem(
            at: root
                .appendingPathComponent(noFallbackID.uuidString, isDirectory: true)
                .appendingPathComponent(".snapshots", isDirectory: true)
                .appendingPathComponent(noFallbackGeneration.uuidString, isDirectory: true)
        )
        do {
            _ = try store.load(gameID: noFallbackID)
            throw CheckFailure(message: "missing sole save generation unexpectedly loaded")
        } catch GameSaveStoreError.missingSnapshot {
            // Expected typed failure.
        }

        let missingPointerID = UUID()
        try store.save(original, gameID: missingPointerID)
        let missingPointerDirectory = root.appendingPathComponent(
            missingPointerID.uuidString,
            isDirectory: true
        )
        try FileManager.default.removeItem(
            at: missingPointerDirectory.appendingPathComponent(".current-save.json")
        )
        do {
            _ = try store.load(gameID: missingPointerID)
            throw CheckFailure(message: "orphaned snapshots loaded as an empty legacy save")
        } catch GameSaveStoreError.invalidSnapshotManifest {
            // Expected: intact snapshots are never silently ignored.
        }
    }

    private static func checkConcurrentSaveSerialization() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let firstStore = GameSaveStore(rootURL: root)
        let secondStore = GameSaveStore(rootURL: root)
        let gameID = UUID()
        let console = Data(repeating: 0x81, count: 128)
        let rtc = Data(repeating: 0x82, count: 18)

        let errors = await withTaskGroup(of: String?.self, returning: [String].self) { group in
            group.addTask {
                do {
                    try firstStore.save(
                        EnginePersistence(regions: [.consoleEEPROM: console]),
                        gameID: gameID
                    )
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }
            group.addTask {
                do {
                    try secondStore.save(
                        EnginePersistence(regions: [.rtc: rtc]),
                        gameID: gameID
                    )
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }
            var failures: [String] = []
            for await failure in group {
                if let failure { failures.append(failure) }
            }
            return failures
        }
        try expect(errors.isEmpty, "concurrent save operations failed: \(errors.joined(separator: "; "))")
        let merged = try firstStore.load(gameID: gameID)
        try expect(
            merged.regions[.consoleEEPROM] == console && merged.regions[.rtc] == rtc,
            "concurrent subset saves lost one committed region"
        )

        let interleavingErrors = await withTaskGroup(
            of: String?.self,
            returning: [String].self
        ) { group in
            group.addTask {
                do {
                    for value in UInt8(0)..<UInt8(20) {
                        try firstStore.save(
                            EnginePersistence(regions: [
                                .cartridgeRAM: Data(repeating: value, count: 64),
                            ]),
                            gameID: gameID
                        )
                    }
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }
            group.addTask {
                do {
                    for _ in 0..<40 {
                        let snapshot = try secondStore.load(gameID: gameID)
                        guard snapshot.regions[.consoleEEPROM] == console,
                              snapshot.regions[.rtc] == rtc,
                              snapshot.regions[.cartridgeRAM].map({ $0.count == 64 }) ?? true else {
                            throw CheckFailure(message: "reader observed a partial save generation")
                        }
                    }
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }
            var failures: [String] = []
            for await failure in group {
                if let failure { failures.append(failure) }
            }
            return failures
        }
        try expect(
            interleavingErrors.isEmpty,
            "load/save interleaving exposed an invalid generation: \(interleavingErrors.joined(separator: "; "))"
        )
    }

    private static func checkCartridgeSaveReplacement() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GameSaveStore(rootURL: root)
        let gameID = UUID()
        let console = Data(repeating: 0x11, count: 128)
        let flash = Data(repeating: 0x22, count: 64)
        try store.save(
            EnginePersistence(regions: [
                .consoleEEPROM: console,
                .cartridgeRAM: Data(repeating: 0x33, count: 32 * 1024),
                .cartridgeFlash: flash,
                .rtc: Data(repeating: 0x44, count: 18),
            ]),
            gameID: gameID
        )
        let eeprom = Data(repeating: 0x55, count: 128)
        try store.replaceCartridgeSave(
            EnginePersistence(regions: [.cartridgeEEPROM: eeprom]),
            gameID: gameID
        )
        let loaded = try store.load(gameID: gameID)
        try expect(loaded.regions[.consoleEEPROM] == console, "Pocket import replaced console EEPROM")
        try expect(loaded.regions[.cartridgeFlash] == flash, "Pocket import replaced cartridge flash")
        try expect(loaded.regions[.cartridgeEEPROM] == eeprom, "Pocket import EEPROM mismatch")
        try expect(loaded.regions[.cartridgeRAM] == nil, "Pocket import retained stale SRAM")
        try expect(loaded.regions[.rtc] == nil, "Pocket import retained stale RTC")
    }

    private static func checkFramePacingPolicy() throws {
        let policy = FramePacingPolicy()
        let nominal = 636.0 / 48_000.0
        let target = nominal * policy.targetBufferedFrames
        try expect(
            policy.targetBufferedFrames == 4,
            "default pacing lost its four-batch scheduling-jitter cushion"
        )
        try expect(target < 0.18, "default pacing target exceeded the bounded audio queue")
        let recoveryThreshold = policy.discontinuity.recoveryThresholdSeconds(
            nominalBatchSeconds: nominal,
            targetBufferedFrames: policy.targetBufferedFrames
        )
        try expect(
            abs(recoveryThreshold - target) < 0.000_001,
            "discontinuity recovery no longer begins at the complete steady-buffer horizon"
        )
        try expect(
            !policy.discontinuity.shouldRecover(
                hostGapSeconds: 0.040,
                queuedAudioSeconds: 0.020,
                nominalBatchSeconds: nominal,
                targetBufferedFrames: policy.targetBufferedFrames,
                transportWasPrimed: true
            ),
            "ordinary sub-horizon starvation was incorrectly hidden as a discontinuity"
        )
        try expect(
            policy.discontinuity.shouldRecover(
                hostGapSeconds: 0.120,
                queuedAudioSeconds: 0.050,
                nominalBatchSeconds: nominal,
                targetBufferedFrames: policy.targetBufferedFrames,
                transportWasPrimed: true
            ),
            "a queue-draining host discontinuity was not recoverable"
        )
        try expect(
            !policy.discontinuity.shouldRecover(
                hostGapSeconds: 0.120,
                queuedAudioSeconds: 0.050,
                nominalBatchSeconds: nominal,
                targetBufferedFrames: policy.targetBufferedFrames,
                transportWasPrimed: false
            ),
            "startup buffering was incorrectly reported as discontinuity recovery"
        )
        try expect(
            !policy.discontinuity.shouldRecover(
                hostGapSeconds: 0.120,
                queuedAudioSeconds: 0.130,
                nominalBatchSeconds: nominal,
                targetBufferedFrames: policy.targetBufferedFrames,
                transportWasPrimed: true
            ),
            "a host gap that did not drain the renderer queue reset the transport"
        )
        try expect(
            abs(policy.discontinuity.reprimeTargetSeconds(
                nominalBatchSeconds: nominal
            ) - nominal * 3) < 0.000_001,
            "discontinuity recovery lost its bounded three-batch re-prime"
        )
        let steady = policy.delaySeconds(
            producedAudioFrames: 636,
            sampleRate: 48_000,
            queuedAudioSeconds: target,
            fastForwarding: false
        )
        let starving = policy.delaySeconds(
            producedAudioFrames: 636,
            sampleRate: 48_000,
            queuedAudioSeconds: 0,
            fastForwarding: false
        )
        let backedUp = policy.delaySeconds(
            producedAudioFrames: 636,
            sampleRate: 48_000,
            queuedAudioSeconds: target * 2,
            fastForwarding: false
        )
        try expect(abs(steady - nominal) < 0.000_001, "steady-state pacing drifted")
        try expect(starving < nominal, "starved audio should reduce frame delay")
        try expect(backedUp > nominal, "backed-up audio should increase frame delay")
        try expect(
            policy.delaySeconds(
                producedAudioFrames: 636,
                sampleRate: 48_000,
                queuedAudioSeconds: target,
                fastForwarding: true
            ) == 0,
            "fast-forward pacing should not sleep"
        )
    }

    private static func checkDisplayProfiles() throws {
        try expect(DisplayProfile.allCases.count == 4, "display profile catalog mismatch")
        let pure = DisplayProfile.purePixels.parameters
        try expect(
            pure.saturation == 1 && pure.contrast == 1 && pure.brightness == 0,
            "Pure Pixels must preserve source color"
        )
        try expect(pure.pixelGridStrength == 0, "Pure Pixels must not add a panel grid")
        try expect(
            DisplayProfile.wonderSwanLCD.parameters.saturation == 0,
            "WonderSwan LCD must produce a monochrome panel"
        )
        let appearances = Set(DisplayProfile.allCases.map { profile in
            let values = profile.parameters
            return "\(values.saturation):\(values.contrast):\(values.brightness):\(values.pixelGridStrength):\(values.responsePersistence):\(values.tintRed):\(values.tintGreen):\(values.tintBlue)"
        })
        try expect(appearances.count == DisplayProfile.allCases.count, "display profiles must have distinct appearances")
        try expect(
            DisplayProfile.colorLCD.parameters.responsePersistence
                > DisplayProfile.swanCrystalLCD.parameters.responsePersistence,
            "SwanCrystal should respond faster than the original Color panel"
        )
    }

    private static func checkControllerProfiles() throws {
        let profile = ControllerProfile.default
        let input = profile.input(for: [
            .dpadUp,
            .rightStickRight,
            .buttonEast,
            .buttonSouth,
            .menu,
            .leftShoulder,
        ])
        try expect(input.contains(.x1), "default controller profile lost X1")
        try expect(input.contains(.y2), "default controller profile lost Y2")
        try expect(input.contains(.a) && input.contains(.b), "default controller action mapping mismatch")
        try expect(input.contains(.start) && input.contains(.volume), "default console-control mapping mismatch")
        try expect(!input.contains(.x2) && !input.contains(.y1), "controller profile emitted an unpressed direction")

        let reassigned = profile.updating(.x1, to: .buttonEast)
        try expect(reassigned.preset == .custom, "custom controller binding retained a preset label")
        try expect(reassigned.element(for: .x1) == .buttonEast, "custom controller binding mismatch")
        try expect(reassigned.element(for: .a) == nil, "duplicate physical binding was not displaced")
        let customInput = reassigned.input(for: [.buttonEast])
        try expect(customInput.contains(.x1), "custom physical input did not reach X1")
        try expect(!customInput.contains(.a), "displaced custom input still activated A")

        let face = ControllerProfile.preset(.faceDiamond)
        let faceInput = face.input(for: [.buttonNorth, .rightShoulder, .rightTrigger])
        try expect(faceInput.contains(.y1), "face-diamond preset lost Y1")
        try expect(faceInput.contains(.a) && faceInput.contains(.b), "face-diamond actions mismatch")

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ControllerProfileStore(fileURL: root.appendingPathComponent("ControllerProfile.json"))
        try store.save(reassigned)
        let loaded = try store.load()
        try expect(loaded == reassigned, "controller profile round trip mismatch")
    }

    private static func checkPocketSaveCodec() throws {
        let sramMetadata = try EngineSession.inspect(rom: makeROM(saveType: 0x01))
        let sramCodec = try PocketSaveCodec(metadata: sramMetadata)
        try expect(sramCodec.layout.payloadByteCount == 32 * 1024, "type-01 Pocket size mismatch")
        let sram = Data((0..<(32 * 1024)).map { UInt8(truncatingIfNeeded: $0) })
        let sramExport = try sramCodec.export(
            EnginePersistence(regions: [.cartridgeRAM: sram])
        )
        try expect(sramExport.data == sram, "Pocket SRAM export changed its payload")
        let sramImport = try sramCodec.importSave(sramExport.data)
        try expect(sramImport.persistence.regions[.cartridgeRAM] == sram, "Pocket SRAM import mismatch")
        try expect(sramImport.report.format == .canonical, "canonical Pocket save misreported")

        let rtcMetadata = try EngineSession.inspect(
            rom: makeROM(color: true, saveType: 0x10, mapper: 1)
        )
        let rtcCodec = try PocketSaveCodec(metadata: rtcMetadata)
        let eeprom = Data(repeating: 0xa5, count: 128)
        var aresRTC = Data([
            0x26, 0x07, 0x14, 0x02, 0x21, 0x35, 0x48, 0x40,
            0x78, 0x56, 0x34, 0x12, 0, 0, 0, 0, 0, 0,
        ])
        let rtcExport = try rtcCodec.export(
            EnginePersistence(regions: [
                .cartridgeEEPROM: eeprom,
                .rtc: aresRTC,
            ])
        )
        try expect(rtcExport.data.count == 140, "Pocket EEPROM+RTC export size mismatch")
        try expect(rtcExport.data[128] == 0x52 && rtcExport.data[129] == 0x54, "Pocket RTC marker mismatch")
        let rtcImport = try rtcCodec.importSave(rtcExport.data)
        try expect(rtcImport.persistence.regions[.cartridgeEEPROM] == eeprom, "Pocket EEPROM import mismatch")
        let restoredRTC = try XCTUnwrap(rtcImport.persistence.regions[.rtc])
        try expect(restoredRTC[0..<7] == aresRTC[0..<7], "Pocket RTC calendar translation mismatch")
        try expect(restoredRTC[8..<16] == aresRTC[8..<16], "Pocket RTC timestamp translation mismatch")

        var legacy = Data(repeating: 0x6c, count: 2 * 1024)
        legacy.append(rtcExport.data.suffix(PocketSaveCodec.rtcTrailerByteCount))
        let legacyImport = try rtcCodec.importSave(legacy)
        try expect(legacyImport.report.format == .legacyPaddedEEPROM, "legacy Pocket EEPROM was not reported")
        try expect(
            legacyImport.persistence.regions[.cartridgeEEPROM] == Data(repeating: 0x6c, count: 128),
            "legacy Pocket EEPROM padding was not removed"
        )

        aresRTC[0] = 0xfa
        do {
            _ = try rtcCodec.export(
                EnginePersistence(regions: [.cartridgeEEPROM: eeprom, .rtc: aresRTC])
            )
            throw CheckFailure(message: "invalid ares RTC calendar was exported")
        } catch is PocketSaveError {}
    }

    private static func checkFrameDifferential() throws {
        let expected = Data([0, 10, 20, 30, 40, 50])
        let identical = try FrameDifferential.compareRGB888(
            expected: expected,
            actual: expected
        )
        try expect(identical.differentPixelCount == 0, "identical RGB frames differed")
        try expect(identical.meanAbsoluteChannelError == 0, "identical RGB error was nonzero")
        let changed = try FrameDifferential.compareRGB888(
            expected: expected,
            actual: Data([0, 12, 20, 35, 40, 45])
        )
        try expect(changed.pixelCount == 2 && changed.differentPixelCount == 2, "RGB pixel difference mismatch")
        try expect(changed.maximumChannelError == 5, "RGB maximum error mismatch")
        try expect(
            abs(changed.meanAbsoluteChannelError - 2) < 0.000_001,
            "RGB mean absolute error mismatch"
        )
        let visualizationExpected = Data([
            40, 40, 40, 40, 40, 40,
            40, 40, 40, 40, 40, 40,
        ])
        let visualizationActual = Data([
            40, 40, 40, 255, 40, 40,
            40, 90, 40, 40, 40, 40,
        ])
        let visualization = try FrameDifferential.visualizeRGB888(
            expected: visualizationExpected,
            actual: visualizationActual,
            width: 2,
            height: 2
        )
        try expect(
            visualization.difference.differentPixelCount == 2,
            "RGB heatmap difference count mismatch"
        )
        try expect(
            visualization.changedBounds == RGBFrameBounds(
                x: 0,
                y: 0,
                width: 2,
                height: 2
            ),
            "RGB heatmap changed bounds mismatch"
        )
        try expect(
            visualization.heatmapRGB888.count == visualizationExpected.count,
            "RGB heatmap byte count mismatch"
        )
        try expect(
            visualization.heatmapRGB888[3] == 255
                && visualization.heatmapRGB888[6] == 255,
            "RGB heatmap did not visibly mark changed pixels"
        )
        let identicalVisualization = try FrameDifferential.visualizeRGB888(
            expected: visualizationExpected,
            actual: visualizationExpected,
            width: 2,
            height: 2
        )
        try expect(
            identicalVisualization.changedBounds == nil,
            "identical RGB heatmap reported changed bounds"
        )
        try expect(
            FrameDifferential.fnv1a64(Data()) == "cbf29ce484222325",
            "RGB FNV identity mismatch"
        )
        let neutral = Data([0, 0, 0, 255, 255, 255])
        let reflective = Data([39, 35, 20, 230, 226, 205])
        let neutralized = try FrameDifferential.normalizeMonochromeRGB888(neutral)
        let reflectiveNeutralized = try FrameDifferential.normalizeMonochromeRGB888(reflective)
        try expect(
            neutralized == reflectiveNeutralized,
            "monochrome structural normalization retained LCD tint"
        )
        let bgra = Data([
            3, 2, 1, 255, 6, 5, 4, 255,
            9, 8, 7, 255, 12, 11, 10, 255,
        ])
        let rgb = try FrameDifferential.rgb888FromBGRA(
            bgra,
            frameWidth: 2,
            frameHeight: 2,
            strideBytes: 8,
            contentWidth: 2,
            contentHeight: 1
        )
        try expect(rgb == Data([1, 2, 3, 4, 5, 6]), "BGRA frame conversion mismatch")
    }

    private static func checkTranslationVisualDivergence() throws {
        func makeRoute(
            totalFrames: UInt64,
            events: [TranslationRouteEvent]? = nil,
            finalFrame: EngineVideoFrame? = nil
        ) throws -> TranslationRoute {
            let resolvedEvents = events ?? [
                TranslationRouteEvent(frameIndex: 0, inputMask: 0),
            ]
            let frame = finalFrame ?? makeRouteFrame(number: totalFrames)
            return try TranslationRoute(
                createdAt: Date(timeIntervalSince1970: 100),
                recordedFrom: .original,
                sourceROM: TranslationArtifactDigest(
                    byteCount: 128 * 1_024,
                    sha256: String(repeating: "a", count: 64)
                ),
                start: TranslationRouteStartContext(
                    hardwareModel: .wonderSwan,
                    firmware: TranslationRouteFirmware(
                        source: .installed,
                        image: TranslationArtifactDigest(
                            byteCount: 4 * 1_024,
                            sha256: String(repeating: "b", count: 64)
                        )
                    ),
                    engine: TranslationRouteEngineIdentity(
                        backend: "ares",
                        buildID: "ares-divergence-fixture"
                    )
                ),
                totalFrames: totalFrames,
                events: resolvedEvents,
                checkpoint: TranslationRouteCheckpoint(
                    frameIndex: totalFrames - 1,
                    frame: frame
                )
            )
        }

        func pairs(
            totalFrames: UInt64,
            patchedChangeAt changedIndex: UInt64? = nil
        ) -> [TranslationVisualFramePair] {
            (0..<totalFrames).map { frameIndex in
                let frameNumber = frameIndex + 1
                return TranslationVisualFramePair(
                    original: makeRouteFrame(number: frameNumber),
                    patched: makeRouteFrame(
                        number: frameNumber,
                        changedVisibleByte: frameIndex == changedIndex ? 0xee : nil
                    )
                )
            }
        }

        let events = [
            TranslationRouteEvent(frameIndex: 0, inputMask: 0),
            TranslationRouteEvent(frameIndex: 1, inputMask: EngineInput.a.rawValue),
            TranslationRouteEvent(frameIndex: 3, inputMask: 0),
        ]
        let route = try makeRoute(totalFrames: 4, events: events)
        let firstDifferenceResult = try TranslationVisualDivergenceAnalyzer.analyze(
            route: route,
            pairs: pairs(totalFrames: 4, patchedChangeAt: 2)
        )
        guard case let .firstDifference(firstDifference) = firstDifferenceResult else {
            throw CheckFailure(message: "first visual change was not reported")
        }
        try expect(firstDifference.kind == .pixels, "pixel divergence classification mismatch")
        try expect(firstDifference.frame.frameIndex == 2, "first divergence frame mismatch")
        try expect(
            firstDifference.frame.inputMask == EngineInput.a.rawValue,
            "first divergence did not preserve route input context"
        )
        try expect(
            firstDifference.previousIdenticalFrame?.frameIndex == 1,
            "previous identical frame mismatch"
        )
        try expect(
            firstDifference.difference?.differentPixelCount == 1,
            "first divergence metrics mismatch"
        )
        try expect(
            firstDifference.changedBounds == RGBFrameBounds(x: 0, y: 0, width: 1, height: 1),
            "first divergence bounds mismatch"
        )

        let noDifferenceResult = try TranslationVisualDivergenceAnalyzer.analyze(
            route: route,
            pairs: pairs(totalFrames: 4)
        )
        guard case let .noDifference(noDifference) = noDifferenceResult else {
            throw CheckFailure(message: "identical route frames reported a visual change")
        }
        try expect(noDifference.framesCompared == 4, "no-difference frame count mismatch")
        try expect(
            noDifference.lastIdenticalFrame.frameIndex == 3,
            "no-difference last frame mismatch"
        )

        let twoFrameRoute = try makeRoute(totalFrames: 2)
        let frameZeroResult = try TranslationVisualDivergenceAnalyzer.analyze(
            route: twoFrameRoute,
            pairs: pairs(totalFrames: 2, patchedChangeAt: 0)
        )
        guard case let .firstDifference(frameZeroDifference) = frameZeroResult else {
            throw CheckFailure(message: "frame-zero divergence was not reported")
        }
        try expect(
            frameZeroDifference.frame.frameIndex == 0
                && frameZeroDifference.previousIdenticalFrame == nil,
            "frame-zero divergence reported an impossible preceding frame"
        )

        func makeRailFrame(number: UInt64, railByte: UInt8) -> EngineVideoFrame {
            let width = 224
            let height = 157
            let stride = width * 4
            var pixels = Data(repeating: UInt8(truncatingIfNeeded: number), count: stride * height)
            for row in 144..<height {
                pixels.replaceSubrange(
                    (row * stride)..<((row + 1) * stride),
                    with: repeatElement(railByte, count: stride)
                )
            }
            return EngineVideoFrame(
                pixels: pixels,
                width: width,
                height: height,
                strideBytes: stride,
                isVertical: false,
                number: number
            )
        }
        let railRoute = try makeRoute(
            totalFrames: 2,
            finalFrame: makeRailFrame(number: 2, railByte: 0x11)
        )
        let railResult = try TranslationVisualDivergenceAnalyzer.analyze(
            route: railRoute,
            pairs: (1...2).map { frameNumber in
                TranslationVisualFramePair(
                    original: makeRailFrame(number: UInt64(frameNumber), railByte: 0x11),
                    patched: makeRailFrame(number: UInt64(frameNumber), railByte: 0xee)
                )
            }
        )
        guard case .noDifference = railResult else {
            throw CheckFailure(message: "hardware indicator rail created a false divergence")
        }
        let canonicalRail = try TranslationRouteCheckpoint.canonicalGameRaster(
            makeRailFrame(number: 1, railByte: 0x11)
        )
        try expect(
            canonicalRail.descriptor.width == 224
                && canonicalRail.descriptor.height == 144
                && canonicalRail.bgra8888.count == 224 * 144 * 4,
            "canonical game raster retained the hardware indicator rail"
        )

        let oneFrameRoute = try makeRoute(totalFrames: 1)
        let dimensionResult = try TranslationVisualDivergenceAnalyzer.analyze(
            route: oneFrameRoute,
            pairs: [
                TranslationVisualFramePair(
                    original: makeRouteFrame(number: 1),
                    patched: makeRouteFrame(number: 1, width: 3, height: 2)
                ),
            ]
        )
        guard case let .firstDifference(dimensionDifference) = dimensionResult else {
            throw CheckFailure(message: "dimension mismatch was not reported")
        }
        try expect(
            dimensionDifference.kind == .dimensions
                && dimensionDifference.visualization == nil
                && dimensionDifference.originalRaster.width == 2
                && dimensionDifference.patchedRaster.width == 3,
            "dimension mismatch classification was incomplete"
        )

        let original = makeRouteFrame(number: 1)
        let vertical = EngineVideoFrame(
            pixels: original.pixels,
            width: original.width,
            height: original.height,
            strideBytes: original.strideBytes,
            isVertical: true,
            number: original.number
        )
        let orientationResult = try TranslationVisualDivergenceAnalyzer.analyze(
            route: oneFrameRoute,
            pairs: [TranslationVisualFramePair(original: original, patched: vertical)]
        )
        guard case let .firstDifference(orientationDifference) = orientationResult else {
            throw CheckFailure(message: "orientation mismatch was not reported")
        }
        try expect(
            orientationDifference.kind == .orientation,
            "orientation mismatch classification mismatch"
        )

        let differentlySized = makeRouteFrame(number: 1, width: 3, height: 2)
        let verticalAndDifferentlySized = EngineVideoFrame(
            pixels: differentlySized.pixels,
            width: differentlySized.width,
            height: differentlySized.height,
            strideBytes: differentlySized.strideBytes,
            isVertical: true,
            number: differentlySized.number
        )
        let combinedMismatchResult = try TranslationVisualDivergenceAnalyzer.analyze(
            route: oneFrameRoute,
            pairs: [
                TranslationVisualFramePair(
                    original: original,
                    patched: verticalAndDifferentlySized
                ),
            ]
        )
        guard case let .firstDifference(combinedMismatch) = combinedMismatchResult else {
            throw CheckFailure(message: "combined raster mismatch was not reported")
        }
        try expect(
            combinedMismatch.kind == .dimensionsAndOrientation,
            "combined raster mismatch classification mismatch"
        )

        do {
            _ = try TranslationVisualDivergenceAnalyzer(route: route, frameLimit: 3)
            throw CheckFailure(message: "an over-limit route was accepted")
        } catch let error as TranslationVisualDivergenceError {
            try expect(
                error == .routeExceedsFrameLimit(totalFrames: 4, limit: 3),
                "route frame-cap error mismatch"
            )
        }
        do {
            _ = try TranslationVisualDivergenceAnalyzer(route: route, frameLimit: 0)
            throw CheckFailure(message: "a zero frame limit was accepted")
        } catch let error as TranslationVisualDivergenceError {
            try expect(error == .invalidFrameLimit, "zero frame-limit error mismatch")
        }

        var cancellationChecks = 0
        do {
            _ = try TranslationVisualDivergenceAnalyzer.analyze(
                route: route,
                pairs: pairs(totalFrames: 4),
                cancellationCheck: {
                    cancellationChecks += 1
                    if cancellationChecks == 2 { throw CancellationError() }
                }
            )
            throw CheckFailure(message: "a cancelled frame stream completed")
        } catch is CancellationError {}
        try expect(
            cancellationChecks == 2,
            "frame-stream cancellation was not checked before every step"
        )

        var incompleteAnalyzer = try TranslationVisualDivergenceAnalyzer(route: route)
        _ = try incompleteAnalyzer.consume(
            original: makeRouteFrame(number: 1),
            patched: makeRouteFrame(number: 1)
        )
        do {
            _ = try incompleteAnalyzer.finish()
            throw CheckFailure(message: "an incomplete frame stream produced a result")
        } catch let error as TranslationVisualDivergenceError {
            try expect(
                error == .incomplete(expectedFrames: 4, actualFrames: 1),
                "incomplete frame-stream error mismatch"
            )
        }

        var staleEndpointPairs = pairs(totalFrames: 4)
        let staleEndpoint = makeRouteFrame(number: 4, changedVisibleByte: 0xee)
        staleEndpointPairs[3] = TranslationVisualFramePair(
            original: staleEndpoint,
            patched: staleEndpoint
        )
        do {
            _ = try TranslationVisualDivergenceAnalyzer.analyze(
                route: route,
                pairs: staleEndpointPairs
            )
            throw CheckFailure(message: "a stale Original route endpoint was accepted")
        } catch let error as TranslationVisualDivergenceError {
            try expect(
                error == .originalCheckpointMismatch,
                "stale Original endpoint error mismatch"
            )
        }

        let derivedDate = Date(timeIntervalSince1970: 200)
        let prefix = try route.prefix(
            through: 2,
            originalFrame: makeRouteFrame(number: 3),
            createdAt: derivedDate
        )
        try expect(
            prefix.createdAt == derivedDate
                && prefix.totalFrames == 3
                && prefix.sourceROM == route.sourceROM
                && prefix.start == route.start
                && prefix.events == Array(events.prefix(2))
                && prefix.checkpoint?.frameIndex == 2
                && prefix.checkpoint?.matches(makeRouteFrame(number: 3)) == true
                && prefix.proofEligibility == .proofReady,
            "derived divergence route did not preserve and filter proof context"
        )
        do {
            _ = try route.prefix(
                through: route.totalFrames,
                originalFrame: makeRouteFrame(number: route.totalFrames + 1)
            )
            throw CheckFailure(message: "an out-of-range route prefix was accepted")
        } catch is TranslationLabError {}
    }

    private static func checkTranslationLabFoundations() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let toolkit = root.appendingPathComponent("toolkit", isDirectory: true)
        let bin = toolkit.appendingPathComponent("bin", isDirectory: true)
        let projectRoot = toolkit
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent("fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: projectRoot.appendingPathComponent("rom", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: projectRoot.appendingPathComponent("build", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("// fixture\n".utf8).write(to: bin.appendingPathComponent("wstrans.mjs"))
        let projectJSON = #"""
        {
          "game": {
            "title": "Translation Fixture",
            "platform": "WonderSwan Color",
            "sourceLanguage": "ja",
            "targetLanguage": "en"
          },
          "rom": {
            "original": "rom/original.wsc",
            "patched": "build/patched.wsc"
          }
        }
        """#
        try Data(projectJSON.utf8).write(to: projectRoot.appendingPathComponent("project.json"))
        let rom = makeROM(color: true)
        try rom.write(to: projectRoot.appendingPathComponent("rom/original.wsc"))
        try rom.write(to: projectRoot.appendingPathComponent("build/patched.wsc"))

        let secondProjectRoot = toolkit
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent("second-fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: secondProjectRoot, withIntermediateDirectories: true)
        let secondProjectJSON = projectJSON.replacingOccurrences(
            of: "Translation Fixture",
            with: "Another Translation Fixture"
        )
        try Data(secondProjectJSON.utf8).write(
            to: secondProjectRoot.appendingPathComponent("project.json")
        )

        let project = try TranslationProject(projectDirectory: projectRoot)
        try expect(project.title == "Translation Fixture", "translation project title mismatch")
        let patchedROMURL = try project.romURL(for: .patched)
        try expect(patchedROMURL == project.patchedROMURL, "patched ROM lookup mismatch")
        let discovered = try TranslationProject.discover(at: toolkit)
        try expect(discovered.count == 2, "toolkit project discovery count mismatch")
        try expect(
            discovered.map(\.title) == ["Another Translation Fixture", "Translation Fixture"],
            "toolkit project discovery ordering mismatch"
        )

        let workspaceStore = TranslationWorkspaceStore(
            fileURL: root.appendingPathComponent("TranslationWorkspace.json")
        )
        let workspace = TranslationWorkspaceDocument(
            projectPaths: discovered.map { $0.rootURL.path },
            selectedProjectPath: project.rootURL.path
        )
        try workspaceStore.save(workspace)
        let loadedWorkspace = try workspaceStore.load()
        try expect(loadedWorkspace == workspace, "translation workspace round trip mismatch")

        let readiness = TranslationReadiness(output: #"""
        Readiness: BLOCKED - fixture needs runtime evidence
        Strings: 558 extracted, 421 translated; table entries: 92; extractors: 3 fixed, 1 pointer
        COMPLETE Table: Character table is usable.
        PENDING ROM Text: One text region needs confirmation.
          Next: node bin/wstrans.mjs extract fixture
        BLOCKED Localization: Runtime text evidence is missing.
          Next: node bin/wstrans.mjs capture-intake fixture
        Next actions:
        - HIGH: Capture the blocked runtime screen.
          Open SwanSong and record the route.
        - MEDIUM: Review untranslated strings.
        """#)
        try expect(readiness.status == .blocked, "structured readiness status mismatch")
        try expect(readiness.metrics?.extracted == 558, "structured readiness metrics mismatch")
        try expect(readiness.metrics?.translated == 421, "structured readiness translation count mismatch")
        try expect(readiness.phases.count == 3, "structured readiness phase count mismatch")
        try expect(
            readiness.phases[1].nextCommand == "node bin/wstrans.mjs extract fixture",
            "structured readiness phase command mismatch"
        )
        try expect(readiness.nextActions.count == 2, "structured readiness action count mismatch")
        try expect(readiness.nextActions[0].priority == .high, "structured readiness priority mismatch")
        try expect(
            readiness.nextActions[0].command == "Open SwanSong and record the route.",
            "structured readiness action command mismatch"
        )

        let romHash = TranslationEvidenceStore.sha256(rom)
        let sourceROM = TranslationArtifactDigest(byteCount: rom.count, sha256: romHash)
        let firmwareBytes = Data(repeating: 0x5a, count: 4 * 1_024)
        let routeStart = TranslationRouteStartContext(
            hardwareModel: .wonderSwan,
            firmware: TranslationRouteFirmware(
                source: .installed,
                image: TranslationArtifactDigest(
                    byteCount: firmwareBytes.count,
                    sha256: TranslationEvidenceStore.sha256(firmwareBytes)
                )
            ),
            engine: TranslationRouteEngineIdentity(
                backend: "ares",
                buildID: "ares-public-fixture-swan-abi4"
            )
        )
        var recorder = TranslationRouteRecorder(
            role: .original,
            sourceROM: sourceROM,
            start: routeStart
        )
        try recorder.record(input: [], frame: makeRouteFrame(number: 1))
        try recorder.record(input: .a, frame: makeRouteFrame(number: 2))
        try recorder.record(input: .a, frame: makeRouteFrame(number: 3))
        try recorder.record(input: [], frame: makeRouteFrame(number: 4))
        let route = try recorder.finish()
        try expect(route.schema == TranslationRoute.currentSchema, "clean-boot route schema mismatch")
        try expect(
            route.proofEligibility == .proofReady,
            "a valid clean-boot route was not proof eligible"
        )
        try expect(
            route.start?.rtc == .proof
                && route.start?.rtc?.mode == .deterministic
                && route.start?.rtc?.seedUnixSeconds
                    == TranslationRouteRTCContext.proofSeedUnixSeconds
                && TranslationRouteRTCContext.proofSeedUTC == "2000-01-01T00:00:00Z",
            "proof route did not bind the documented fixed UTC RTC policy"
        )
        try expect(route.totalFrames == 4, "translation route duration mismatch")
        try expect(route.events.count == 3, "translation route did not compact repeated input")
        try expect(route.input(at: 2) == .a, "translation route replay input mismatch")
        try expect(route.targetFrameNumber == 4, "translation route checkpoint frame mismatch")
        try expect(
            route.checkpoint?.matches(makeRouteFrame(number: 4)) == true,
            "translation route checkpoint did not bind the final visible frame"
        )

        let paddingVariant = makeRouteFrame(number: 4, paddingByte: 0xff)
        let baseFingerprint = try TranslationRouteCheckpoint.fingerprint(
            makeRouteFrame(number: 4)
        )
        let paddingFingerprint = try TranslationRouteCheckpoint.fingerprint(paddingVariant)
        let changedFingerprint = try TranslationRouteCheckpoint.fingerprint(
            makeRouteFrame(number: 4, changedVisibleByte: 0xee)
        )
        try expect(
            baseFingerprint == paddingFingerprint,
            "route checkpoint fingerprint included stride padding"
        )
        try expect(
            baseFingerprint != changedFingerprint,
            "route checkpoint fingerprint ignored a visible-pixel change"
        )
        var fullFramePixels = Data(repeating: 0x22, count: 224 * 157 * 4)
        let cleanFullFrame = EngineVideoFrame(
            pixels: fullFramePixels,
            width: 224,
            height: 157,
            strideBytes: 224 * 4,
            isVertical: false,
            number: 4
        )
        fullFramePixels[(150 * 224 * 4) + 7] = 0xee
        let hardwareIconVariant = EngineVideoFrame(
            pixels: fullFramePixels,
            width: 224,
            height: 157,
            strideBytes: 224 * 4,
            isVertical: false,
            number: 4
        )
        let cleanFullFingerprint = try TranslationRouteCheckpoint.fingerprint(cleanFullFrame)
        let hardwareIconFingerprint = try TranslationRouteCheckpoint.fingerprint(
            hardwareIconVariant
        )
        try expect(
            cleanFullFingerprint == hardwareIconFingerprint,
            "route checkpoint included the mutable hardware-icon strip"
        )

        var lateRecorder = TranslationRouteRecorder(
            role: .original,
            sourceROM: sourceROM,
            start: routeStart
        )
        do {
            try lateRecorder.record(input: [], frame: makeRouteFrame(number: 100))
            throw CheckFailure(message: "a mid-session route was accepted as clean-boot proof")
        } catch is TranslationLabError {}

        do {
            _ = try TranslationRoute(
                recordedFrom: .patched,
                sourceROM: sourceROM,
                start: routeStart,
                totalFrames: route.totalFrames,
                events: route.events,
                checkpoint: try XCTUnwrap(route.checkpoint)
            )
            throw CheckFailure(message: "a Patched recording was accepted as proof")
        } catch is TranslationLabError {}
        let wrongRTCStart = TranslationRouteStartContext(
            hardwareModel: routeStart.hardwareModel,
            firmware: routeStart.firmware,
            engine: routeStart.engine,
            rtc: TranslationRouteRTCContext(
                mode: .deterministic,
                seedUnixSeconds: TranslationRouteRTCContext.proofSeedUnixSeconds + 1
            )
        )
        do {
            _ = try TranslationRoute(
                recordedFrom: .original,
                sourceROM: sourceROM,
                start: wrongRTCStart,
                totalFrames: route.totalFrames,
                events: route.events,
                checkpoint: try XCTUnwrap(route.checkpoint)
            )
            throw CheckFailure(message: "a route with a different RTC seed was accepted as proof")
        } catch is TranslationLabError {}

        let evidenceStore = TranslationEvidenceStore()
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let unsafeAnalysis = projectRoot.appendingPathComponent("analysis", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: unsafeAnalysis, withDestinationURL: outside)
        do {
            _ = try evidenceStore.saveRoute(route, project: project)
            throw CheckFailure(message: "translation evidence followed an unsafe analysis symlink")
        } catch is TranslationLabError {}
        try FileManager.default.removeItem(at: unsafeAnalysis)

        let routeURL = try evidenceStore.saveRoute(route, project: project)
        let latest = try XCTUnwrap(evidenceStore.latestRoute(project: project))
        try expect(
            latest.0.standardizedFileURL.path == routeURL.standardizedFileURL.path,
            "latest translation route URL mismatch"
        )
        try expect(
            latest.1.schema == route.schema
                && latest.1.recordedFrom == route.recordedFrom
                && latest.1.sourceROM == route.sourceROM
                && latest.1.start == route.start
                && latest.1.totalFrames == route.totalFrames
                && latest.1.events == route.events
                && latest.1.checkpoint == route.checkpoint,
            "latest translation route payload mismatch"
        )
        let newerRoute = try TranslationRoute(
            createdAt: route.createdAt.addingTimeInterval(10),
            recordedFrom: .original,
            sourceROM: sourceROM,
            start: routeStart,
            totalFrames: route.totalFrames,
            events: route.events,
            checkpoint: try XCTUnwrap(route.checkpoint)
        )
        let newerRouteURL = try evidenceStore.saveRoute(newerRoute, project: project)

        var invalidV3Object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: routeURL)) as? [String: Any]
        )
        invalidV3Object.removeValue(forKey: "checkpoint")
        let invalidV3Data = try JSONSerialization.data(
            withJSONObject: invalidV3Object,
            options: [.prettyPrinted, .sortedKeys]
        )
        let invalidV3URL = routeURL.deletingLastPathComponent()
            .appendingPathComponent("route-invalid-v3.json")
        try invalidV3Data.write(to: invalidV3URL, options: [.atomic])
        let routesWithInvalidV3 = try evidenceStore.listRoutes(project: project)
        let invalidV3Summary = try XCTUnwrap(
            routesWithInvalidV3.first {
                $0.fileURL.lastPathComponent == invalidV3URL.lastPathComponent
            }
        )
        guard case let .invalidV3(invalidV3Issue) = invalidV3Summary.route.proofEligibility else {
            throw CheckFailure(message: "an invalid v3 route was not kept as blocked history")
        }
        try expect(
            invalidV3Issue.contains("checkpoint"),
            "invalid v3 route did not explain its blocked proof status"
        )
        do {
            try invalidV3Summary.route.validateForProof()
            throw CheckFailure(message: "an invalid v3 route was accepted for deterministic proof")
        } catch is TranslationLabError {}
        let invalidV3DataAfterIndexing = try Data(contentsOf: invalidV3URL)
        try expect(
            invalidV3DataAfterIndexing == invalidV3Data,
            "indexing an invalid v3 route rewrote its immutable bytes"
        )
        try FileManager.default.removeItem(at: invalidV3URL)

        var missingRTCV3Object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: routeURL)) as? [String: Any]
        )
        var missingRTCV3Start = try XCTUnwrap(
            missingRTCV3Object["start"] as? [String: Any]
        )
        missingRTCV3Start.removeValue(forKey: "rtc")
        missingRTCV3Object["start"] = missingRTCV3Start
        let missingRTCV3Data = try JSONSerialization.data(
            withJSONObject: missingRTCV3Object,
            options: [.prettyPrinted, .sortedKeys]
        )
        let missingRTCV3URL = routeURL.deletingLastPathComponent()
            .appendingPathComponent("route-missing-rtc-v3.json")
        try missingRTCV3Data.write(to: missingRTCV3URL, options: [.atomic])
        let routesWithMissingRTCV3 = try evidenceStore.listRoutes(project: project)
        let missingRTCV3Summary = try XCTUnwrap(
            routesWithMissingRTCV3.first {
                $0.fileURL.lastPathComponent == missingRTCV3URL.lastPathComponent
            }
        )
        guard case let .invalidV3(missingRTCV3Issue) = missingRTCV3Summary.route.proofEligibility else {
            throw CheckFailure(message: "a v3 route without RTC context was not blocked")
        }
        try expect(
            missingRTCV3Issue.contains("RTC mode and seed"),
            "a v3 route without RTC context did not explain the proof failure"
        )
        try FileManager.default.removeItem(at: missingRTCV3URL)

        var v2Object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: routeURL)) as? [String: Any]
        )
        v2Object["schema"] = TranslationRoute.rtcUnboundSchema
        var v2Start = try XCTUnwrap(v2Object["start"] as? [String: Any])
        v2Start.removeValue(forKey: "rtc")
        v2Object["start"] = v2Start
        let v2Data = try JSONSerialization.data(
            withJSONObject: v2Object,
            options: [.prettyPrinted, .sortedKeys]
        )
        let v2URL = routeURL.deletingLastPathComponent()
            .appendingPathComponent("route-rtc-unbound-v2.json")
        try v2Data.write(to: v2URL, options: [.atomic])
        let routesWithV2 = try evidenceStore.listRoutes(project: project)
        let v2Summary = try XCTUnwrap(
            routesWithV2.first { $0.fileURL.lastPathComponent == v2URL.lastPathComponent }
        )
        try expect(
            v2Summary.route.proofEligibility == .rtcStartUnknown
                && v2Summary.route.start?.rtc == nil
                && v2Summary.route.proofEligibility.issue?.contains("RTC mode and seed") == true
                && v2Summary.route.proofEligibility.issue?.contains("946684800") == true,
            "version 2 route did not remain visible with the precise RTC migration status"
        )
        do {
            try v2Summary.route.validateForProof()
            throw CheckFailure(message: "an RTC-unbound v2 route was accepted for proof")
        } catch is TranslationLabError {}
        _ = try evidenceStore.saveTestCase(
            name: "RTC migration fixture",
            note: "Must be re-recorded with the fixed UTC seed.",
            route: v2Summary,
            project: project
        )
        let v2DataAfterNaming = try Data(contentsOf: v2URL)
        try expect(
            v2DataAfterNaming == v2Data,
            "naming a version 2 route rewrote its immutable route bytes"
        )

        var invalidV2Object = v2Object
        invalidV2Object.removeValue(forKey: "checkpoint")
        let invalidV2Data = try JSONSerialization.data(
            withJSONObject: invalidV2Object,
            options: [.prettyPrinted, .sortedKeys]
        )
        let invalidV2URL = routeURL.deletingLastPathComponent()
            .appendingPathComponent("route-invalid-v2.json")
        try invalidV2Data.write(to: invalidV2URL, options: [.atomic])
        let routesWithInvalidV2 = try evidenceStore.listRoutes(project: project)
        let invalidV2Summary = try XCTUnwrap(
            routesWithInvalidV2.first {
                $0.fileURL.lastPathComponent == invalidV2URL.lastPathComponent
            }
        )
        guard case let .invalidV2(invalidV2Issue) = invalidV2Summary.route.proofEligibility else {
            throw CheckFailure(message: "an invalid v2 route was not kept as blocked history")
        }
        try expect(
            invalidV2Issue.contains("checkpoint"),
            "invalid v2 route did not explain its blocked proof status"
        )
        try FileManager.default.removeItem(at: invalidV2URL)
        try FileManager.default.removeItem(at: v2URL)

        let legacyRouteData = Data(#"""
        {
          "schema": "swan-song-input-route-v1",
          "createdAt": "2025-01-01T00:00:00Z",
          "recordedFrom": "original",
          "sourceROMSHA256": "\#(romHash)",
          "totalFrames": 4,
          "events": [
            {"frameIndex": 0, "inputMask": 0},
            {"frameIndex": 1, "inputMask": 512},
            {"frameIndex": 3, "inputMask": 0}
          ]
        }
        """#.utf8)
        let legacyURL = routeURL.deletingLastPathComponent()
            .appendingPathComponent("route-legacy-v1.json")
        try legacyRouteData.write(to: legacyURL, options: [.atomic])
        let routesWithLegacy = try evidenceStore.listRoutes(project: project)
        let legacySummary = try XCTUnwrap(
            routesWithLegacy.first { $0.fileURL.lastPathComponent == legacyURL.lastPathComponent }
        )
        try expect(
            legacySummary.route.proofEligibility == .legacyStartUnknown,
            "legacy route was not kept visible as non-proof history"
        )
        do {
            try legacySummary.route.validateForProof()
            throw CheckFailure(message: "legacy route was accepted for deterministic proof")
        } catch is TranslationLabError {}
        _ = try evidenceStore.saveTestCase(
            name: "Legacy route fixture",
            note: "Must be re-recorded from clean boot.",
            route: legacySummary,
            project: project
        )
        let legacyRouteDataAfterNaming = try Data(contentsOf: legacyURL)
        try expect(
            legacyRouteDataAfterNaming == legacyRouteData,
            "naming a legacy route rewrote its immutable route bytes"
        )
        try FileManager.default.removeItem(at: legacyURL)

        let routes = try evidenceStore.listRoutes(project: project)
        try expect(routes.count == 2, "translation route history count mismatch")
        try expect(
            routes.first?.fileURL.standardizedFileURL.path == newerRouteURL.standardizedFileURL.path,
            "translation route history ordering mismatch"
        )
        let indexedRoute = try XCTUnwrap(routes.first)
        let immutableRouteData = try Data(contentsOf: indexedRoute.fileURL)
        let testCaseUpdatedAt = Date(timeIntervalSince1970: 1_799_000_000)
        let testCase = try evidenceStore.saveTestCase(
            name: "  Chapter 2 shop overflow  ",
            note: "  Check the final price glyph and the right border.  ",
            route: indexedRoute,
            project: project,
            updatedAt: testCaseUpdatedAt
        )
        try expect(testCase.name == "Chapter 2 shop overflow", "test-case name was not normalized")
        try expect(
            testCase.note == "Check the final price glyph and the right border.",
            "test-case note was not normalized"
        )
        let routeDataAfterTestCaseSave = try Data(contentsOf: indexedRoute.fileURL)
        try expect(
            routeDataAfterTestCaseSave == immutableRouteData,
            "saving test-case metadata changed the immutable route"
        )
        let namedRoutes = try evidenceStore.listRoutes(project: project)
        let namedRoute = try XCTUnwrap(namedRoutes.first { $0.id == indexedRoute.id })
        try expect(namedRoute.testCase == testCase, "route test-case metadata did not round trip")
        try expect(namedRoute.testCaseIssue == nil, "valid route test-case metadata reported an issue")
        try expect(
            namedRoute.routeDigest == indexedRoute.routeDigest,
            "route digest changed after test-case metadata was saved"
        )
        let suiteStartedAt = Date(timeIntervalSince1970: 1_799_100_000)
        let suiteCompletedAt = suiteStartedAt.addingTimeInterval(12)
        let suiteDifference = try FrameDifferential.compareRGB888(
            expected: Data([0, 0, 0, 12, 12, 12]),
            actual: Data([0, 0, 0, 18, 12, 12])
        )
        let suiteRun = TranslationSuiteRun(
            projectTitle: project.title,
            startedAt: suiteStartedAt,
            completedAt: suiteCompletedAt,
            cases: [
                TranslationSuiteCaseResult(
                    route: namedRoute.routeDigest,
                    name: testCase.name,
                    originalEvidenceName: "capture-original-fixture",
                    patchedEvidenceName: "capture-patched-fixture",
                    originalFrameNumber: 44,
                    patchedFrameNumber: 44,
                    difference: suiteDifference,
                    changedBounds: RGBFrameBounds(x: 1, y: 0, width: 1, height: 1),
                    baselineComparison: TranslationSuiteBaselineComparison(
                        evidenceName: "capture-approved-baseline",
                        difference: suiteDifference,
                        changedBounds: RGBFrameBounds(x: 1, y: 0, width: 1, height: 1)
                    )
                ),
                TranslationSuiteCaseResult(
                    route: routes[1].routeDigest,
                    name: "Opening screen",
                    originalEvidenceName: "capture-original-opening",
                    patchedEvidenceName: "capture-patched-opening",
                    originalFrameNumber: 4,
                    patchedFrameNumber: 4,
                    difference: try FrameDifferential.compareRGB888(
                        expected: Data([0, 0, 0]),
                        actual: Data([0, 0, 0])
                    ),
                    changedBounds: nil
                ),
            ]
        )
        let suiteURL = try evidenceStore.saveSuiteRun(suiteRun, project: project)
        let suiteRuns = try evidenceStore.listSuiteRuns(project: project)
        try expect(
            suiteRuns.count == 1,
            "translation suite report was not indexed"
        )
        try expect(
            suiteRuns[0].fileURL.standardizedFileURL == suiteURL.standardizedFileURL,
            "translation suite report URL changed during indexing"
        )
        try expect(
            suiteRuns[0].run == suiteRun,
            "translation suite report payload did not round trip"
        )
        try expect(
            suiteRuns[0].run.changedCaseCount == 1
                && suiteRuns[0].run.identicalCaseCount == 1,
            "translation suite visual summary mismatch"
        )
        try expect(
            suiteRuns[0].run.changedFromBaselineCount == 1
                && suiteRuns[0].run.stableAgainstBaselineCount == 0
                && suiteRuns[0].run.unbaselinedCaseCount == 1,
            "translation suite baseline summary mismatch"
        )
        let duplicateRouteSuite = TranslationSuiteRun(
            projectTitle: project.title,
            startedAt: suiteStartedAt,
            completedAt: suiteCompletedAt,
            cases: [suiteRun.cases[0], suiteRun.cases[0]]
        )
        do {
            _ = try evidenceStore.saveSuiteRun(duplicateRouteSuite, project: project)
            throw CheckFailure(message: "duplicate route was accepted in a suite report")
        } catch is TranslationLabError {}
        let validSuiteData = try Data(contentsOf: suiteURL)
        let invalidSuiteText = String(decoding: validSuiteData, as: UTF8.self)
            .replacingOccurrences(
                of: "Translation Fixture",
                with: "Different Project"
        )
        try Data(invalidSuiteText.utf8).write(to: suiteURL, options: [.atomic])
        let corruptedSuiteRuns = try evidenceStore.listSuiteRuns(project: project)
        try expect(
            corruptedSuiteRuns.isEmpty,
            "project-mismatched suite report was trusted"
        )
        try validSuiteData.write(to: suiteURL, options: [.atomic])
        do {
            _ = try evidenceStore.saveTestCase(
                name: "   ",
                note: "",
                route: namedRoute,
                project: project
            )
            throw CheckFailure(message: "empty route test-case name was accepted")
        } catch is TranslationLabError {}
        let testCaseURL = projectRoot
            .appendingPathComponent("analysis/swan-song-lab/test-cases", isDirectory: true)
            .appendingPathComponent("case-\(namedRoute.routeDigest.sha256).json")
        let validTestCaseText = try String(contentsOf: testCaseURL, encoding: .utf8)
        let corruptTestCaseText = validTestCaseText.replacingOccurrences(
            of: namedRoute.routeDigest.sha256,
            with: String(repeating: "0", count: 64)
        )
        try Data(corruptTestCaseText.utf8).write(to: testCaseURL, options: [.atomic])
        let routesWithCorruptTestCase = try evidenceStore.listRoutes(project: project)
        let routeWithCorruptTestCase = try XCTUnwrap(
            routesWithCorruptTestCase.first { $0.id == namedRoute.id }
        )
        try expect(
            routeWithCorruptTestCase.testCase == nil
                && routeWithCorruptTestCase.testCaseIssue != nil,
            "digest-mismatched test-case metadata was trusted"
        )
        _ = try evidenceStore.saveTestCase(
            name: testCase.name,
            note: testCase.note,
            route: routeWithCorruptTestCase,
            project: project,
            updatedAt: testCaseUpdatedAt
        )
        let artifact = try evidenceStore.capture(
            TranslationEvidenceInput(
                project: project,
                role: .patched,
                romURL: project.patchedROMURL,
                romFooterChecksum: 0x1234,
                backend: "ares",
                frameNumber: 44,
                framePNG: Data([0x89, 0x50, 0x4e, 0x47]),
                gameFrameSHA256: try XCTUnwrap(route.checkpoint?.sha256),
                state: Data(repeating: 0x51, count: 32),
                internalRAM: Data(repeating: 0x62, count: 64 * 1024),
                route: route
            )
        )
        try expect(
            FileManager.default.fileExists(atPath: artifact.manifestURL.path),
            "translation evidence manifest was not committed"
        )
        try expect(
            FileManager.default.fileExists(atPath: artifact.internalRAMURL.path),
            "translation evidence RAM was not committed"
        )
        var evidence = try evidenceStore.listEvidence(project: project)
        try expect(evidence.count == 1 && evidence[0].isIntact, "intact evidence was not indexed")
        let reviewedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let approvedReview = try evidenceStore.saveReview(
            status: .approved,
            note: "Approved visual baseline.",
            evidence: evidence[0],
            project: project,
            updatedAt: reviewedAt.addingTimeInterval(-10)
        )
        evidence = try evidenceStore.listEvidence(project: project)
        try expect(
            evidence[0].review == approvedReview,
            "approved evidence review did not round trip"
        )
        let baselineRoute = try XCTUnwrap(
            try evidenceStore.listRoutes(project: project).first {
                $0.routeDigest == evidence[0].manifest?.route
            }
        )
        let baselineCreatedAt = reviewedAt.addingTimeInterval(-5)
        let baseline = try evidenceStore.saveBaseline(
            evidence: evidence[0],
            route: baselineRoute,
            project: project,
            createdAt: baselineCreatedAt
        )
        var baselines = try evidenceStore.listBaselines(project: project)
        try expect(
            baselines.count == 1
                && baselines[0].isIntact
                && baselines[0].baseline == baseline
                && baselines[0].evidence?.id == evidence[0].id,
            "approved route baseline did not round trip"
        )
        let review = try evidenceStore.saveReview(
            status: .needsWork,
            note: "  English glyph clips the right border.  ",
            evidence: evidence[0],
            project: project,
            updatedAt: reviewedAt
        )
        try expect(review.note == "English glyph clips the right border.", "review note was not normalized")
        evidence = try evidenceStore.listEvidence(project: project)
        try expect(evidence[0].review == review, "evidence review did not round trip")
        try expect(evidence[0].reviewIssue == nil, "valid evidence review reported an issue")
        baselines = try evidenceStore.listBaselines(project: project)
        try expect(
            baselines.count == 1
                && !baselines[0].isIntact
                && baselines[0].integrityIssue != nil,
            "baseline remained trusted after its evidence lost Approved status"
        )
        do {
            _ = try evidenceStore.saveBaseline(
                evidence: evidence[0],
                route: baselineRoute,
                project: project
            )
            throw CheckFailure(message: "Needs Work evidence was accepted as a baseline")
        } catch is TranslationLabError {}
        try evidenceStore.removeBaseline(route: baselineRoute, project: project)
        baselines = try evidenceStore.listBaselines(project: project)
        try expect(
            baselines.isEmpty,
            "route baseline removal failed"
        )

        let diagnosticURL = root.appendingPathComponent("fixture.swsdiag", isDirectory: true)
        let diagnostic = try evidenceStore.exportDiagnostic(
            evidence: evidence[0],
            project: project,
            to: diagnosticURL,
            createdAt: reviewedAt
        )
        let diagnosticFiles = try FileManager.default.contentsOfDirectory(
            at: diagnostic.packageURL,
            includingPropertiesForKeys: nil
        )
        try expect(
            Set(diagnosticFiles.map(\.lastPathComponent)) == [
                "README.txt", "diagnostic.json", "frame.png", "route.json",
            ],
            "source-free diagnostic exported an unexpected artifact"
        )
        let diagnosticDecoder = JSONDecoder()
        diagnosticDecoder.dateDecodingStrategy = .iso8601
        let diagnosticManifest = try diagnosticDecoder.decode(
            TranslationDiagnosticManifest.self,
            from: Data(contentsOf: diagnostic.manifestURL)
        )
        try expect(
            diagnosticManifest.schema == "swan-song-source-free-diagnostic-v1",
            "diagnostic schema mismatch"
        )
        try expect(diagnosticManifest.review == review, "diagnostic review mismatch")
        try expect(
            diagnosticManifest.omittedArtifacts.contains("internal RAM"),
            "diagnostic did not declare its RAM omission"
        )
        try expect(
            !diagnosticFiles.contains(where: {
                ["runtime.state", "ram.bin", "original.wsc", "patched.wsc"].contains($0.lastPathComponent)
            }),
            "source-free diagnostic leaked a restricted artifact"
        )
        do {
            _ = try evidenceStore.exportDiagnostic(
                evidence: evidence[0],
                project: project,
                to: diagnosticURL
            )
            throw CheckFailure(message: "diagnostic exporter replaced an existing package")
        } catch TranslationEvidenceReviewError.destinationExists {}

        let routeDigest = try XCTUnwrap(evidence[0].manifest?.route)
        var original16 = Data(repeating: 0x20, count: 16 * 1_024)
        var patched16 = original16
        patched16[0] = 0x41
        patched16[1] = 0x42
        patched16[16] = 0x43
        patched16[patched16.count - 1] = 0x44
        let pureRAMComparison = try TranslationRAMComparison(
            originalEvidenceName: "original-16k",
            patchedEvidenceName: "patched-16k",
            route: routeDigest,
            originalFrameNumber: 44,
            patchedFrameNumber: 44,
            original: original16,
            patched: patched16
        )
        try expect(
            pureRAMComparison.changedByteCount == 4
                && pureRAMComparison.changeRanges == [
                    TranslationRAMChangeRange(startOffset: 0, length: 2),
                    TranslationRAMChangeRange(startOffset: 16, length: 1),
                    TranslationRAMChangeRange(startOffset: patched16.count - 1, length: 1),
                ],
            "checkpoint RAM ranges did not coalesce adjacent changes"
        )
        try expect(
            pureRAMComparison.changedRowOffsets == [0, 16, patched16.count - 16],
            "checkpoint RAM changed-row indexing lost a boundary"
        )
        try expect(
            pureRAMComparison.row(at: patched16.count - 1)?.patched.last == 0x44,
            "checkpoint RAM final row did not preserve its last byte"
        )
        let parsedHexPattern = try TranslationRAMComparison.hexPattern("41 42")
        try expect(
            parsedHexPattern == Data([0x41, 0x42]),
            "checkpoint RAM hex query parsing mismatch"
        )
        let boundaryHits = try pureRAMComparison.search(Data([0x41, 0x42]))
        try expect(
            boundaryHits == [TranslationRAMSearchHit(role: .patched, offset: 0)],
            "checkpoint RAM search did not bind the role and boundary offset"
        )
        let finalAddress = try pureRAMComparison.validatedAddress("0x3fff")
        try expect(
            finalAddress == patched16.count - 1,
            "checkpoint RAM address validation rejected the last byte"
        )
        do {
            _ = try TranslationRAMComparison(
                originalEvidenceName: "original",
                patchedEvidenceName: "patched",
                route: routeDigest,
                originalFrameNumber: 44,
                patchedFrameNumber: 45,
                original: original16,
                patched: patched16
            )
            throw CheckFailure(message: "checkpoint RAM accepted mismatched frames")
        } catch is TranslationRAMInspectionError {}
        do {
            _ = try TranslationRAMComparison(
                originalEvidenceName: "original",
                patchedEvidenceName: "patched",
                route: routeDigest,
                originalFrameNumber: 44,
                patchedFrameNumber: 44,
                original: Data(repeating: 0, count: 1_024),
                patched: Data(repeating: 0, count: 1_024)
            )
            throw CheckFailure(message: "checkpoint RAM accepted an unsupported RAM size")
        } catch is TranslationRAMInspectionError {}
        let identical64 = Data(repeating: 0x5A, count: 64 * 1_024)
        let identicalRAMComparison = try TranslationRAMComparison(
            originalEvidenceName: "original-64k",
            patchedEvidenceName: "patched-64k",
            route: routeDigest,
            originalFrameNumber: 44,
            patchedFrameNumber: 44,
            original: identical64,
            patched: identical64
        )
        try expect(
            identicalRAMComparison.changedByteCount == 0
                && identicalRAMComparison.changeRanges.isEmpty
                && identicalRAMComparison.changedRowOffsets.isEmpty,
            "byte-identical checkpoint RAM reported false changes"
        )
        do {
            _ = try TranslationRAMComparison(
                originalEvidenceName: "original",
                patchedEvidenceName: "patched",
                route: routeDigest,
                originalFrameNumber: 44,
                patchedFrameNumber: 44,
                original: Data(repeating: 0, count: 16 * 1_024),
                patched: Data(repeating: 0, count: 64 * 1_024)
            )
            throw CheckFailure(message: "checkpoint RAM accepted different snapshot sizes")
        } catch is TranslationRAMInspectionError {}
        do {
            _ = try pureRAMComparison.validatedAddress("0x4000")
            throw CheckFailure(message: "checkpoint RAM accepted an out-of-range address")
        } catch is TranslationRAMInspectionError {}

        original16.removeAll(keepingCapacity: false)
        var originalRAM = Data(repeating: 0x62, count: 64 * 1_024)
        originalRAM[0] = 0x10
        originalRAM[1] = 0x11
        originalRAM[32] = 0x12
        let originalArtifact = try evidenceStore.capture(
            TranslationEvidenceInput(
                project: project,
                role: .original,
                romURL: project.originalROMURL,
                romFooterChecksum: 0x1234,
                backend: "ares",
                frameNumber: 44,
                framePNG: Data([0x89, 0x50, 0x4e, 0x47]),
                gameFrameSHA256: try XCTUnwrap(route.checkpoint?.sha256),
                state: Data(repeating: 0x51, count: 32),
                internalRAM: originalRAM,
                route: route
            )
        )
        let pairedEvidence = try evidenceStore.listEvidence(project: project)
        let originalEvidence = try XCTUnwrap(
            pairedEvidence.first { $0.manifest?.romRole == .original }
        )
        let patchedEvidence = try XCTUnwrap(
            pairedEvidence.first { $0.manifest?.romRole == .patched }
        )
        let storedRAMComparison = try evidenceStore.compareInternalRAM(
            patchedEvidence,
            originalEvidence,
            project: project
        )
        try expect(
            storedRAMComparison.byteCount == 64 * 1_024
                && storedRAMComparison.changedByteCount == 3
                && storedRAMComparison.changeRanges.count == 2
                && storedRAMComparison.originalEvidenceName == originalArtifact.name,
            "evidence-backed checkpoint RAM comparison mismatch"
        )
        try Data(repeating: 0x99, count: 64 * 1_024).write(
            to: originalArtifact.internalRAMURL,
            options: [.atomic]
        )
        do {
            _ = try evidenceStore.loadInternalRAM(for: originalEvidence, project: project)
            throw CheckFailure(message: "checkpoint RAM trusted bytes changed after indexing")
        } catch is TranslationRAMInspectionError {}
        try FileManager.default.removeItem(at: originalArtifact.internalRAMURL)
        let symlinkTarget = root.appendingPathComponent("ram-symlink-target.bin")
        try originalRAM.write(to: symlinkTarget, options: [.atomic])
        try FileManager.default.createSymbolicLink(
            at: originalArtifact.internalRAMURL,
            withDestinationURL: symlinkTarget
        )
        do {
            _ = try evidenceStore.loadInternalRAM(for: originalEvidence, project: project)
            throw CheckFailure(message: "checkpoint RAM accepted a symbolic link")
        } catch is TranslationLabError {}
        try FileManager.default.removeItem(at: originalArtifact.directoryURL)

        try Data([0x00]).write(to: artifact.frameURL, options: [.atomic])
        evidence = try evidenceStore.listEvidence(project: project)
        try expect(
            evidence.count == 1 && !evidence[0].isIntact && evidence[0].integrityIssue != nil,
            "altered evidence was not reported as damaged"
        )
        do {
            _ = try evidenceStore.exportDiagnostic(
                evidence: evidence[0],
                project: project,
                to: root.appendingPathComponent("damaged.swsdiag", isDirectory: true)
            )
            throw CheckFailure(message: "damaged evidence was exported")
        } catch is TranslationEvidenceReviewError {}
    }

    private static func checkTranslationRAMTextScanner() throws {
        var original = Data(repeating: 0x01, count: 16 * 1_024)
        var patched = original

        func write(_ value: Data, at offset: Int, to snapshot: inout Data) {
            snapshot.replaceSubrange(offset..<(offset + value.count), with: value)
        }

        write(Data("DIALOGUE JP\0".utf8), at: 0x20, to: &original)
        write(Data("DIALOGUE EN\0".utf8), at: 0x20, to: &patched)
        let shiftJIS = try XCTUnwrap("メニュー".data(using: .shiftJIS))
        write(shiftJIS + Data([0xff]), at: 0x100, to: &original)
        write(shiftJIS + Data([0xff]), at: 0x100, to: &patched)
        write(Data("OLD TEXT\0".utf8), at: 0x180, to: &original)
        write(Data("NEW TEXT\0".utf8), at: 0x200, to: &patched)
        write(Data("      \0".utf8), at: 0x300, to: &original)
        write(Data("UNTERMINATED".utf8), at: 0x400, to: &patched)

        let originalScan = try TranslationRAMTextScanner.scan(original)
        let patchedScan = try TranslationRAMTextScanner.scan(patched)
        try expect(
            originalScan.candidates.map(\.offset) == [0x20, 0x100, 0x180],
            "RAM text scan reported false Original candidates"
        )
        try expect(
            patchedScan.candidates.map(\.offset) == [0x20, 0x100, 0x200],
            "RAM text scan reported false Patched candidates"
        )
        let decodedShiftJIS = try XCTUnwrap(
            originalScan.candidates.first(where: { $0.offset == 0x100 })
        )
        try expect(
            decodedShiftJIS.text == "メニュー"
                && decodedShiftJIS.encoding == .shiftJIS
                && decodedShiftJIS.terminator == .ff
                && decodedShiftJIS.byteDigest.sha256
                    == TranslationEvidenceStore.sha256(shiftJIS),
            "RAM text scan did not decode and bind Shift-JIS bytes"
        )

        let route = TranslationArtifactDigest(
            byteCount: 32,
            sha256: String(repeating: "a", count: 64)
        )
        let comparison = try TranslationRAMComparison(
            originalEvidenceName: "original-text",
            patchedEvidenceName: "patched-text",
            route: route,
            originalFrameNumber: 120,
            patchedFrameNumber: 120,
            original: original,
            patched: patched
        )
        let report = try TranslationRAMTextScanner.report(for: comparison)
        try expect(
            report.changes.map(\.offset) == [0x20, 0x180, 0x200]
                && report.changes.map(\.kind) == [.modified, .removed, .added],
            "RAM text report did not classify same-address text changes"
        )
        let reportJSON = try report.jsonData()
        let repeatedReportJSON = try report.jsonData()
        try expect(
            reportJSON == repeatedReportJSON
                && String(decoding: reportJSON, as: UTF8.self).contains(
                    TranslationRAMTextReport.privateAnalysisNotice
                )
                && String(decoding: reportJSON, as: UTF8.self).contains("DIALOGUE EN"),
            "RAM text report JSON was not deterministic or self-identifying"
        )

        var bounded = Data(repeating: 0x01, count: 128)
        write(Data("TEXT ONE\0".utf8), at: 0, to: &bounded)
        write(Data("TEXT TWO\0".utf8), at: 24, to: &bounded)
        write(Data("TEXT THREE\0".utf8), at: 48, to: &bounded)
        let boundedScan = try TranslationRAMTextScanner.scan(
            bounded,
            configuration: TranslationRAMTextScanConfiguration(
                maximumCandidateCount: 2,
                maximumInputByteCount: bounded.count
            )
        )
        try expect(
            boundedScan.candidates.count == 2 && boundedScan.wasTruncated,
            "RAM text scan did not enforce its candidate bound"
        )
        do {
            _ = try TranslationRAMTextScanner.scan(
                Data(repeating: 0, count: 5),
                configuration: TranslationRAMTextScanConfiguration(maximumInputByteCount: 4)
            )
            throw CheckFailure(message: "RAM text scan accepted an oversized input")
        } catch is TranslationRAMTextScanError {}
        do {
            _ = try TranslationRAMTextScanner.scan(
                Data(),
                configuration: TranslationRAMTextScanConfiguration(minimumCharacterCount: 0)
            )
            throw CheckFailure(message: "RAM text scan accepted invalid limits")
        } catch is TranslationRAMTextScanError {}
    }

    private static func checkTranslationRAMPointerScanner() throws {
        var original = Data(repeating: 0x01, count: 16 * 1_024)
        var patched = original

        func write(_ value: Data, at offset: Int, to snapshot: inout Data) {
            snapshot.replaceSubrange(offset..<(offset + value.count), with: value)
        }

        func writePointer(_ target: Int, at offset: Int, to snapshot: inout Data) {
            snapshot[offset] = UInt8(target & 0xff)
            snapshot[offset + 1] = UInt8((target >> 8) & 0xff)
        }

        write(Data("JAPANESE TEXT\0".utf8), at: 0x0200, to: &original)
        write(Data("ENGLISH TEXT\0".utf8), at: 0x0200, to: &patched)
        write(Data("OLD BUFFER\0".utf8), at: 0x0300, to: &original)
        write(Data("NEW BUFFER\0".utf8), at: 0x0400, to: &patched)

        writePointer(0x0200, at: 0x0010, to: &original)
        writePointer(0x0200, at: 0x0010, to: &patched)
        writePointer(0x0200, at: 0x0020, to: &original)
        writePointer(0x0200, at: 0x0030, to: &patched)
        writePointer(0x0300, at: 0x0040, to: &original)
        writePointer(0x0400, at: 0x0050, to: &patched)

        let route = TranslationArtifactDigest(
            byteCount: 32,
            sha256: String(repeating: "b", count: 64)
        )
        let comparison = try TranslationRAMComparison(
            originalEvidenceName: "original-pointers",
            patchedEvidenceName: "patched-pointers",
            route: route,
            originalFrameNumber: 220,
            patchedFrameNumber: 220,
            original: original,
            patched: patched
        )
        let textReport = try TranslationRAMTextScanner.report(for: comparison)
        let report = try TranslationRAMPointerScanner.report(
            for: comparison,
            textReport: textReport
        )
        try expect(
            report.candidateTargetCount == 3
                && report.analyzedTargetCount == 3
                && !report.wasTruncated
                && report.originalReferenceCount == 3
                && report.patchedReferenceCount == 3,
            "RAM pointer report counts or bounds mismatch"
        )

        let modifiedLead = try XCTUnwrap(
            report.leads.first { $0.targetOffset == 0x0200 }
        )
        try expect(
            modifiedLead.textChangeKind == .modified
                && modifiedLead.originalReferenceOffsets == [0x0010, 0x0020]
                && modifiedLead.patchedReferenceOffsets == [0x0010, 0x0030]
                && modifiedLead.stableReferenceOffsets == [0x0010]
                && modifiedLead.removedReferenceOffsets == [0x0020]
                && modifiedLead.addedReferenceOffsets == [0x0030],
            "RAM pointer report did not classify stable, removed, and added sites"
        )
        let removedLead = try XCTUnwrap(
            report.leads.first { $0.targetOffset == 0x0300 }
        )
        let addedLead = try XCTUnwrap(
            report.leads.first { $0.targetOffset == 0x0400 }
        )
        try expect(
            removedLead.textChangeKind == .removed
                && removedLead.originalReferenceOffsets == [0x0040]
                && removedLead.patchedReferenceOffsets.isEmpty
                && addedLead.textChangeKind == .added
                && addedLead.originalReferenceOffsets.isEmpty
                && addedLead.patchedReferenceOffsets == [0x0050],
            "RAM pointer report lost added or removed text-buffer references"
        )

        let reportJSON = try report.jsonData()
        let repeatedReportJSON = try report.jsonData()
        try expect(
            reportJSON == repeatedReportJSON
                && String(decoding: reportJSON, as: UTF8.self).contains(
                    TranslationRAMPointerReport.privateAnalysisNotice
                ),
            "RAM pointer report JSON was not deterministic or private-labeled"
        )

        let targetBounded = try TranslationRAMPointerScanner.report(
            for: comparison,
            textReport: textReport,
            configuration: TranslationRAMPointerScanConfiguration(maximumTargetCount: 1)
        )
        try expect(
            targetBounded.analyzedTargetCount == 1
                && targetBounded.leads.map(\.targetOffset) == [0x0200]
                && targetBounded.wasTruncated,
            "RAM pointer scan did not enforce its target bound"
        )
        let referenceBounded = try TranslationRAMPointerScanner.report(
            for: comparison,
            textReport: textReport,
            configuration: TranslationRAMPointerScanConfiguration(
                maximumReferencesPerTarget: 1
            )
        )
        try expect(
            referenceBounded.wasTruncated
                && referenceBounded.leads.first { $0.targetOffset == 0x0200 }?
                    .originalReferenceOffsets == [0x0010],
            "RAM pointer scan did not enforce its per-target reference bound"
        )

        do {
            _ = try TranslationRAMPointerScanner.report(
                for: comparison,
                textReport: textReport,
                configuration: TranslationRAMPointerScanConfiguration(
                    maximumInputByteCount: 1_024
                )
            )
            throw CheckFailure(message: "RAM pointer scan accepted an oversized input")
        } catch is TranslationRAMPointerScanError {}
        do {
            _ = try TranslationRAMPointerScanner.report(
                for: comparison,
                textReport: textReport,
                configuration: TranslationRAMPointerScanConfiguration(
                    maximumReferencesPerTarget: 0
                )
            )
            throw CheckFailure(message: "RAM pointer scan accepted invalid limits")
        } catch is TranslationRAMPointerScanError {}

        let mismatchedComparison = try TranslationRAMComparison(
            originalEvidenceName: "different-original",
            patchedEvidenceName: "different-patched",
            route: route,
            originalFrameNumber: 220,
            patchedFrameNumber: 220,
            original: original,
            patched: patched
        )
        do {
            _ = try TranslationRAMPointerScanner.report(
                for: mismatchedComparison,
                textReport: textReport
            )
            throw CheckFailure(message: "RAM pointer scan accepted a stale text report")
        } catch TranslationRAMPointerScanError.mismatchedTextReport {}
    }

    private static func XCTUnwrap<T>(_ value: T?) throws -> T {
        guard let value else { throw CheckFailure(message: "required test value was nil") }
        return value
    }

    private static func contentPixels(_ frame: EngineVideoFrame) -> Data {
        let width = min(frame.width, 224)
        let height = min(frame.height, 144)
        var output = Data(capacity: width * height * 4)
        for row in 0..<height {
            let start = row * frame.strideBytes
            output.append(frame.pixels[start..<(start + width * 4)])
        }
        return output
    }

    private static func checkStateStoreRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GameStateStore(rootURL: root, maximumTimelineEntries: 8)

        func identity(
            romByte: UInt8 = 0x11,
            firmwareByte: UInt8 = 0x22,
            buildID: String? = "ares-test-build",
            backend: String = "ares"
        ) -> GameStateSessionIdentity {
            GameStateSessionIdentity(
                rom: Data(repeating: romByte, count: 128 * 1_024),
                romChecksum: 0x1234,
                firmware: Data(repeating: firmwareByte, count: 8 * 1_024),
                isColor: true,
                backend: backend,
                engineBuildID: buildID
            )
        }

        func isLegacy(_ compatibility: GameStateCompatibility) -> Bool {
            if case .legacyNeedsConfirmation = compatibility { return true }
            return false
        }

        func isWrongROM(_ compatibility: GameStateCompatibility) -> Bool {
            if case .wrongROM = compatibility { return true }
            return false
        }

        func isWrongFirmware(_ compatibility: GameStateCompatibility) -> Bool {
            if case .wrongFirmware = compatibility { return true }
            return false
        }

        func isWrongEngineBuild(_ compatibility: GameStateCompatibility) -> Bool {
            if case .wrongEngineBuild = compatibility { return true }
            return false
        }

        func isDamaged(_ compatibility: GameStateCompatibility) -> Bool {
            if case .damaged = compatibility { return true }
            return false
        }

        func makePreview(seed: UInt8) throws -> Data {
            let width = 224
            let height = 144
            let stride = width * 4
            var pixels = Data(count: stride * height)
            pixels.withUnsafeMutableBytes { raw in
                let bytes = raw.bindMemory(to: UInt8.self)
                for pixel in 0..<(width * height) {
                    let offset = pixel * 4
                    bytes[offset] = seed &+ UInt8(truncatingIfNeeded: pixel)
                    bytes[offset + 1] = seed &+ UInt8(truncatingIfNeeded: pixel / width)
                    bytes[offset + 2] = seed &+ UInt8(truncatingIfNeeded: pixel % width)
                    bytes[offset + 3] = 255
                }
            }
            return try EngineFramePNGCodec.encode(EngineVideoFrame(
                pixels: pixels,
                width: width,
                height: height,
                strideBytes: stride,
                isVertical: false,
                number: 0
            ))
        }

        let currentIdentity = identity()
        let state = Data(repeating: 0x3c, count: 2048)
        let preview = try makePreview(seed: 1)
        let gameID = UUID()
        let manifest = try store.saveQuickState(
            gameID: gameID,
            sessionIdentity: currentIdentity,
            frameNumber: 99,
            state: state,
            previewPNG: preview
        )
        try expect(
            manifest.schemaVersion == GameStateManifest.currentSchemaVersion,
            "new quick state did not use schema 2"
        )
        try expect(
            manifest.romSHA256 == currentIdentity.romSHA256
                && manifest.romByteCount == currentIdentity.romByteCount
                && manifest.firmwareSHA256 == currentIdentity.firmwareSHA256
                && manifest.firmwareByteCount == currentIdentity.firmwareByteCount
                && manifest.hardwareModel == .wonderSwanColor
                && manifest.isColor == true
                && manifest.backend == currentIdentity.backend
                && manifest.engineBuildID == currentIdentity.engineBuildID
                && manifest.stateSHA256 != nil
                && manifest.previewByteCount == preview.count
                && manifest.previewSHA256 != nil,
            "schema-2 manifest omitted an exact session or artifact identity"
        )
        let loaded = try XCTUnwrap(
            store.loadQuickState(gameID: gameID, sessionIdentity: currentIdentity)
        )
        try expect(loaded.manifest == manifest, "quick-state manifest mismatch")
        try expect(loaded.state == state, "quick-state payload mismatch")
        try expect(loaded.previewPNG == preview, "quick-state preview mismatch")
        try expect(loaded.compatibility == .ready, "matching schema-2 state was not ready")

        let checksumCollision = try XCTUnwrap(
            store.loadQuickState(
                gameID: gameID,
                sessionIdentity: identity(romByte: 0x12)
            )
        )
        try expect(
            isWrongROM(checksumCollision.compatibility),
            "different ROM bytes with the same 16-bit checksum were accepted"
        )
        let firmwareMismatch = try XCTUnwrap(
            store.loadQuickState(
                gameID: gameID,
                sessionIdentity: identity(firmwareByte: 0x23)
            )
        )
        try expect(
            isWrongFirmware(firmwareMismatch.compatibility),
            "different startup-file bytes were accepted"
        )
        let buildMismatch = try XCTUnwrap(
            store.loadQuickState(
                gameID: gameID,
                sessionIdentity: identity(buildID: "different-ares-build")
            )
        )
        try expect(
            isWrongEngineBuild(buildMismatch.compatibility),
            "different engine build was accepted"
        )

        let corruptGameID = UUID()
        let corruptManifest = try store.saveQuickState(
            gameID: corruptGameID,
            sessionIdentity: currentIdentity,
            frameNumber: 50,
            state: state,
            previewPNG: preview
        )
        let corruptDirectory = root.appendingPathComponent(
            corruptGameID.uuidString,
            isDirectory: true
        )
        var corruptState = state
        corruptState[0] ^= 0xff
        try corruptState.write(
            to: corruptDirectory.appendingPathComponent(
                "\(corruptManifest.generation.uuidString).state"
            ),
            options: [.atomic]
        )
        let corruptRecord = try XCTUnwrap(
            store.loadQuickState(gameID: corruptGameID, sessionIdentity: currentIdentity)
        )
        try expect(
            isDamaged(corruptRecord.compatibility),
            "same-length state corruption passed its SHA-256 check"
        )

        let previewGameID = UUID()
        let healthyPreview = try makePreview(seed: 2)
        let healthy = try store.saveQuickState(
            gameID: previewGameID,
            sessionIdentity: currentIdentity,
            frameNumber: 60,
            state: Data(repeating: 0x4d, count: 1024),
            previewPNG: healthyPreview
        )
        let damagedPreview = try makePreview(seed: 3)
        let damaged = try store.saveQuickState(
            gameID: previewGameID,
            sessionIdentity: currentIdentity,
            frameNumber: 61,
            state: Data(repeating: 0x5e, count: 512),
            previewPNG: damagedPreview
        )
        let previewDirectory = root.appendingPathComponent(
            previewGameID.uuidString,
            isDirectory: true
        )
        var corruptedPreview = damagedPreview
        corruptedPreview[corruptedPreview.count / 2] ^= 0xff
        try corruptedPreview.write(
            to: previewDirectory.appendingPathComponent("\(damaged.generation.uuidString).png"),
            options: [.atomic]
        )
        let missing = try store.saveQuickState(
            gameID: previewGameID,
            sessionIdentity: currentIdentity,
            frameNumber: 62,
            state: Data(repeating: 0x6f, count: 768),
            previewPNG: try makePreview(seed: 4)
        )
        try FileManager.default.removeItem(
            at: previewDirectory.appendingPathComponent("\(missing.generation.uuidString).png")
        )
        var timeline = try store.listStates(
            gameID: previewGameID,
            sessionIdentity: currentIdentity
        )
        try expect(timeline.count == 3, "a damaged preview hid the rest of the timeline")
        let damagedSummary = try XCTUnwrap(timeline.first { $0.id == damaged.generation })
        let missingSummary = try XCTUnwrap(timeline.first { $0.id == missing.generation })
        let healthySummary = try XCTUnwrap(timeline.first { $0.id == healthy.generation })
        try expect(
            damagedSummary.compatibility == .ready
                && damagedSummary.previewPNG.isEmpty
                && damagedSummary.previewIssue != nil,
            "damaged preview was not isolated from its loadable emulator state"
        )
        try expect(
            missingSummary.compatibility == .ready
                && missingSummary.previewPNG.isEmpty
                && missingSummary.previewIssue != nil,
            "missing preview was not isolated from its loadable emulator state"
        )
        try expect(
            healthySummary.compatibility == .ready
                && healthySummary.previewPNG == healthyPreview
                && healthySummary.previewIssue == nil,
            "healthy timeline card was degraded by another preview"
        )

        let previewlessGameID = UUID()
        let previewless = try store.saveQuickState(
            gameID: previewlessGameID,
            sessionIdentity: currentIdentity,
            frameNumber: 62,
            state: state,
            previewPNG: nil
        )
        let previewlessSummary = try XCTUnwrap(
            store.listStates(
                gameID: previewlessGameID,
                sessionIdentity: currentIdentity
            ).first { $0.id == previewless.generation }
        )
        try expect(
            previewlessSummary.compatibility == .ready
                && previewlessSummary.previewPNG.isEmpty
                && previewlessSummary.previewIssue != nil,
            "previewless schema-2 state was not marked unsafe for transient-free loading"
        )

        let legacyGameID = UUID()
        let legacy = try store.saveQuickState(
            gameID: legacyGameID,
            romChecksum: currentIdentity.romChecksum,
            frameNumber: 70,
            backend: currentIdentity.backend,
            state: state,
            previewPNG: preview
        )
        try expect(legacy.schemaVersion == 1, "legacy writer no longer creates schema 1")
        let legacyRecord = try XCTUnwrap(
            store.loadQuickState(gameID: legacyGameID, sessionIdentity: currentIdentity)
        )
        try expect(
            isLegacy(legacyRecord.compatibility) && !legacyRecord.compatibility.isReady,
            "schema-1 state was silently classified as ready"
        )
        let legacyDirectory = root.appendingPathComponent(
            legacyGameID.uuidString,
            isDirectory: true
        )
        try FileManager.default.removeItem(
            at: legacyDirectory.appendingPathComponent("Timeline.json")
        )
        let migrated = try store.saveQuickState(
            gameID: legacyGameID,
            sessionIdentity: currentIdentity,
            frameNumber: 71,
            state: Data(repeating: 0x7a, count: 256),
            previewPNG: try makePreview(seed: 5)
        )
        let migratedTimeline = try store.listStates(
            gameID: legacyGameID,
            sessionIdentity: currentIdentity
        )
        try expect(
            migratedTimeline.map(\.id) == [migrated.generation, legacy.generation]
                && migratedTimeline[0].compatibility == .ready
                && isLegacy(migratedTimeline[1].compatibility),
            "first schema-2 save discarded a QuickState-only legacy generation"
        )
        let migratedQuick = try XCTUnwrap(
            store.loadQuickState(gameID: legacyGameID, sessionIdentity: currentIdentity)
        )
        try expect(
            migratedQuick.manifest.generation == migrated.generation,
            "schema-2 quick pointer did not publish from the single timeline index"
        )

        let timelineGameID = UUID()
        let second = try store.saveQuickState(
            gameID: timelineGameID,
            sessionIdentity: currentIdentity,
            frameNumber: 100,
            state: Data(repeating: 0x4d, count: 1024),
            previewPNG: try makePreview(seed: 6)
        )
        let third = try store.saveQuickState(
            gameID: timelineGameID,
            sessionIdentity: currentIdentity,
            frameNumber: 101,
            state: Data(repeating: 0x5e, count: 512),
            previewPNG: try makePreview(seed: 7)
        )
        timeline = try store.listStates(
            gameID: timelineGameID,
            sessionIdentity: currentIdentity
        )
        try expect(
            timeline.map(\.id) == [third.generation, second.generation],
            "timeline ordering mismatch"
        )
        let historical = try store.loadState(
            gameID: timelineGameID,
            generation: second.generation,
            sessionIdentity: currentIdentity
        )
        try expect(
            historical.manifest.frameNumber == 100 && historical.compatibility == .ready,
            "historical state lookup mismatch"
        )
        try store.deleteState(gameID: timelineGameID, generation: third.generation)
        timeline = try store.listStates(
            gameID: timelineGameID,
            sessionIdentity: currentIdentity
        )
        try expect(timeline.map(\.id) == [second.generation], "timeline deletion mismatch")
        let replacementQuick = try store.loadQuickState(
            gameID: timelineGameID,
            sessionIdentity: currentIdentity
        )
        try expect(
            replacementQuick?.manifest.generation == second.generation,
            "quick-state fallback mismatch"
        )
    }
}
