import Foundation

public enum StoryForgeStage: String, CaseIterable, Codable, Identifiable, Sendable {
    case concept
    case outline
    case draft
    case revision
    case release

    public var id: String { rawValue }

    public var title: String { rawValue.capitalized }
}

public enum StoryForgeBookFormat: String, CaseIterable, Codable, Identifiable, Sendable {
    case novella
    case shortLightNovel = "short-light-novel"
    case volume

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .novella: "Novella"
        case .shortLightNovel: "Short Light Novel"
        case .volume: "Full Volume"
        }
    }
}

public enum StoryForgeGenreProfile: String, CaseIterable, Codable, Identifiable, Sendable {
    case custom
    case cozyComedy = "cozy-comedy"
    case romance
    case mystery
    case adventure
    case sliceOfLife = "slice-of-life"
    case drama
    case fantasy
    case scienceFiction = "science-fiction"

    public var id: String { rawValue }

    public var title: String {
        rawValue.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
    }
}

public enum StoryForgeReportKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case characterVoice = "character-voice"
    case prosePolish = "prose-polish"
    case chapterMomentum = "chapter-momentum"
    case sceneDelivery = "scene-delivery"
    case continuity
    case readerSynthesis = "reader-synthesis"
    case rightsRelease = "rights-release"
    case soundtrackBible = "soundtrack-bible"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .characterVoice: "Character Voice"
        case .prosePolish: "Prose Polish"
        case .chapterMomentum: "Chapter Momentum"
        case .sceneDelivery: "Scene Delivery"
        case .continuity: "Continuity"
        case .readerSynthesis: "Reader Synthesis"
        case .rightsRelease: "Rights & Release"
        case .soundtrackBible: "Soundtrack Bible"
        }
    }

    var scriptName: String {
        switch self {
        case .characterVoice: "report_character_voice.py"
        case .prosePolish: "report_prose_polish.py"
        case .chapterMomentum: "report_chapter_momentum.py"
        case .sceneDelivery: "report_scene_delivery.py"
        case .continuity: "report_novel_continuity.py"
        case .readerSynthesis: "synthesize_reader_feedback.py"
        case .rightsRelease: "report_rights_release_lane.py"
        case .soundtrackBible: "report_soundtrack_bible.py"
        }
    }

    public var reportFilename: String {
        switch self {
        case .characterVoice: "character-voice-report.json"
        case .prosePolish: "prose-polish-report.json"
        case .chapterMomentum: "chapter-momentum-report.json"
        case .sceneDelivery: "scene-delivery-report.json"
        case .continuity: "continuity-report.json"
        case .readerSynthesis: "reader-synthesis-report.json"
        case .rightsRelease: "rights-release-report.json"
        case .soundtrackBible: "soundtrack-bible-report.json"
        }
    }
}

public enum StoryForgeCommand: Equatable, Sendable {
    case createProject(
        slug: String,
        title: String,
        destination: URL,
        format: StoryForgeBookFormat,
        targetWords: Int,
        genre: StoryForgeGenreProfile
    )
    case migrate(manifest: URL, output: URL?)
    case validate(manifest: URL, stage: StoryForgeStage, report: URL)
    case report(kind: StoryForgeReportKind, manifest: URL, output: URL?)
    case illustrationBriefs(manifest: URL)
    case illustrationReview(manifest: URL)
    case lock(manifest: URL, check: Bool)
    case catalogStatus(root: URL, report: URL, markdown: URL)
    case catalogAudit(root: URL, output: URL, strict: Bool)
    case seriesBible(root: URL, output: URL)
    case buildRelease(manifest: URL)

    public var scriptName: String {
        switch self {
        case .createProject: "create_light_novel_project.py"
        case .migrate: "migrate_light_novel_project.py"
        case .validate: "check_light_novel_project.py"
        case let .report(kind, _, _): kind.scriptName
        case .illustrationBriefs: "make_imagegen_illustration_briefs.py"
        case .illustrationReview: "review_novel_illustrations.py"
        case .lock: "lock_light_novel_project.py"
        case .catalogStatus: "status_novel_catalog.py"
        case .catalogAudit: "audit_novel_catalog.py"
        case .seriesBible: "build_series_bible.py"
        case .buildRelease: "build_novel_release.py"
        }
    }

    public var arguments: [String] {
        switch self {
        case let .createProject(slug, title, destination, format, targetWords, genre):
            return [
                slug,
                "--title", title,
                "--destination", destination.path,
                "--format", format.rawValue,
                "--target-words", String(targetWords),
                "--manifest-format", "json",
                "--genre-profile", genre.rawValue,
            ]
        case let .migrate(manifest, output):
            var values = [manifest.path]
            if let output { values += ["--out", output.path] }
            return values
        case let .validate(manifest, stage, report):
            return [manifest.path, "--stage", stage.rawValue, "--out", report.path]
        case let .report(_, manifest, output):
            var values = [manifest.path]
            if let output { values += ["--out", output.path] }
            return values
        case let .illustrationBriefs(manifest):
            return [manifest.path]
        case let .illustrationReview(manifest):
            return [manifest.path]
        case let .lock(manifest, check):
            return [manifest.path] + (check ? ["--check"] : [])
        case let .catalogStatus(root, report, markdown):
            return [root.path, "--out", report.path, "--markdown", markdown.path]
        case let .catalogAudit(root, output, strict):
            return [root.path, "--out", output.path] + (strict ? ["--strict"] : [])
        case let .seriesBible(root, output):
            return [root.path, "--out", output.path]
        case let .buildRelease(manifest):
            return [manifest.path]
        }
    }

