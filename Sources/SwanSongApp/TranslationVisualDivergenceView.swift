import AppKit
import SwiftUI
import SwanSongKit

private enum TranslationVisualDivergenceMode: String, CaseIterable, Identifiable {
    case sideBySide = "Side by Side"
    case overlay = "Overlay"
    case difference = "Difference"

    var id: Self { self }
}

struct TranslationVisualDivergenceView: View {
    static let accessibilityIdentifier = "translation-first-visual-change"
    static let minimumInteractiveDimension: CGFloat = 28

    @Bindable var model: AppModel
    @State private var mode: TranslationVisualDivergenceMode = .difference

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView(.vertical) {
                Group {
                    if model.translationVisualDivergenceIsRunning {
                        progressWorkspace
                    } else if let result = model.translationVisualDivergenceResult {
                        resultWorkspace(result)
                    } else {
                        issueWorkspace
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 430, alignment: .topLeading)
                .padding(22)
            }
            if case let .firstDifference(divergence)? = model.translationVisualDivergenceResult,
               !model.translationVisualDivergenceIsRunning {
                Divider()
                divergenceActionBar(divergence)
            }
        }
        .frame(minWidth: 760, idealWidth: 980, minHeight: 560, idealHeight: 700)
        .background(SwanTheme.libraryBackground)
        .accessibilityIdentifier(Self.accessibilityIdentifier)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(spacing: 14) {
            SwanIconTile(symbol: "scope", tint: SwanTheme.translationAccent, size: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text("First Visual Change")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Original and Patched replay from the same clean boot and inputs.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.translationVisualDivergenceIsRunning {
                Button("Cancel", action: model.cancelTranslationVisualDivergence)
                    .keyboardShortcut(.cancelAction)
                    .frame(minHeight: Self.minimumInteractiveDimension)
            } else {
                Button("Done", action: model.dismissTranslationVisualDivergence)
                    .keyboardShortcut(.cancelAction)
                    .frame(minHeight: Self.minimumInteractiveDimension)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(.bar)
    }

    private var progressWorkspace: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 36)
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.cyan.opacity(0.16), .purple.opacity(0.16)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "rectangle.2.swap")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            .frame(width: 88, height: 88)
            .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(model.translationVisualDivergenceProgress?.phase.title ?? "Preparing comparison…")
                    .font(.title3.weight(.semibold))
                Text(progressDetail)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: model.translationVisualDivergenceProgress?.fractionComplete ?? 0)
                .frame(maxWidth: 460)
                .tint(.cyan)
                .accessibilityLabel("First visual change comparison progress")
                .accessibilityValue(progressDetail)
            Label(
                "Only the first changed frame pair is retained. The Original lane must still reproduce the saved endpoint before a result is trusted.",
                systemImage: "checkmark.shield"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 560)
            Spacer(minLength: 36)
        }
        .frame(maxWidth: .infinity, minHeight: 430)
    }

    @ViewBuilder
    private func resultWorkspace(_ result: TranslationVisualDivergenceResult) -> some View {
        switch result {
        case let .firstDifference(divergence):
            divergenceWorkspace(divergence)
        case let .noDifference(noDifference):
            noDifferenceWorkspace(noDifference)
        }
    }

    private func divergenceWorkspace(_ divergence: TranslationVisualDivergence) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    divergenceIdentity(divergence)
                    Spacer(minLength: 16)
                    divergenceMetrics(divergence)
                }
                VStack(alignment: .leading, spacing: 12) {
                    divergenceIdentity(divergence)
                    divergenceMetrics(divergence)
                }
            }

            if divergence.visualization != nil {
                Picker("Comparison view", selection: $mode) {
                    ForEach(TranslationVisualDivergenceMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 390)
                .accessibilityIdentifier("first-visual-change-mode")
            }

            comparisonSurface(divergence)
                .frame(maxWidth: .infinity, minHeight: 260, maxHeight: 390)
        }
    }

    private func divergenceActionBar(_ divergence: TranslationVisualDivergence) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Label(
                "Private, memory-only comparison · frame \(divergence.frame.frameIndex + 1)",
                systemImage: "lock.shield"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
            Button("Create Test at This Frame", systemImage: "scope") {
                model.createTranslationTestAtFirstVisualChange()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(minHeight: Self.minimumInteractiveDimension)
            .accessibilityIdentifier("first-visual-change-create-test")
            .help("Save a new immutable route prefix ending at this exact Original frame")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func divergenceIdentity(_ divergence: TranslationVisualDivergence) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("First change at frame \(divergence.frame.frameIndex + 1)")
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
            Text(
                String(
                    format: "%.2f seconds from clean boot",
                    seconds(for: divergence.frame.frameIndex)
                )
            )
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            if let previous = divergence.previousIdenticalFrame {
                Label(
                    "Frame \(previous.frameIndex + 1) was still identical",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
            } else {
                Label("The very first frame differs", systemImage: "bolt.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
    }

    private func divergenceMetrics(_ divergence: TranslationVisualDivergence) -> some View {
        HStack(spacing: 9) {
            metricPill(
                title: "Kind",
                value: divergenceKindTitle(divergence.kind),
                symbol: "rectangle.2.swap"
            )
            if let difference = divergence.difference {
                metricPill(
                    title: "Pixels",
                    value: "\(difference.differentPixelCount.formatted()) · \((difference.differentPixelFraction * 100).formatted(.number.precision(.fractionLength(2))))%",
                    symbol: "square.grid.3x3.fill"
                )
                metricPill(
                    title: "Peak error",
                    value: difference.maximumChannelError.formatted(),
                    symbol: "waveform.path.ecg"
                )
            }
        }
    }

    @ViewBuilder
    private func comparisonSurface(_ divergence: TranslationVisualDivergence) -> some View {
        switch mode {
        case .sideBySide:
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    framePanel("Original", frame: divergence.frame.frames.original, color: .cyan)
                    framePanel("Patched", frame: divergence.frame.frames.patched, color: .purple)
                }
                VStack(spacing: 12) {
                    framePanel("Original", frame: divergence.frame.frames.original, color: .cyan)
                    framePanel("Patched", frame: divergence.frame.frames.patched, color: .purple)
                }
            }
        case .overlay:
            labeledRasterPanel("Overlay", color: .indigo) {
                ZStack {
                    frameImage(divergence.frame.frames.original)
                    frameImage(divergence.frame.frames.patched)
                        .opacity(0.5)
                }
            }
        case .difference:
            if let heatmap = heatmapFrame(divergence) {
                labeledRasterPanel("Difference Heatmap", color: .orange) {
                    frameImage(heatmap)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) {
                        framePanel("Original", frame: divergence.frame.frames.original, color: .cyan)
                        framePanel("Patched", frame: divergence.frame.frames.patched, color: .purple)
                    }
                    VStack(spacing: 12) {
                        framePanel("Original", frame: divergence.frame.frames.original, color: .cyan)
                        framePanel("Patched", frame: divergence.frame.frames.patched, color: .purple)
                    }
                }
            }
        }
    }

    private func noDifferenceWorkspace(_ noDifference: TranslationVisualNoDifference) -> some View {
        VStack(spacing: 18) {
            Spacer(minLength: 12)
            Image(systemName: "equal.circle.fill")
                .font(.system(size: 58, weight: .medium))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text("No visual difference on this route")
                    .font(.title2.weight(.semibold))
                Text(
                    "Original and Patched produced the same canonical game raster for all \(noDifference.framesCompared.formatted()) frames, and Original reproduced the saved endpoint."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 620)
            }
            framePanel(
                "Shared endpoint · frame \(noDifference.lastIdenticalFrame.frameIndex + 1)",
                frame: noDifference.lastIdenticalFrame.frames.original,
                color: .green
            )
            .frame(maxWidth: 560, minHeight: 230, maxHeight: 320)
            Label(
                "This proves only that this deterministic input route has no visible game-raster change. It does not rule out RAM, audio, timing, or unvisited-screen changes.",
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 660)
            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, minHeight: 430)
    }

    private var issueWorkspace: some View {
        ContentUnavailableView {
            Label("Comparison Unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(model.translationVisualDivergenceIssue ?? "The comparison did not produce a result.")
        } actions: {
            Button("Close", action: model.dismissTranslationVisualDivergence)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 430)
    }

    private func framePanel(_ title: String, frame: EngineVideoFrame, color: Color) -> some View {
        labeledRasterPanel(title, color: color) {
            frameImage(frame)
        }
    }

    private func labeledRasterPanel<Content: View>(
        _ title: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            ZStack {
                Color.black
                content()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                Rectangle().stroke(color.opacity(0.42), lineWidth: 1)
            }
        }
        .padding(10)
        .swanSurface(.standard, tint: color, cornerRadius: 12)
    }

    @ViewBuilder
    private func frameImage(_ frame: EngineVideoFrame) -> some View {
        if let data = try? EngineFramePNGCodec.encode(frame),
           let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.none)
                .aspectRatio(
                    CGFloat(frame.width) / CGFloat(frame.height),
                    contentMode: .fit
                )
                .accessibilityHidden(true)
        } else {
            Image(systemName: "photo.badge.exclamationmark")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Frame preview unavailable")
        }
    }

    private func heatmapFrame(_ divergence: TranslationVisualDivergence) -> EngineVideoFrame? {
        guard let visualization = divergence.visualization else { return nil }
        let width = divergence.originalRaster.width
        let height = divergence.originalRaster.height
        guard visualization.heatmapRGB888.count == width * height * 3 else { return nil }
        var bgra = Data(capacity: width * height * 4)
        visualization.heatmapRGB888.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for pixel in 0..<(width * height) {
                let offset = pixel * 3
                bgra.append(bytes[offset + 2])
                bgra.append(bytes[offset + 1])
                bgra.append(bytes[offset])
                bgra.append(255)
            }
        }
        return EngineVideoFrame(
            pixels: bgra,
            width: width,
            height: height,
            strideBytes: width * 4,
            isVertical: divergence.originalRaster.orientation == .vertical,
            number: divergence.frame.frameIndex + 1
        )
    }

    private func metricPill(title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: symbol)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .swanSurface(.recessed, tint: SwanTheme.translationAccent, cornerRadius: 9)
    }

    private var progressDetail: String {
        guard let progress = model.translationVisualDivergenceProgress else {
            return "Preparing clean-boot runners"
        }
        let base = "\(progress.phase.title) · Frame \(progress.framesProcessed.formatted()) of \(progress.totalFrames.formatted())"
        if let first = progress.firstDifferenceFrameIndex {
            return "\(base) · first change found at \(first + 1); validating endpoint"
        }
        return base
    }

    private func seconds(for frameIndex: UInt64) -> Double {
        Double(frameIndex + 1) / (4_000.0 / 53.0)
    }

    private func divergenceKindTitle(_ kind: TranslationVisualDivergenceKind) -> String {
        switch kind {
        case .pixels: "Pixels"
        case .dimensions: "Dimensions"
        case .orientation: "Orientation"
        case .dimensionsAndOrientation: "Size + Rotation"
        }
    }
}
