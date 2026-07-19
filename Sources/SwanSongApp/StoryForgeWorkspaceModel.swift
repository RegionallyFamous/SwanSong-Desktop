import Foundation
import Observation
import SwanSongKit

enum StoryForgeWorkspaceSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case editorial = "Editorial"
    case artAndMusic = "Art & Music"
    case catalog = "Catalog"
    case publication = "Publish"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .overview: "book.pages"
        case .editorial: "checklist"
        case .artAndMusic: "photo.on.rectangle.angled"
        case .catalog: "books.vertical"
        case .publication: "shippingbox"
        }
    }
}

@MainActor
@Observable
final class StoryForgeWorkspaceModel {
    var selectedSection: StoryForgeWorkspaceSection = .overview
    var frameworkRoot: URL?
    var catalogRoot: URL?
    var manifestURL: URL?
    var projectSummary: StoryForgeManifestSummary?
    var selectedStage: StoryForgeStage = .concept
    var catalogStatus: StoryForgeCatalogStatus?
    var lastReport: StoryForgeReportSummary?
    var lastOperationTitle = ""
    var lastOperationSucceeded: Bool?
    var diagnostics = ""
    var diagnosticsAreVisible = false
    var issue: String?
    var isRunning = false
    var activeCommandName: String?

    var newProjectSlug = ""
    var newProjectTitle = ""
    var newProjectParent: URL?
    var newProjectFormat: StoryForgeBookFormat = .shortLightNovel
    var newProjectGenre: StoryForgeGenreProfile = .custom
    var newProjectTargetWords = 12_000

    private var cli: StoryForgeCLIResolution?
    private let runner: SwanSDKSubprocessRunner
    private let completionNotifier: @MainActor (SwanSongTaskCompletion) -> Void
    private let defaults: UserDefaults
    private var commandTask: Task<Void, Never>?

    private static let frameworkDefaultsKey = "SwanSong.storyForgeRoot"
    private static let catalogDefaultsKey = "SwanSong.storyForgeCatalogRoot"
    private static let projectDefaultsKey = "SwanSong.storyForgeProjectManifest"

    init(
        runner: SwanSDKSubprocessRunner = SwanSDKSubprocessRunner(),
        completionNotifier: @escaping @MainActor (SwanSongTaskCompletion) -> Void = {
            SwanSongTaskNotificationCenter.shared.deliver($0)
        },
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.runner = runner
        self.completionNotifier = completionNotifier
        self.defaults = defaults

        let configured = environment["SWANSONG_STORY_FORGE_DIR"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        let remembered = defaults.string(forKey: Self.frameworkDefaultsKey).map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        if let root = configured ?? remembered {
            do {
                try configureFramework(at: root, remember: configured == nil)
            } catch {
                if configured == nil { defaults.removeObject(forKey: Self.frameworkDefaultsKey) }
                issue = error.localizedDescription
            }
        }

        if let path = defaults.string(forKey: Self.catalogDefaultsKey) {
            let rememberedCatalog = URL(fileURLWithPath: path, isDirectory: true)
            if FileManager.default.fileExists(atPath: rememberedCatalog.path) {
                catalogRoot = rememberedCatalog.standardizedFileURL.resolvingSymlinksInPath()
                newProjectParent = catalogRoot
            } else {
                defaults.removeObject(forKey: Self.catalogDefaultsKey)
            }
        }
        if let path = defaults.string(forKey: Self.projectDefaultsKey) {
            do {
                try openProject(at: URL(fileURLWithPath: path))
            } catch {
                defaults.removeObject(forKey: Self.projectDefaultsKey)
            }
        }
        reloadCatalogStatusFromDisk()
    }

    var frameworkDescription: String {
        guard let frameworkRoot else { return "No Story Forge selected" }
        return "Story Forge schema v3 · \(frameworkRoot.path)"
    }

    var projectRoot: URL? { manifestURL?.deletingLastPathComponent() }

    var illustrationBriefsURL: URL? {
        projectRoot?.appendingPathComponent("editorial/imagegen-illustration-briefs.json")
    }

    var illustrationContactSheetURL: URL? {
        projectRoot?.appendingPathComponent("reports/illustration-review/contact-sheet.png")
    }

    var publicationProofURL: URL? {
        projectRoot?.appendingPathComponent("reports/publication-proof/all-pages-contact-sheet.png")
    }

    var lockfileURL: URL? { projectRoot?.appendingPathComponent("novel.lock.json") }

    var catalogDashboardURL: URL? { catalogRoot?.appendingPathComponent("catalog-status.md") }

    var canCreateProject: Bool {
        frameworkRoot != nil
            && newProjectParent != nil
            && Self.isValidSlug(
                newProjectSlug.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            && !newProjectTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && newProjectTargetWords >= 1_000
            && !isRunning
    }

    private static func isValidSlug(_ slug: String) -> Bool {
        slug.range(
            of: #"^[a-z0-9]+(?:-[a-z0-9]+)*$"#,
            options: .regularExpression
        ) != nil
    }

    func configureFramework(at url: URL, remember: Bool = true) throws {
        let resolution = try StoryForgeCLIResolution.resolve(root: url)
        cli = resolution
        frameworkRoot = resolution.root
        if remember { defaults.set(resolution.root.path, forKey: Self.frameworkDefaultsKey) }
        if catalogRoot == nil {
            let novels = resolution.root.appendingPathComponent("novels", isDirectory: true)
            if FileManager.default.fileExists(atPath: novels.path) {
                setCatalogRoot(novels)
            }
        }
        issue = nil
    }

    func setCatalogRoot(_ url: URL) {
        let root = url.standardizedFileURL.resolvingSymlinksInPath()
        catalogRoot = root
        newProjectParent = root
        defaults.set(root.path, forKey: Self.catalogDefaultsKey)
        reloadCatalogStatusFromDisk()
    }

    func openProject(at url: URL) throws {
        let manifest: URL
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            manifest = url.appendingPathComponent("novel.json")
        } else {
            manifest = url
        }
        let summary = try StoryForgeManifestSummary.load(from: manifest)
        manifestURL = manifest.standardizedFileURL.resolvingSymlinksInPath()
        projectSummary = summary
        selectedStage = summary.stage
        defaults.set(manifestURL?.path, forKey: Self.projectDefaultsKey)
        let parent = manifest.deletingLastPathComponent().deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: parent.path) { setCatalogRoot(parent) }
        lastReport = nil
        lastOperationTitle = ""
        lastOperationSucceeded = nil
        issue = nil
    }

