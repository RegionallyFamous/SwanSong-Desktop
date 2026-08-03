import Foundation

/// A deliberately coarse, source-free stage for a failed read-only Original
/// frame authentication. The value identifies which fail-closed boundary
/// refused the request without retaining or publishing the underlying error.
public enum TranslationOriginalFrameAuthenticationStage:
    String, CaseIterable, Codable, Equatable, Sendable
{
    case authorization
    case executorObservation = "executor-observation"
    case boundInputProjectTreeObservation =
        "bound-input-project-tree-observation"
    case runTreeObservation = "run-tree-observation"
    case preSealAssembly = "pre-seal-assembly"
    case project
    case plan
    case authentication
    case engine
    case query
    case inspect
    case load
    case run
    case frame
    case raster
    case endpoint
    case geometry
    case revalidation
    case output

    public static let markerPrefix =
        "ORIGINAL_FRAME_AUTHENTICATION_STAGE:"

    public var marker: String {
        Self.markerPrefix + rawValue
    }

    /// Executes one authentication boundary and replaces every underlying
    /// failure with only its source-free stage. A stage already classified by
    /// an inner boundary is preserved.
    public func perform<T>(_ operation: () throws -> T) throws -> T {
        do {
            return try operation()
        } catch let failure as TranslationOriginalFrameAuthenticationStageFailure {
            throw failure
        } catch {
            throw TranslationOriginalFrameAuthenticationStageFailure(stage: self)
        }
    }

    /// Extracts exactly one known stage marker from private runner output.
    /// Unknown or ambiguous output remains unclassified.
    public static func sourceFreeCategory(
        in runnerOutput: String
    ) -> TranslationOriginalFrameAuthenticationStage? {
        let matches = allCases.filter { stage in
            let escaped = NSRegularExpression.escapedPattern(
                for: stage.marker
            )
            return runnerOutput.range(
                of: escaped + "(?:$|[^a-z0-9-])",
                options: .regularExpression
            ) != nil
        }
        return matches.count == 1 ? matches[0] : nil
    }

    /// Public-negative-control KAT for the stage boundary and its redaction.
    public static func signedReleaseSourceFreeStageKAT() throws -> String {
        let privateDecoy =
            "private-path=/never/share/private.rom address=0x1234"
        for stage in allCases {
            do {
                try stage.perform { () throws -> Void in
                    throw NSError(
                        domain: privateDecoy,
                        code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey: privateDecoy,
                        ]
                    )
                }
            } catch let failure
                as TranslationOriginalFrameAuthenticationStageFailure
            {
                guard failure.stage == stage,
                      failure.errorDescription
                        == "STOP_PREEXECUTION_CAPABILITY: \(stage.marker)",
                      failure.errorDescription?.contains(privateDecoy) == false,
                      sourceFreeCategory(
                        in: "runner-prefix \(stage.marker) \(privateDecoy)"
                      ) == stage else {
                    throw TranslationLabError.invalidRoute(
                        "source-free Original-frame stage KAT failed"
                    )
                }
            }
        }
        guard sourceFreeCategory(in: privateDecoy) == nil,
              sourceFreeCategory(in: markerPrefix) == nil,
              sourceFreeCategory(
                in: markerPrefix + "unknown-private-stage"
              ) == nil,
              sourceFreeCategory(
                in: "\(inspect.marker) \(load.marker)"
              ) == nil else {
            throw TranslationLabError.invalidRoute(
                "source-free Original-frame stage ambiguity KAT failed"
            )
        }
        return "PASS original-frame-stage-categories "
            + allCases.map(\.rawValue).joined(separator: ",")
    }
}

public struct TranslationOriginalFrameAuthenticationStageFailure:
    LocalizedError, Equatable, Sendable
{
    public let stage: TranslationOriginalFrameAuthenticationStage

    public init(stage: TranslationOriginalFrameAuthenticationStage) {
        self.stage = stage
    }

    public var errorDescription: String? {
        "STOP_PREEXECUTION_CAPABILITY: \(stage.marker)"
    }
}
