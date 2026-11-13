import CarrierWaveData
import SwiftUI

// MARK: - WhatsNewSheet

/// Modal sheet shown in CW Sweep on first launch after an update. Presents
/// release notes the user hasn't yet acknowledged, grouped by version.
struct WhatsNewSheet: View {
    // MARK: Internal

    let entries: [WhatsNewEntry]
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(entries) { entry in
                        WhatsNewEntryCard(entry: entry)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") { onDismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 480, idealHeight: 640)
    }

    // MARK: Private

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 32))
                .foregroundStyle(.blue)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("What's New in CW Sweep")
                    .font(.title2.weight(.bold))
                Text("Here's what changed since you last opened the app.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

// MARK: - WhatsNewEntryCard

private struct WhatsNewEntryCard: View {
    let entry: WhatsNewEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.headline)
                        .font(.headline)
                    Text(entry.date, format: .dateTime.month(.abbreviated).day().year())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("v\(entry.version)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(entry.items) { item in
                    WhatsNewItemRow(item: item)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - WhatsNewItemRow

private struct WhatsNewItemRow: View {
    // MARK: Internal

    let item: WhatsNewItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.kind.iconName)
                .font(.subheadline)
                .foregroundStyle(tint)
                .frame(width: 20, alignment: .center)
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.kind.label.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(tint)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                }
                if let detail = item.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Private

    private var tint: Color {
        switch item.kind {
        case .feature: .blue
        case .improvement: .green
        case .fix: .orange
        }
    }
}

#Preview {
    WhatsNewSheet(
        entries: WhatsNewCatalog.entries,
        onDismiss: {}
    )
}
