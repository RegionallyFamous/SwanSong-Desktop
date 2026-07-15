import Foundation
import SwanSongKit

/// Compares both private Translation Lab ROM lanes without entering the normal
/// library or touching cartridge-save storage.
///
/// The pinned ares bridge deliberately permits one live WonderSwan instance at
/// a time. SwanSong therefore runs deterministic clean-boot passes: Original
/// first (including endpoint validation), then Patched, and finally a short
/// Original replay only when it must reconstruct the exact first changed pair.
enum TranslationVisualDivergenceRunner {
    enum Phase: String, Equatable, Sendable {
        case original
        case patched
        case confirmingFirstChange
        case complete

        var title: String {
            switch self {
            case .original: "Validating Original"
            case .patched: "Comparing Patched"
            case .confirmingFirstChange: "Reconstructing first change"
            case .complete: "Comparison complete"
            }
        }
    }

    struct Progress: Equatable, Sendable {
        let phase: Phase
        let framesProcessed: UInt64
        let totalFrames: UInt64
        let firstDifferenceFrameIndex: UInt64?

        init(
            phase: Phase = .original,
            framesProcessed: UInt64,
            totalFrames: UInt64,
            firstDifferenceFrameIndex: UInt64?
        ) {
            self.phase = phase
            self.framesProcessed = framesProcessed
            self.totalFrames = totalFrames
            self.firstDifferenceFrameIndex = firstDifferenceFrameIndex
        }

        var fractionComplete: Double {
            guard totalFrames > 0 else { return 0 }
            let lane = min(Double(framesProcessed) / Double(totalFrames), 1)
            return switch phase {
            case .original: lane * 0.45
            case .patched: 0.45 + lane * 0.45
            case .confirmingFirstChange: 0.90 + lane * 0.10
            case .complete: 1
            }
        }
    }

    private struct OriginalPass {
        let fingerprints: [String]
        let endpoint: EngineVideoFrame
    }

    private struct PatchedPass {
        let firstDifferenceFrameIndex: UInt64?
        let firstDifferenceFrame: EngineVideoFrame?
        let precedingFrame: EngineVideoFrame?
        let endpoint: EngineVideoFrame
    }

    static func run(
        route: TranslationRoute,
        originalROM: Data,
        patchedROM: Data,
        startupFile: Data?,
        progress: @escaping @Sendable (Progress) async -> Void
    ) async throws -> TranslationVisualDivergenceResult {
        // Validate the proof route and hard frame cap before allocating its
        // compact fingerprint table.
        _ = try TranslationVisualDivergenceAnalyzer(route: route)

        let original = try await runOriginalPass(
            route: route,
            rom: originalROM,
            startupFile: startupFile,
            progress: progress
        )
        let patched = try await runPatchedPass(
            route: route,
            rom: patchedROM,
            startupFile: startupFile,
            originalFingerprints: original.fingerprints,
            progress: progress
        )

        guard let differenceIndex = patched.firstDifferenceFrameIndex,
              let patchedDifferenceFrame = patched.firstDifferenceFrame else {
            let lastIndex = route.totalFrames - 1
            await progress(
                Progress(
                    phase: .complete,
                    framesProcessed: route.totalFrames,
                    totalFrames: route.totalFrames,
                    firstDifferenceFrameIndex: nil
                )
            )
            return .noDifference(
                TranslationVisualNoDifference(
                    framesCompared: route.totalFrames,
                    lastIdenticalFrame: TranslationVisualComparedFrame(
                        frameIndex: lastIndex,
                        inputMask: route.input(at: lastIndex).rawValue,
                        frames: TranslationVisualFramePair(
                            original: original.endpoint,
                            patched: patched.endpoint
                        )
                    )
                )
            )
        }

        let (originalDifferenceFrame, precedingOriginalFrame) = try await
            reconstructOriginalFrame(
                route: route,
                rom: originalROM,
                startupFile: startupFile,
                through: differenceIndex,
                progress: progress
            )
        let previousPair: TranslationVisualComparedFrame?
        if differenceIndex > 0,
           let precedingOriginalFrame,
           let precedingPatchedFrame = patched.precedingFrame {
            let previousIndex = differenceIndex - 1
            previousPair = TranslationVisualComparedFrame(
                frameIndex: previousIndex,
                inputMask: route.input(at: previousIndex).rawValue,
                frames: TranslationVisualFramePair(
                    original: precedingOriginalFrame,
                    patched: precedingPatchedFrame
                )
            )
        } else {
            previousPair = nil
        }
        guard let divergence = try TranslationVisualDivergenceAnalyzer.compareFramePair(
            route: route,
            frameIndex: differenceIndex,
            original: originalDifferenceFrame,
            patched: patchedDifferenceFrame,
            previousIdenticalFrame: previousPair
        ) else {
            throw TranslationLabError.invalidRoute(
                "the first changed frame could not be reconstructed deterministically"
            )
        }
        await progress(
            Progress(
                phase: .complete,
                framesProcessed: route.totalFrames,
                totalFrames: route.totalFrames,
                firstDifferenceFrameIndex: differenceIndex
            )
        )
        return .firstDifference(divergence)
    }

