import AppKit
import SwiftUI
import SwanSongKit

struct RewindTimeRibbonView: View {
    @Bindable var model: AppModel

    var body: some View {
        RewindTimeRibbonContent(
            checkpoints: model.rewindCheckpoints,
            selectedID: Binding(
                get: { model.selectedRewindCheckpointID },
                set: { id in
                    guard let id else { return }
                    model.selectRewindCheckpoint(id)
                }
            ),
            isBusy: model.playerStateOperation == .rewinding,
            canResume: model.canResumeSelectedRewindCheckpoint,
            onCancel: model.dismissRewind,
            onResume: model.resumeFromSelectedRewindCheckpoint
        )
    }
}

@MainActor
final class RewindTimeRibbonGeometryProbe {
    static let coordinateSpace = "rewind-time-ribbon-viewport"

    private(set) var viewportFrame = CGRect.zero
    private(set) var elementFrames: [String: CGRect] = [:]
    private(set) var usesVerticalFallback = false

    func recordViewport(_ frame: CGRect) {
        viewportFrame = frame
    }

    func recordElement(identifier: String, frame: CGRect) {
        elementFrames[identifier] = frame
    }

    func recordVerticalFallback() {
        usesVerticalFallback = true
    }
}

private struct RewindTimeRibbonViewportGeometryReader: View {
    let probe: RewindTimeRibbonGeometryProbe?