    public var workingDirectory: URL {
        switch self {
        case let .createProject(_, _, destination, _, _, _): destination
        case let .catalogStatus(root, _, _), let .catalogAudit(root, _, _),
             let .seriesBible(root, _): root
        case let .migrate(manifest, _), let .validate(manifest, _, _),
             let .report(_, manifest, _), let .illustrationBriefs(manifest),
             let .illustrationReview(manifest), let .lock(manifest, _),
             let .buildRelease(manifest):
            manifest.deletingLastPathComponent()
        }
    }
}

public enum StoryForgeIntegrationError: LocalizedError, Equatable {
    case invalidFramework(String)
    case invalidProject(String)
    case malformedReport(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidFramework(detail), let .invalidProject(detail),
             let .malformedReport(detail): detail
        }
    }
}

public struct StoryForgeCLIResolution: Equatable, Sendable {
    public static let requiredSchemaVersion = 3

    public let root: URL
    public let pythonURL: URL
    public let pythonPrefix: [String]
    public let scriptsDirectory: URL

    public static func resolve(
        root: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> Self {
        let resolved = root.standardizedFileURL.resolvingSymlinksInPath()
        let scripts = resolved.appendingPathComponent("scripts", isDirectory: true)
        let starter = resolved.appendingPathComponent(
            "skills/forge-light-novels/assets/starter/novel.json"
        )
        let requiredScripts = [
            "create_light_novel_project.py",
            "check_light_novel_project.py",
            "report_character_voice.py",
            "report_prose_polish.py",
            "report_chapter_momentum.py",
            "report_scene_delivery.py",
            "report_novel_continuity.py",
            "synthesize_reader_feedback.py",
            "report_rights_release_lane.py",
            "report_soundtrack_bible.py",
            "make_imagegen_illustration_briefs.py",
            "review_novel_illustrations.py",
            "lock_light_novel_project.py",
            "migrate_light_novel_project.py",
            "status_novel_catalog.py",
            "audit_novel_catalog.py",
            "build_series_bible.py",
            "build_novel_release.py",
        ]
        guard FileManager.default.fileExists(atPath: starter.path),
              requiredScripts.allSatisfy({
                  FileManager.default.fileExists(
                      atPath: scripts.appendingPathComponent($0).path
                  )
              }) else {
            throw StoryForgeIntegrationError.invalidFramework(
                "Choose the Story Forge repository containing the schema-v3 novel starter and complete scripts folder."
            )
        }
        let data = try Data(contentsOf: starter)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard object?["schema_version"] as? Int == requiredSchemaVersion else {
            throw StoryForgeIntegrationError.invalidFramework(
                "SwanSong requires Story Forge light-novel schema v3."
            )
        }

        let python: URL
        let prefix: [String]
        if let override = environment["SWANSONG_STORY_FORGE_PYTHON"], !override.isEmpty {
            python = URL(fileURLWithPath: override)
            prefix = []
        } else {
            python = URL(fileURLWithPath: "/usr/bin/env")
            prefix = ["python3"]
        }
        return Self(root: resolved, pythonURL: python, pythonPrefix: prefix, scriptsDirectory: scripts)
    }

    public func invocation(for command: StoryForgeCommand) -> SwanSDKCommandInvocation {
        SwanSDKCommandInvocation(
            executableURL: pythonURL,
            arguments: pythonPrefix + [
                "-B",
                scriptsDirectory.appendingPathComponent(command.scriptName).path,
            ] + command.arguments,
            workingDirectory: command.workingDirectory,
            environment: [
                "PYTHONDONTWRITEBYTECODE": "1",
                "STORY_FORGE_ROOT": root.path,
            ]
        )
    }
}

public struct StoryForgeManifestSummary: Equatable, Sendable {
    public let schemaVersion: Int
    public let slug: String
    public let title: String
    public let stage: StoryForgeStage
    public let rightsLane: String
    public let releaseScope: String
    public let sceneCount: Int
    public let chapterCount: Int
    public let illustrationCount: Int
    public let readerCount: Int
    public let reportCount: Int
    public let soundtrackEnabled: Bool