    private static func runOriginalPass(
        route: TranslationRoute,
        rom: Data,
        startupFile: Data?,
        progress: @escaping @Sendable (Progress) async -> Void
    ) async throws -> OriginalPass {
        let runner = try makeRunner(route: route)
        do {
            try await prepare(runner, rom: rom, startupFile: startupFile)
            var fingerprints: [String] = []
            fingerprints.reserveCapacity(Int(route.totalFrames))
            var endpoint: EngineVideoFrame?
            await progress(
                Progress(
                    phase: .original,
                    framesProcessed: 0,
                    totalFrames: route.totalFrames,
                    firstDifferenceFrameIndex: nil
                )
            )
            for frameIndex in 0..<route.totalFrames {
                try Task.checkCancellation()
                let output = try await runner.nextFrame(input: route.input(at: frameIndex))
                fingerprints.append(try TranslationRouteCheckpoint.fingerprint(output.video))
                endpoint = output.video
                if (frameIndex + 1).isMultiple(of: 15)
                    || frameIndex + 1 == route.totalFrames {
                    await progress(
                        Progress(
                            phase: .original,
                            framesProcessed: frameIndex + 1,
                            totalFrames: route.totalFrames,
                            firstDifferenceFrameIndex: nil
                        )
                    )
                }
            }
            guard let endpoint,
                  route.checkpoint?.matches(endpoint) == true else {
                throw TranslationVisualDivergenceError.originalCheckpointMismatch
            }
            try? await runner.stop()
            return OriginalPass(fingerprints: fingerprints, endpoint: endpoint)
        } catch {
            try? await runner.stop()
            throw error
        }
    }

    private static func runPatchedPass(
        route: TranslationRoute,
        rom: Data,
        startupFile: Data?,
        originalFingerprints: [String],
        progress: @escaping @Sendable (Progress) async -> Void
    ) async throws -> PatchedPass {
        guard originalFingerprints.count == Int(route.totalFrames) else {
            throw TranslationLabError.invalidRoute(
                "the Original fingerprint pass ended before the route endpoint"
            )
        }
        let runner = try makeRunner(route: route)
        do {
            try await prepare(runner, rom: rom, startupFile: startupFile)
            var previousFrame: EngineVideoFrame?
            var firstDifferenceFrameIndex: UInt64?
            var firstDifferenceFrame: EngineVideoFrame?
            var precedingFrame: EngineVideoFrame?
            var endpoint: EngineVideoFrame?
            for frameIndex in 0..<route.totalFrames {
                try Task.checkCancellation()
                let output = try await runner.nextFrame(input: route.input(at: frameIndex))
                if firstDifferenceFrameIndex == nil {
                    let fingerprint = try TranslationRouteCheckpoint.fingerprint(output.video)
                    if fingerprint != originalFingerprints[Int(frameIndex)] {
                        firstDifferenceFrameIndex = frameIndex
                        firstDifferenceFrame = output.video
                        precedingFrame = previousFrame
                    }
                }
                previousFrame = output.video
                endpoint = output.video
                if (frameIndex + 1).isMultiple(of: 15)
                    || frameIndex + 1 == route.totalFrames {
                    await progress(
                        Progress(
                            phase: .patched,
                            framesProcessed: frameIndex + 1,
                            totalFrames: route.totalFrames,
                            firstDifferenceFrameIndex: firstDifferenceFrameIndex
                        )
                    )
                }
            }
            guard let endpoint else {
                throw TranslationVisualDivergenceError.incomplete(
                    expectedFrames: route.totalFrames,
                    actualFrames: 0
                )
            }
            try? await runner.stop()
            return PatchedPass(
                firstDifferenceFrameIndex: firstDifferenceFrameIndex,
                firstDifferenceFrame: firstDifferenceFrame,
                precedingFrame: precedingFrame,
                endpoint: endpoint
            )
        } catch {
            try? await runner.stop()
            throw error
        }
    }

    private static func reconstructOriginalFrame(
        route: TranslationRoute,
        rom: Data,
        startupFile: Data?,
        through target: UInt64,
        progress: @escaping @Sendable (Progress) async -> Void
    ) async throws -> (EngineVideoFrame, EngineVideoFrame?) {
        let runner = try makeRunner(route: route)
        do {
            try await prepare(runner, rom: rom, startupFile: startupFile)
            var previous: EngineVideoFrame?
            var targetFrame: EngineVideoFrame?
            for frameIndex in 0...target {
                try Task.checkCancellation()
                let output = try await runner.nextFrame(input: route.input(at: frameIndex))
                if frameIndex == target {
                    targetFrame = output.video
                } else {
                    previous = output.video
                }
                if (frameIndex + 1).isMultiple(of: 15) || frameIndex == target {
                    await progress(
                        Progress(
                            phase: .confirmingFirstChange,
                            framesProcessed: frameIndex + 1,
                            totalFrames: max(target + 1, 1),
                            firstDifferenceFrameIndex: target
                        )
                    )
                }
            }
            guard let targetFrame else {
                throw TranslationVisualDivergenceError.incomplete(
                    expectedFrames: target + 1,
                    actualFrames: 0
                )
            }
            try? await runner.stop()
            return (targetFrame, previous)
        } catch {
            try? await runner.stop()
            throw error
        }
    }

    private static func makeRunner(route: TranslationRoute) throws -> EmulationRunner {
        guard let start = route.start else {
            throw TranslationLabError.invalidRoute(
                "the route start context is missing"
            )
        }
        return try EmulationRunner(
            rtcMode: .deterministic(
                seedUnixSeconds: TranslationRouteRTCContext.proofSeedUnixSeconds
            ),
            hardwareModel: start.engineHardwareModel
        )
    }

    private static func prepare(
        _ runner: EmulationRunner,
        rom: Data,
        startupFile: Data?
    ) async throws {
        if let startupFile {
            try await runner.stageBootROM(startupFile)
        }
        _ = try await runner.load(rom: rom)
    }
}
