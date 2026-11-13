// Video Export Sheet — Progress & Completion
//
// Progress view shown during video rendering, and completion view shown after.

import AVFoundation
import CoreMedia
import SwiftUI

// MARK: - Progress

extension VideoExportSheet {
    var progressContent: some View {
        VStack(spacing: 24) {
            Spacer()
            thumbnailPreview
            progressInfo
            Spacer()
        }
    }

    private var thumbnailPreview: some View {
        Group {
            if let img = thumbnailImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.quaternary)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .overlay { ProgressView() }
            }
        }
        .padding(.horizontal, 32)
    }

    private var progressInfo: some View {
        Group {
            if progress == nil {
                Text("Preparing session data…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let prog = progress {
                VStack(spacing: 8) {
                    ProgressView(
                        value: Double(prog.framesCompleted),
                        total: Double(max(prog.totalFrames, 1))
                    )
                    HStack {
                        Text("Frame \(prog.framesCompleted) / \(prog.totalFrames)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let remaining = prog.estimatedSecondsRemaining {
                            Text(formatRemaining(remaining))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 32)
            }
        }
    }

    func formatRemaining(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if mins > 0 {
            return "\(mins)m \(secs)s remaining"
        }
        return "\(secs)s remaining"
    }
}

// MARK: - Completion

extension VideoExportSheet {
    var completionContent: some View {
        VStack(spacing: 24) {
            Spacer()

            thumbnailPreview

            // Success header
            Label("Export Complete", systemImage: "checkmark.circle.fill")
                .font(.title2.bold())
                .foregroundStyle(.green)

            // Metadata
            if let url = exportedFileURL {
                videoMetadataView(url: url)
            }

            // Share button
            if let url = exportedFileURL {
                Button {
                    presentShareSheet(url: url)
                } label: {
                    Label("Share Video", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 32)
            }

            Spacer()
        }
    }

    private func videoMetadataView(url: URL) -> some View {
        let fileSize = formatFileSize(url: url)

        return VStack(spacing: 4) {
            if let duration = videoDuration {
                Text(duration)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(fileSize)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .task {
            videoDuration = await formatVideoDuration(url: url)
        }
    }

    private func formatFileSize(url: URL) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64
        else {
            return "Unknown size"
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    private func formatVideoDuration(url: URL) async -> String? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else {
            return nil
        }
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0 else {
            return nil
        }
        let total = Int(seconds)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