    var body: some View {
        GeometryReader { proxy in
            let frame = CGRect(origin: .zero, size: proxy.size)
            Color.clear
                .onAppear { probe?.recordViewport(frame) }
                .onChange(of: frame) { _, value in probe?.recordViewport(value) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct RewindTimeRibbonElementGeometryReader: View {
    let identifier: String
    let probe: RewindTimeRibbonGeometryProbe?

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(
                in: .named(RewindTimeRibbonGeometryProbe.coordinateSpace)
            )
            Color.clear
                .onAppear { probe?.recordElement(identifier: identifier, frame: frame) }
                .onChange(of: frame) { _, value in
                    probe?.recordElement(identifier: identifier, frame: value)
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct RewindTimeRibbonContent: View {
    static let accessibilityIdentifier = "rewind-time-ribbon"
    static let minimumInteractiveDimension: CGFloat = 28

    let checkpoints: [RewindCheckpoint]
    @Binding var selectedID: RewindCheckpoint.ID?
    let isBusy: Bool
    let canResume: Bool
    let onCancel: () -> Void
    let onResume: () -> Void
    var geometryProbe: RewindTimeRibbonGeometryProbe? = nil

    private var selected: RewindCheckpoint? {
        checkpoints.first { $0.id == selectedID } ?? checkpoints.last
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            ViewThatFits(in: .vertical) {
                ribbonBody(isCompact: false)
                ribbonBody(isCompact: true)
                ScrollView(.vertical) {
                    ribbonBody(isCompact: true)
                }
                .scrollIndicators(.visible)
                .onAppear { geometryProbe?.recordVerticalFallback() }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(24)
        .frame(minWidth: 760, idealWidth: 900, minHeight: 500)
        .background(.regularMaterial)
        .coordinateSpace(name: RewindTimeRibbonGeometryProbe.coordinateSpace)
        .background(RewindTimeRibbonViewportGeometryReader(probe: geometryProbe))
        .accessibilityIdentifier(Self.accessibilityIdentifier)
        .accessibilityElement(children: .contain)
    }

    private func ribbonBody(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: isCompact ? 10 : 16) {
            selectedMoment(isCompact: isCompact)
            timeline
            footer
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [SwanTheme.violet.opacity(0.88), SwanTheme.cyan.opacity(0.82)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "gobackward")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 48, height: 48)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Time Ribbon")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Choose one recent moment, then continue from there.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label(
                retainedDurationLabel,
                systemImage: "memorychip"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.06), in: Capsule())

            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
                .frame(minHeight: Self.minimumInteractiveDimension)
                .contentShape(Rectangle())
                .disabled(isBusy)
        }
    }

    @ViewBuilder
    private func selectedMoment(isCompact: Bool) -> some View {
        if isCompact {
            HStack(alignment: .center, spacing: 16) {
                selectedPreview
                    .frame(width: 270, height: 190)
                selectedDetails(isCompact: true)
                    .frame(minWidth: 260, maxWidth: 360, alignment: .leading)
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 18) {
                    selectedPreview
                        .frame(width: 400, height: 270)
                    selectedDetails(isCompact: false)
                        .frame(
                            minWidth: 210,
                            idealWidth: 250,
                            maxWidth: 300,
                            alignment: .leading
                        )
                }

                VStack(alignment: .leading, spacing: 14) {
                    selectedPreview
                        .frame(maxWidth: .infinity)
                        .frame(height: 230)
                    selectedDetails(isCompact: false)
                }
            }
        }
    }

    private var selectedPreview: some View {
        ZStack {
            Color.black
            if let selected {
                RewindFrameImage(frame: selected.previewFrame)
                    .aspectRatio(
                        CGFloat(selected.previewFrame.width)
                            / CGFloat(selected.previewFrame.height),
                        contentMode: .fit
                    )
            } else {
                ContentUnavailableView(
                    "No Recent Moments",
                    systemImage: "gobackward",
                    description: Text("Keep playing briefly to build an in-memory rewind history.")
                )
                .foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(SwanTheme.cyan.opacity(0.34), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(selectedPreviewAccessibilityLabel)
        .background(
            RewindTimeRibbonElementGeometryReader(
                identifier: "rewind-preview",
                probe: geometryProbe
            )
        )
    }

    private func selectedDetails(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: isCompact ? 8 : 12) {
            if let selected {
                Text(secondsBackLabel(for: selected))
                    .font(
                        .system(
                            isCompact ? .title2 : .title,
                            design: .rounded,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(SwanTheme.cyan)
                    .monospacedDigit()
                LabeledContent("Frame", value: selected.frameNumber.formatted())
                LabeledContent(
                    "Memory",
                    value: ByteCountFormatter.string(
                        fromByteCount: Int64(selected.payloadByteCount),
                        countStyle: .memory
                    )
                )
                .foregroundStyle(.secondary)
                Text(
                    isCompact
                        ? "Preview only. SwanSong restores this moment after you choose Resume Here."
                        : "Moving through the ribbon only previews moments. SwanSong restores the emulator once, after you choose Resume Here."
                )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button(action: onResume) {
                if isBusy {
                    Label("Rewinding…", systemImage: "clock.arrow.circlepath")
                } else {
                    Label("Resume Here", systemImage: "play.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(minHeight: Self.minimumInteractiveDimension)
            .disabled(!canResume || isBusy)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("rewind-resume")
            .accessibilityHint("Restores this in-memory checkpoint once and discards newer rewind history. Undo will be available.")
            .background(
                RewindTimeRibbonElementGeometryReader(
                    identifier: "rewind-resume",
                    probe: geometryProbe
                )
            )

            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Restoring the selected rewind checkpoint")
            }
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent moments")
                    .font(.headline)
                Spacer()
                Text("Older")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Text("Now")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(checkpoints) { checkpoint in
                            rewindMomentButton(checkpoint)
                                .id(checkpoint.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.visible)
                .onAppear {
                    if let selectedID {
                        proxy.scrollTo(selectedID, anchor: .center)
                    }
                }
                .onChange(of: selectedID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.16)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
            .frame(height: 104)
        }
    }

    private func rewindMomentButton(_ checkpoint: RewindCheckpoint) -> some View {
        let isSelected = checkpoint.id == selectedID
        return Button {
            selectedID = checkpoint.id
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    Color.black
                    RewindFrameImage(frame: checkpoint.previewFrame)
                        .aspectRatio(
                            CGFloat(checkpoint.previewFrame.width)
                                / CGFloat(checkpoint.previewFrame.height),
                            contentMode: .fit
                        )
                }
                .frame(width: 126, height: 72)
                .clipped()
                Text(shortSecondsBackLabel(for: checkpoint))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(isSelected ? SwanTheme.cyan : Color.secondary)
            }
            .padding(5)
            .background(
                isSelected ? SwanTheme.cyan.opacity(0.12) : Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(
                        isSelected ? SwanTheme.cyan : Color.primary.opacity(0.10),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel(
            "Rewind checkpoint, \(secondsBackLabel(for: checkpoint)), frame \(checkpoint.frameNumber)"
        )
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityIdentifier("rewind-checkpoint-\(checkpoint.id)")
        .background(
            RewindTimeRibbonElementGeometryReader(
                identifier: "rewind-checkpoint-\(checkpoint.id)",
                probe: geometryProbe
            )
        )
    }

    private var footer: some View {
        Label(
            "Memory-only: nothing in the ribbon is written to disk. Resuming from the past discards the newer in-memory branch; Undo restores the moment you left.",
            systemImage: "lock.shield"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RewindTimeRibbonElementGeometryReader(
                identifier: "rewind-footer",
                probe: geometryProbe
            )
        )
    }

    private var retainedDurationLabel: String {
        guard checkpoints.count > 1 else { return "Building history" }
        return String(
            format: "%.1f sec · %d moments",
            duration(checkpoints.first!, checkpoints.last!),
            checkpoints.count
        )
    }

    private var selectedPreviewAccessibilityLabel: String {
        guard let selected else { return "No rewind preview available" }
        return "Selected rewind preview, \(secondsBackLabel(for: selected)), frame \(selected.frameNumber)"
    }

    private func secondsBackLabel(for checkpoint: RewindCheckpoint) -> String {
        let seconds = secondsBack(for: checkpoint)
        return seconds < 0.05
            ? "Now"
            : String(format: "%.1f seconds ago", seconds)
    }

    private func shortSecondsBackLabel(for checkpoint: RewindCheckpoint) -> String {
        let seconds = secondsBack(for: checkpoint)
        return seconds < 0.05 ? "Now" : String(format: "−%.1fs", seconds)
    }

    private func secondsBack(for checkpoint: RewindCheckpoint) -> TimeInterval {
        guard let newest = checkpoints.last,
              newest.frameNumber >= checkpoint.frameNumber else { return 0 }
        return duration(checkpoint, newest)
    }

    private func duration(
        _ older: RewindCheckpoint,
        _ newer: RewindCheckpoint
    ) -> TimeInterval {
        Double(newer.frameNumber - older.frameNumber)
            / RewindBufferConfiguration.standard.nominalFramesPerSecond
    }
}

private struct RewindFrameImage: View {
    let image: NSImage?

    init(frame: EngineVideoFrame) {
        image = (try? ScreenshotExporter.pngData(for: frame)).flatMap(NSImage.init(data:))
    }

    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.none)
                .accessibilityHidden(true)
        } else {
            Color.black
                .overlay {
                    Image(systemName: "photo.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                }
                .accessibilityHidden(true)
        }
    }
}
