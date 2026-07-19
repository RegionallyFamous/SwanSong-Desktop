import AppKit
import SwanSongKit
import SwiftUI
import UniformTypeIdentifiers

struct StoryForgeWorkspaceView: View {
    @State private var workspace: StoryForgeWorkspaceModel
    let openGameStudio: () -> Void

    init(workspace: StoryForgeWorkspaceModel, openGameStudio: @escaping () -> Void) {
        _workspace = State(initialValue: workspace)
        self.openGameStudio = openGameStudio
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            sectionPicker
            Divider()
            Group {
                if workspace.frameworkRoot == nil {
                    frameworkSetup
                } else {
                    content
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            diagnostics
        }
        .background(SwanTheme.libraryBackground.ignoresSafeArea())
        .navigationTitle("Story Forge")
        .toolbar {
            ToolbarItemGroup {
                Button("Choose Story Forge…", systemImage: "hammer.circle") {
                    chooseFramework()
                }
                .disabled(workspace.isRunning)
                Button("Choose Catalog…", systemImage: "books.vertical") {
                    chooseCatalog()
                }
                .disabled(workspace.frameworkRoot == nil || workspace.isRunning)
                Button("Open Novel…", systemImage: "book.pages") {
                    chooseProject()
                }
                .disabled(workspace.frameworkRoot == nil || workspace.isRunning)
                if let projectRoot = workspace.projectRoot {
                    Button("Show Novel in Finder", systemImage: "arrow.forward.square") {
                        NSWorkspace.shared.activateFileViewerSelecting([projectRoot])
                    }
                }
            }
        }
        .alert(
            "Story Forge",
            isPresented: Binding(
                get: { workspace.issue != nil },
                set: { if !$0 { workspace.issue = nil } }
            )
        ) {
            Button("OK", role: .cancel) { workspace.issue = nil }
        } message: {
            Text(workspace.issue ?? "")
        }
        .onChange(of: workspace.newProjectFormat) { _, format in
            switch format {
            case .shortLightNovel: workspace.newProjectTargetWords = 12_000
            case .novella: workspace.newProjectTargetWords = 25_000
            case .volume: workspace.newProjectTargetWords = 50_000
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "book.pages.fill")
                .font(.title2)
                .foregroundStyle(SwanTheme.violet)
            VStack(alignment: .leading, spacing: 3) {
                Text(workspace.projectSummary?.title ?? "Story Forge")
                    .font(.title2.bold())
                Text(
                    workspace.projectRoot?.path
                        ?? "Plan, draft, illustrate, polish, and publish novels with evidence-backed gates."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .textSelection(.enabled)
            }
            Spacer()
            if workspace.isRunning {
                ProgressView().controlSize(.small)
                Text("\(workspace.activeCommandName ?? "Working")…")
                    .font(.callout.weight(.medium))
                Button("Cancel", role: .cancel) { workspace.cancel() }
            } else if let summary = workspace.projectSummary {
                Label("\(summary.stage.title) project", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var sectionPicker: some View {
        Picker("Story Forge workspace", selection: $workspace.selectedSection) {
            ForEach(StoryForgeWorkspaceSection.allCases) { section in
                Label(section.rawValue, systemImage: section.symbol).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .disabled(workspace.isRunning)
        .accessibilityIdentifier("story-forge-sections")
    }

    @ViewBuilder
    private var content: some View {
        switch workspace.selectedSection {
        case .overview: overview
        case .editorial: projectRequired { editorial }
        case .artAndMusic: projectRequired { artAndMusic }
        case .catalog: catalog
        case .publication: projectRequired { publication }
        }
    }

    private var frameworkSetup: some View {
        VStack(spacing: 20) {
            SwanEmptyState(
                title: "Connect Story Forge",
                description: "Choose the Story Forge repository that contains the schema-v3 novel framework. SwanSong runs its reviewed tools through fixed, visible actions.",
                symbol: "book.pages",
                tint: SwanTheme.violet
            )
            Button("Choose Story Forge Folder…", action: chooseFramework)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .swanEmptyStateContainer(tint: SwanTheme.violet)
        .padding(40)
        .accessibilityIdentifier("story-forge-setup")
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let summary = workspace.projectSummary {
                    projectOverview(summary)
                } else {
                    sectionHeading(
                        "Start a Novel",
                        detail: "Create a schema-v3 project or open an existing novel.json. Human approvals remain human decisions; SwanSong never fills them in for you."
                    )
                    newProjectCard
                    StoryForgeCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Already writing?").font(.headline)
                                Text("Open a dependency-free Story Forge novel.json project.")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Open Novel…", action: chooseProject)
                        }
                    }
                }
                resultCard
            }
            .padding(22)
            .frame(maxWidth: 980, alignment: .leading)
        }
    }

    private func projectOverview(_ summary: StoryForgeManifestSummary) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeading(
                "Story Readiness",
                detail: "Check the declared stage against the exact manuscript, reports, continuity, rights, art, music, and publication evidence."
            )
            StoryForgeCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(summary.title).font(.title3.bold())
                            Text("Schema v\(summary.schemaVersion) · \(summary.slug)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(summary.stage.title)
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(SwanTheme.violet.opacity(0.14), in: Capsule())
                    }
                    stageRail
                    Divider()
                    HStack(spacing: 24) {
                        metric("Chapters", summary.chapterCount)
                        metric("Scenes", summary.sceneCount)
                        metric("Readers", summary.readerCount)
                        metric("Reports", summary.reportCount)
                        metric("Illustrations", summary.illustrationCount)
                    }
                    HStack {
                        Label("\(summary.rightsLane) · \(summary.releaseScope)", systemImage: "checkmark.shield")
                        Spacer()
                        Label(
                            summary.soundtrackEnabled ? "Soundtrack enabled" : "Soundtrack optional",
                            systemImage: summary.soundtrackEnabled ? "music.note.list" : "music.note"
                        )
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
            StoryForgeCard {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Run a stage gate").font(.headline)
                        Text("Later gates include every earlier gate. A score never substitutes for editorial judgment or reader approval.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Stage", selection: $workspace.selectedStage) {
                        ForEach(StoryForgeStage.allCases) { stage in Text(stage.title).tag(stage) }
                    }
                    .frame(width: 130)
                    Button("Check \(workspace.selectedStage.title)") { workspace.runStageGate() }
                        .buttonStyle(.borderedProminent)
                        .disabled(workspace.isRunning)
                }
            }
            StoryForgeCard {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("WonderSwan adaptation").font(.headline)
                        Text("Carry stable scene IDs, continuity, signature moments, ImageGen art rules, and soundtrack motifs into SwanSong Studio after revision.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Continue in Studio", systemImage: "hammer", action: openGameStudio)
                        .disabled(summary.stage == .concept || summary.stage == .outline || summary.stage == .draft)
                }
            }
        }
    }

    private var stageRail: some View {
        HStack(spacing: 8) {
            ForEach(StoryForgeStage.allCases) { stage in
                let reached = stageIndex(stage) <= stageIndex(workspace.projectSummary?.stage ?? .concept)
                VStack(spacing: 5) {
                    Image(systemName: reached ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(reached ? SwanTheme.violet : Color.secondary)
                    Text(stage.title).font(.caption2.weight(.medium))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Novel stages")
    }

    private var newProjectCard: some View {
        StoryForgeCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    TextField("lowercase-project-name", text: $workspace.newProjectSlug)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                    TextField("Novel title", text: $workspace.newProjectTitle)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Picker("Length", selection: $workspace.newProjectFormat) {
                        ForEach(StoryForgeBookFormat.allCases) { item in Text(item.title).tag(item) }
                    }
                    Picker("Genre profile", selection: $workspace.newProjectGenre) {
                        ForEach(StoryForgeGenreProfile.allCases) { item in Text(item.title).tag(item) }
                    }
                    TextField("Words", value: $workspace.newProjectTargetWords, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 105)
                }
                HStack {
                    Text(workspace.newProjectParent?.path ?? "Choose a catalog folder")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button("Choose Location…", action: chooseNewProjectParent)
                    Button("Create Novel") { workspace.createProject() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!workspace.canCreateProject)
                }
            }
        }
    }

    private var editorial: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sectionHeading(
                    "Editorial Desk",
                    detail: "Run distinct passes so voice, prose, momentum, scene delivery, continuity, reader disagreement, rights, and music cannot hide behind one average score."
                )
                StoryForgeCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Complete editorial suite").font(.headline)
                            Text("Refresh all eight manuscript-bound reports in one pass.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Run All Reports") { workspace.runEditorialSuite() }
                            .buttonStyle(.borderedProminent)
                            .disabled(workspace.isRunning)
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                    ForEach(StoryForgeReportKind.allCases) { kind in
                        Button { workspace.runReport(kind) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(kind.title, systemImage: reportSymbol(kind))
                                    .font(.headline)
                                Text(reportDescription(kind))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(3)
                            }
                            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                            .padding(14)
                            .background(.background.opacity(0.82), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .disabled(workspace.isRunning)
                    }
                }
                resultCard
            }
            .padding(22)
            .frame(maxWidth: 980, alignment: .leading)
        }
    }