    public static func load(from manifest: URL) throws -> Self {
        guard ["json", "yaml", "yml"].contains(manifest.pathExtension.lowercased()) else {
            throw StoryForgeIntegrationError.invalidProject(
                "Choose novel.json, novel.yaml, or novel.yml."
            )
        }
        guard manifest.lastPathComponent.hasPrefix("novel.") else {
            throw StoryForgeIntegrationError.invalidProject(
                "Choose the novel manifest at the root of a Story Forge project."
            )
        }
        guard manifest.pathExtension.lowercased() == "json" else {
            throw StoryForgeIntegrationError.invalidProject(
                "SwanSong currently opens the dependency-free novel.json manifest. Use Story Forge to convert YAML projects before opening them here."
            )
        }
        let data = try Data(contentsOf: manifest)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let schemaVersion = object["schema_version"] as? Int,
              schemaVersion == StoryForgeCLIResolution.requiredSchemaVersion,
              let stageValue = object["stage"] as? String,
              let stage = StoryForgeStage(rawValue: stageValue) else {
            throw StoryForgeIntegrationError.invalidProject(
                "The selected project is not a valid Story Forge schema-v3 novel."
            )
        }
        let identity = object["identity"] as? [String: Any] ?? [:]
        let rights = object["rights_release"] as? [String: Any] ?? [:]
        let editorial = object["editorial"] as? [String: Any] ?? [:]
        let illustration = object["illustration_bible"] as? [String: Any] ?? [:]
        let soundtrack = object["soundtrack_bible"] as? [String: Any] ?? [:]
        return Self(
            schemaVersion: schemaVersion,
            slug: identity["slug"] as? String ?? manifest.deletingLastPathComponent().lastPathComponent,
            title: identity["title"] as? String ?? "Untitled",
            stage: stage,
            rightsLane: rights["mode"] as? String ?? "unreviewed",
            releaseScope: rights["release_scope"] as? String ?? "unreviewed",
            sceneCount: (object["scenes"] as? [Any])?.count ?? 0,
            chapterCount: (object["chapters"] as? [Any])?.count ?? 0,
            illustrationCount: (illustration["moments"] as? [Any])?.count ?? 0,
            readerCount: (editorial["reader_tests"] as? [Any])?.count ?? 0,
            reportCount: (editorial["analysis_reports"] as? [Any])?.count ?? 0,
            soundtrackEnabled: soundtrack["enabled"] as? Bool ?? false
        )
    }
}

public struct StoryForgeReportSummary: Equatable, Sendable {
    public let ok: Bool
    public let errors: [String]
    public let warnings: [String]

    public init(ok: Bool, errors: [String], warnings: [String]) {
        self.ok = ok
        self.errors = errors
        self.warnings = warnings
    }

    public static func decode(_ data: Data) throws -> Self {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ok = object["ok"] as? Bool else {
            throw StoryForgeIntegrationError.malformedReport(
                "Story Forge returned a malformed report."
            )
        }
        return Self(
            ok: ok,
            errors: object["errors"] as? [String] ?? [],
            warnings: object["warnings"] as? [String] ?? []
        )
    }
}

public struct StoryForgeGateReport: Codable, Equatable, Sendable {
    public let ok: Bool
    public let errors: [String]
    public let warnings: [String]

    public static func decode(_ data: Data) throws -> Self {
        do {
            return try JSONDecoder().decode(Self.self, from: data)
        } catch {
            throw StoryForgeIntegrationError.malformedReport(
                "Story Forge returned a malformed stage report."
            )
        }
    }
}

public struct StoryForgeCatalogStatus: Codable, Equatable, Sendable {
    public struct Novel: Codable, Equatable, Identifiable, Sendable {
        public let slug: String
        public let title: String
        public let stage: String
        public let gate: String
        public let scenes: Int
        public let words: Int
        public let reports: Int
        public let readerTests: Int
        public let illustrations: Int
        public let staleEvidence: Int
        public let errorCount: Int
        public let nextAction: String
        public let manifest: String

        public var id: String { manifest }

        enum CodingKeys: String, CodingKey {
            case slug, title, stage, gate, scenes, words, reports, illustrations, manifest
            case readerTests = "reader_tests"
            case staleEvidence = "stale_evidence"
            case errorCount = "error_count"
            case nextAction = "next_action"
        }
    }

    public let schemaVersion: Int
    public let tool: String
    public let ok: Bool
    public let root: String
    public let countsByStage: [String: Int]
    public let novels: [Novel]

    enum CodingKeys: String, CodingKey {
        case tool, ok, root, novels
        case schemaVersion = "schema_version"
        case countsByStage = "counts_by_stage"
    }

    public static func decode(_ data: Data) throws -> Self {
        do {
            let value = try JSONDecoder().decode(Self.self, from: data)
            guard value.schemaVersion == 1, value.tool == "novel-catalog-status" else {
                throw StoryForgeIntegrationError.malformedReport(
                    "SwanSong does not recognize this Story Forge catalog report."
                )
            }
            return value
        } catch let error as StoryForgeIntegrationError {
            throw error
        } catch {
            throw StoryForgeIntegrationError.malformedReport(
                "Story Forge returned a malformed catalog report."
            )
        }
    }
}