    func refreshProject() {
        guard let manifestURL else { return }
        do {
            projectSummary = try StoryForgeManifestSummary.load(from: manifestURL)
        } catch {
            issue = error.localizedDescription
        }
    }

    func createProject() {
        guard let destination = newProjectParent else {
            issue = "Choose a catalog folder for the new novel."
            return
        }
        let slug = newProjectSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = newProjectTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canCreateProject else {
            issue = "Use lowercase letters, digits, and single hyphens for the project name, then enter a title, destination, and target of at least 1,000 words."
            return
        }
        let command = StoryForgeCommand.createProject(
            slug: slug,
            title: title,
            destination: destination,
            format: newProjectFormat,
            targetWords: newProjectTargetWords,
            genre: newProjectGenre
        )
        start(command, title: "Create Novel") { [weak self] _ in
            guard let self else { return }
            try self.openProject(
                at: destination.appendingPathComponent(slug, isDirectory: true)
            )
            self.newProjectSlug = ""
            self.newProjectTitle = ""
            self.selectedSection = .overview
        }
    }

    func migrateManifest(at manifest: URL) {
        start(.migrate(manifest: manifest, output: nil), title: "Migrate to Schema v3") { _ in }
    }

    func runStageGate() {
        guard let manifestURL else {
            issue = "Open a novel project first."
            return
        }
        let report = temporaryReportURL("stage-gate")
        start(
            .validate(manifest: manifestURL, stage: selectedStage, report: report),
            title: "\(selectedStage.title) Gate",
            qualityResult: true
        ) { [weak self] _ in
            guard let self else { return }
            defer {
                try? FileManager.default.removeItem(
                    at: report.deletingLastPathComponent()
                )
            }
            self.lastReport = try StoryForgeReportSummary.decode(Data(contentsOf: report))
            self.lastOperationSucceeded = self.lastReport?.ok
            self.refreshProject()
        }
    }

    func runReport(_ kind: StoryForgeReportKind) {
        guard let manifestURL, let projectRoot else {
            issue = "Open a novel project first."
            return
        }
        let output = projectRoot.appendingPathComponent("reports/\(kind.reportFilename)")
        start(
            .report(kind: kind, manifest: manifestURL, output: output),
            title: kind.title,
            qualityResult: true
        ) { [weak self] _ in
            guard let self else { return }
            self.lastReport = try StoryForgeReportSummary.decode(Data(contentsOf: output))
            self.lastOperationSucceeded = self.lastReport?.ok
            self.refreshProject()
        }
    }