    private var artAndMusic: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sectionHeading(
                    "Art & Music",
                    detail: "Turn approved story beats into coherent production briefs, then review the complete set and optional soundtrack as one experience."
                )
                StoryForgeCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Production art always starts in ImageGen", systemImage: "sparkles")
                            .font(.headline)
                        Text("SwanSong creates prompt briefs and verifies provenance, hashes, eye line, continuity, artifacts, composition variety, and set approval. It never replaces missing art with programmatic pictures.")
                            .font(.callout).foregroundStyle(.secondary)
                        HStack {
                            Button("Create ImageGen Briefs") { workspace.makeIllustrationBriefs() }
                                .buttonStyle(.borderedProminent)
                            Button("Review Illustration Set") { workspace.reviewIllustrations() }
                            artifactButton("Open Briefs", url: workspace.illustrationBriefsURL)
                            artifactButton("Open Contact Sheet", url: workspace.illustrationContactSheetURL)
                        }
                        .disabled(workspace.isRunning)
                    }
                }
                StoryForgeCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Label("Fun, story-shaped music", systemImage: "music.note.list")
                                .font(.headline)
                            Text("Check motif transformations, memorable loop hooks, cue purpose, mono safety, and all four WonderSwan channel roles.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Check Soundtrack Bible") { workspace.runReport(.soundtrackBible) }
                            .disabled(workspace.isRunning)
                    }
                }
                resultCard
            }
            .padding(22)
            .frame(maxWidth: 980, alignment: .leading)
        }
    }

    private var catalog: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sectionHeading(
                    "Novel Catalog",
                    detail: "See every book’s real stage, stale evidence, originality risks, and next useful action without flattening different readers or stories into one score."
                )
                StoryForgeCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(workspace.catalogRoot?.path ?? "No catalog selected")
                                .font(.callout.monospaced()).lineLimit(1)
                            Text("Status is read-only analysis; the Markdown dashboard is written beside the catalog for the team.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Choose Catalog…", action: chooseCatalog)
                        Button("Refresh Status") { workspace.runCatalogStatus() }
                            .buttonStyle(.borderedProminent)
                            .disabled(workspace.catalogRoot == nil || workspace.isRunning)
                    }
                }
                if let status = workspace.catalogStatus {
                    StoryForgeCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label(
                                    status.ok ? "Catalog gates are current" : "Catalog needs attention",
                                    systemImage: status.ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                                )
                                .font(.headline)
                                .foregroundStyle(status.ok ? .green : .orange)
                                Spacer()
                                Text("\(status.novels.count) novels").font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(status.novels) { novel in
                                Divider()
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: novel.gate == "pass" ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                        .foregroundStyle(novel.gate == "pass" ? .green : .orange)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(novel.title).font(.body.weight(.semibold))
                                        Text("\(novel.stage.capitalized) · \(novel.words.formatted()) words · \(novel.scenes) scenes · \(novel.illustrations) art moments")
                                            .font(.caption).foregroundStyle(.secondary)
                                        Text(novel.nextAction).font(.caption)
                                    }
                                    Spacer()
                                    if novel.staleEvidence > 0 {
                                        Text("\(novel.staleEvidence) stale")
                                            .font(.caption.bold()).foregroundStyle(.orange)
                                    }
                                }
                            }
                        }
                    }
                }
                StoryForgeCard {
                    HStack {
                        Button("Originality Audit") { workspace.runCatalogAudit() }
                        Button("Strict Originality Audit") { workspace.runCatalogAudit(strict: true) }
                        Button("Build Series Bible") { workspace.buildSeriesBible() }
                        Spacer()
                        artifactButton("Open Dashboard", url: workspace.catalogDashboardURL)
                    }
                    .disabled(workspace.catalogRoot == nil || workspace.isRunning)
                }
                resultCard
            }
            .padding(22)
            .frame(maxWidth: 980, alignment: .leading)
        }
    }

    private var publication: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sectionHeading(
                    "Publication",
                    detail: "Freeze exact evidence, build deterministic EPUB and PDF editions, and inspect accessibility, text parity, embedded fonts, and every rendered page."
                )
                StoryForgeCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Rights lane", systemImage: "checkmark.shield")
                            .font(.headline)
                        Text("\(workspace.projectSummary?.rightsLane ?? "unreviewed") · \(workspace.projectSummary?.releaseScope ?? "unreviewed")")
                            .font(.title3.weight(.semibold))
                        Text("Fan work cannot pass as commercial clearance. Licensed commercial releases require recorded approval. SwanSong preserves the decision trail; it does not provide legal advice.")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("Check Rights & Release") { workspace.runReport(.rightsRelease) }
                            .disabled(workspace.isRunning)
                    }
                }
                StoryForgeCard {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Lock exact evidence").font(.headline)
                            Text("The lock binds manuscript, framework, reports, ImageGen art, music, and publication tools by hash.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Write Lockfile") { workspace.writeLockfile() }
                        Button("Check Lock") { workspace.checkLockfile() }
                        artifactButton("Show Lockfile", url: workspace.lockfileURL)
                    }
                    .disabled(workspace.isRunning)
                }
                StoryForgeCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("EPUB & PDF proof").font(.headline)
                                Text("External EPUBCheck runs when available and is mandatory when the project requires it. PDF proof covers every page, not a sample.")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Build EPUB & PDF") { workspace.buildPublication() }
                                .buttonStyle(.borderedProminent)
                                .disabled(workspace.isRunning)
                        }
                        HStack {
                            artifactButton("Open All-Page Proof", url: workspace.publicationProofURL)
                            if let output = workspace.projectRoot?.appendingPathComponent("output") {
                                artifactButton("Show Editions", url: output)
                            }
                        }
                    }
                }
                StoryForgeCard {
                    HStack {
                        Text("Older schema-v2 project?").font(.headline)
                        Text("Migration writes a new v3 manifest and leaves human decisions pending.")
                            .font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("Migrate Project…", action: chooseLegacyManifest)
                            .disabled(workspace.isRunning)
                    }
                }
                resultCard
            }
            .padding(22)
            .frame(maxWidth: 980, alignment: .leading)
        }
    }

    @ViewBuilder
    private func projectRequired<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if workspace.projectSummary == nil {
            ContentUnavailableView {
                Label("Open a Novel Project", systemImage: "book.pages")
            } description: {
                Text("This workspace needs a schema-v3 novel.json project.")
            } actions: {
                Button("Open Novel…", action: chooseProject).buttonStyle(.borderedProminent)
                Button("Go to Overview") { workspace.selectedSection = .overview }
            }
        } else {
            content()
        }
    }

    @ViewBuilder
    private var resultCard: some View {
        if !workspace.lastOperationTitle.isEmpty {
            StoryForgeCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        if workspace.isRunning {
                            ProgressView().controlSize(.small)
                            Text(workspace.lastOperationTitle).font(.headline)
                        } else {
                            Label(
                                workspace.lastOperationTitle,
                                systemImage: workspace.lastOperationSucceeded == true
                                    ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                            )
                            .font(.headline)
                            .foregroundStyle(workspace.lastOperationSucceeded == true ? .green : .orange)
                        }
                        Spacer()
                        if let report = workspace.lastReport {
                            Text("\(report.errors.count) issues · \(report.warnings.count) leads")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let report = workspace.lastReport {
                        ForEach(Array(report.errors.prefix(6).enumerated()), id: \.offset) { _, error in
                            Label(error, systemImage: "xmark.circle").font(.callout)
                        }
                        ForEach(Array(report.warnings.prefix(4).enumerated()), id: \.offset) { _, warning in
                            Label(warning, systemImage: "lightbulb").font(.callout)
                        }
                        if report.ok && report.warnings.isEmpty {
                            Text("The current evidence satisfies this automated gate. Human editorial and release approvals remain separate.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var diagnostics: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Button {
                    workspace.diagnosticsAreVisible.toggle()
                } label: {
                    Label("Task Details", systemImage: workspace.diagnosticsAreVisible ? "chevron.down" : "chevron.right")
                }
                .buttonStyle(.plain)
                Text(workspace.frameworkDescription)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button("Clear") { workspace.clearDiagnostics() }
                    .disabled(workspace.diagnostics.isEmpty)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 9)
            if workspace.diagnosticsAreVisible {
                ScrollView {
                    Text(workspace.diagnostics.isEmpty ? "Story Forge task details will appear here." : workspace.diagnostics)
                        .font(.caption.monospaced())
                        .foregroundStyle(workspace.diagnostics.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(height: 110)
                .background(.black.opacity(0.035))
            }
        }
    }

    private func sectionHeading(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.largeTitle.bold())
            Text(detail).font(.callout).foregroundStyle(.secondary)
        }
    }

    private func metric(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.formatted()).font(.title3.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func artifactButton(_ title: String, url: URL?) -> some View {
        Button(title) {
            guard let url else { return }
            if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.open(url) }
        }
        .disabled(url.map { !FileManager.default.fileExists(atPath: $0.path) } ?? true)
    }

    private func stageIndex(_ stage: StoryForgeStage) -> Int {
        StoryForgeStage.allCases.firstIndex(of: stage) ?? 0
    }

    private func reportSymbol(_ kind: StoryForgeReportKind) -> String {
        switch kind {
        case .characterVoice: "person.wave.2"
        case .prosePolish: "text.badge.checkmark"
        case .chapterMomentum: "chart.line.uptrend.xyaxis"
        case .sceneDelivery: "target"
        case .continuity: "point.3.connected.trianglepath.dotted"
        case .readerSynthesis: "person.2"
        case .rightsRelease: "checkmark.shield"
        case .soundtrackBible: "music.note.list"
        }
    }

    private func reportDescription(_ kind: StoryForgeReportKind) -> String {
        switch kind {
        case .characterVoice: "Compare marked voice samples without rewriting everyone into one style."
        case .prosePolish: "Expose repetition, clichés, filter phrases, openings, and rhythm leads."
        case .chapterMomentum: "Check hooks, pulls, emotional rhythm, and signature moments."
        case .sceneDelivery: "Prove each drafted scene delivers its planned turn and consequence."
        case .continuity: "Resolve typed time, object, promise, knowledge, and relationship states."
        case .readerSynthesis: "Preserve consensus and meaningful disagreement without averaging taste."
        case .rightsRelease: "Verify original, fan-work, or licensed release boundaries."
        case .soundtrackBible: "Check motifs, fun loop hooks, cues, channels, and mono safety."
        }
    }

    private func chooseFramework() {
        chooseDirectory(prompt: "Choose Story Forge") { url in
            do { try workspace.configureFramework(at: url) }
            catch { workspace.issue = error.localizedDescription }
        }
    }

    private func chooseCatalog() {
        chooseDirectory(prompt: "Choose Novel Catalog") { workspace.setCatalogRoot($0) }
    }

    private func chooseNewProjectParent() {
        chooseDirectory(prompt: "Choose Novel Catalog") { workspace.setCatalogRoot($0) }
    }

    private func chooseProject() {
        let panel = NSOpenPanel()
        panel.title = "Open Story Forge Novel"
        panel.prompt = "Open Novel"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try workspace.openProject(at: url) }
        catch { workspace.issue = error.localizedDescription }
    }

    private func chooseLegacyManifest() {
        let panel = NSOpenPanel()
        panel.title = "Choose Schema-v2 Novel"
        panel.prompt = "Migrate"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        workspace.migrateManifest(at: url)
    }

    private func chooseDirectory(prompt: String, completion: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = prompt
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        completion(url)
    }
}

private struct StoryForgeCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.background.opacity(0.86), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.primary.opacity(0.08), lineWidth: 1)
            }
    }
}