    func runEditorialSuite() {
        guard let manifestURL, let projectRoot else {
            issue = "Open a novel project first."
            return
        }
        let commands = StoryForgeReportKind.allCases.map { kind in
            (
                kind,
                StoryForgeCommand.report(
                    kind: kind,
                    manifest: manifestURL,
                    output: projectRoot.appendingPathComponent("reports/\(kind.reportFilename)")
                )
            )
        }
        startSequence(commands, title: "Complete Editorial Suite")
    }

    func makeIllustrationBriefs() {
        guard let manifestURL else { issue = "Open a novel project first."; return }
        start(.illustrationBriefs(manifest: manifestURL), title: "ImageGen Briefs", qualityResult: true) { [weak self] _ in
            guard let self, let illustrationBriefsURL else { return }
            self.lastReport = try StoryForgeReportSummary.decode(
                Data(contentsOf: illustrationBriefsURL)
            )
            self.lastOperationSucceeded = self.lastReport?.ok
        }
    }

    func reviewIllustrations() {
        guard let manifestURL, let projectRoot else {
            issue = "Open a novel project first."
            return
        }
        let report = projectRoot.appendingPathComponent("reports/illustration-set-review.json")
        start(.illustrationReview(manifest: manifestURL), title: "Illustration Set Review", qualityResult: true) { [weak self] _ in
            guard let self else { return }
            self.lastReport = try StoryForgeReportSummary.decode(Data(contentsOf: report))
            self.lastOperationSucceeded = self.lastReport?.ok
            self.refreshProject()
        }
    }

    func writeLockfile() {
        guard let manifestURL else { issue = "Open a novel project first."; return }
        start(.lock(manifest: manifestURL, check: false), title: "Freeze Project") { [weak self] _ in
            self?.refreshProject()
        }
    }

    func checkLockfile() {
        guard let manifestURL else { issue = "Open a novel project first."; return }
        start(.lock(manifest: manifestURL, check: true), title: "Check Project Lock", qualityResult: true) { _ in }
    }

    func runCatalogStatus() {
        guard let catalogRoot else { issue = "Choose the novels catalog first."; return }
        let report = catalogRoot.appendingPathComponent("catalog-status.json")
        let markdown = catalogRoot.appendingPathComponent("catalog-status.md")
        start(
            .catalogStatus(root: catalogRoot, report: report, markdown: markdown),
            title: "Catalog Status",
            qualityResult: true
        ) { [weak self] _ in
            guard let self else { return }
            self.catalogStatus = try StoryForgeCatalogStatus.decode(Data(contentsOf: report))
            self.lastOperationSucceeded = self.catalogStatus?.ok
        }
    }

    func runCatalogAudit(strict: Bool = false) {
        guard let catalogRoot else { issue = "Choose the novels catalog first."; return }
        let output = catalogRoot.appendingPathComponent("catalog-originality-report.json")
        start(
            .catalogAudit(root: catalogRoot, output: output, strict: strict),
            title: strict ? "Strict Originality Audit" : "Originality Audit",
            qualityResult: true
        ) { [weak self] _ in
            guard let self else { return }
            self.lastReport = try StoryForgeReportSummary.decode(Data(contentsOf: output))
            self.lastOperationSucceeded = self.lastReport?.ok
        }
    }

    func buildSeriesBible() {
        guard let catalogRoot else { issue = "Choose the novels catalog first."; return }
        let output = catalogRoot.appendingPathComponent("series-bible.json")
        start(.seriesBible(root: catalogRoot, output: output), title: "Series Bible", qualityResult: true) { [weak self] _ in
            guard let self else { return }
            self.lastReport = try StoryForgeReportSummary.decode(Data(contentsOf: output))
            self.lastOperationSucceeded = self.lastReport?.ok
        }
    }

    func buildPublication() {
        guard let manifestURL else { issue = "Open a novel project first."; return }
        start(.buildRelease(manifest: manifestURL), title: "Build EPUB & PDF") { [weak self] _ in
            self?.refreshProject()
        }
    }

    func cancel() { commandTask?.cancel() }

    func clearDiagnostics() { diagnostics = "" }

    private func reloadCatalogStatusFromDisk() {
        guard let url = catalogRoot?.appendingPathComponent("catalog-status.json"),
              let data = try? Data(contentsOf: url) else {
            catalogStatus = nil
            return
        }
        catalogStatus = try? StoryForgeCatalogStatus.decode(data)
    }

    private func start(
        _ command: StoryForgeCommand,
        title: String,
        qualityResult: Bool = false,
        onComplete: @escaping @MainActor (SwanSDKCommandResult) throws -> Void
    ) {
        guard let cli else {
            issue = "Choose the Story Forge repository first."
            return
        }
        guard !isRunning else {
            issue = "Another Story Forge task is still running."
            return
        }
        issue = nil
        lastReport = nil
        lastOperationTitle = title
        lastOperationSucceeded = nil
        activeCommandName = title
        isRunning = true
        diagnosticsAreVisible = true
        let invocation = cli.invocation(for: command)
        appendDiagnostic("\n› \(([invocation.executableURL.lastPathComponent] + invocation.arguments).joined(separator: " "))\n")
        commandTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await runner.run(
                    invocation,
                    onOutput: { [weak self] _, text in
                        Task { @MainActor [weak self] in self?.appendDiagnostic(text) }
                    }
                )
                try onComplete(result)
                if lastOperationSucceeded == nil { lastOperationSucceeded = result.succeeded }
                if !result.succeeded && !qualityResult {
                    let detail = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
                    issue = "\(title) could not finish. \(detail)"
                }
                let operationSucceeded = lastOperationSucceeded ?? result.succeeded
                completionNotifier(
                    SwanSongTaskCompletion(
                        name: title,
                        result: operationSucceeded ? .succeeded : .failed
                    )
                )
            } catch is CancellationError {
                appendDiagnostic("Task cancelled.\n")
                lastOperationSucceeded = false
            } catch {
                issue = error.localizedDescription
                appendDiagnostic("\(error.localizedDescription)\n")
                lastOperationSucceeded = false
                completionNotifier(SwanSongTaskCompletion(name: title, result: .failed))
            }
            activeCommandName = nil
            isRunning = false
            commandTask = nil
        }
    }

    private func startSequence(
        _ commands: [(StoryForgeReportKind, StoryForgeCommand)],
        title: String
    ) {
        guard let cli else { issue = "Choose the Story Forge repository first."; return }
        guard !isRunning else { issue = "Another Story Forge task is still running."; return }
        issue = nil
        lastReport = nil
        lastOperationTitle = title
        lastOperationSucceeded = nil
        activeCommandName = title
        isRunning = true
        diagnosticsAreVisible = true
        commandTask = Task { [weak self] in
            guard let self else { return }
            var errors: [String] = []
            var warnings: [String] = []
            var allPassed = true
            do {
                for (kind, command) in commands {
                    try Task.checkCancellation()
                    let invocation = cli.invocation(for: command)
                    appendDiagnostic("\n› \(kind.title)\n")
                    let result = try await runner.run(
                        invocation,
                        onOutput: { [weak self] _, text in
                            Task { @MainActor [weak self] in self?.appendDiagnostic(text) }
                        }
                    )
                    allPassed = allPassed && result.succeeded
                    if let projectRoot,
                       let report = try? StoryForgeReportSummary.decode(
                           Data(
                               contentsOf: projectRoot.appendingPathComponent(
                                   "reports/\(kind.reportFilename)"
                               )
                           )
                       ) {
                        errors += report.errors.map { "\(kind.title): \($0)" }
                        warnings += report.warnings.map { "\(kind.title): \($0)" }
                    }
                }
                lastReport = StoryForgeReportSummary(
                    ok: allPassed && errors.isEmpty,
                    errors: errors,
                    warnings: warnings
                )
                lastOperationSucceeded = lastReport?.ok
                refreshProject()
                completionNotifier(
                    SwanSongTaskCompletion(
                        name: title,
                        result: lastOperationSucceeded == true ? .succeeded : .failed
                    )
                )
            } catch is CancellationError {
                appendDiagnostic("Task cancelled.\n")
                lastOperationSucceeded = false
            } catch {
                issue = error.localizedDescription
                appendDiagnostic("\(error.localizedDescription)\n")
                lastOperationSucceeded = false
                completionNotifier(SwanSongTaskCompletion(name: title, result: .failed))
            }
            activeCommandName = nil
            isRunning = false
            commandTask = nil
        }
    }

    private func temporaryReportURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SwanSong-StoryForge-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("\(name).json")
    }

    private func appendDiagnostic(_ text: String) {
        guard !text.isEmpty else { return }
        diagnostics += text
    }
}
