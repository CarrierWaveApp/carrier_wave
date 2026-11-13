import CarrierWaveData
import SwiftUI

// MARK: - WhatsNewSheet

/// Modal shown after a fresh install update presenting the user with the
/// release notes they haven't yet seen, grouped by version.
struct WhatsNewSheet: View {
    // MARK: Internal

    let entries: [WhatsNewEntry]
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    ForEach(entries) { entry in
                        WhatsNewEntryCard(entry: entry)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("What's New")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: Private

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 36))
                .foregroundStyle(.blue)
                .accessibilityHidden(true)
            Text("Carrier Wave got better.")
                .font(.title2.weight(.bold))
            Text("Here's what's new since you last opened the app.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    .background(Color(.systemGray5))
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
        .background(Color(.secondarySystemGroupedBackground))
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
                .frame(width: 24, alignment: .center)
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
                if let link = item.link {
                    Link(destination: link) {
                        HStack(spacing: 3) {
                            Text(item.linkLabel ?? "Learn more")
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(tint)
                    }
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

// MARK: - WhatsNewPresenter

private struct WhatsNewPresenter: ViewModifier {
    // MARK: Internal

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                WhatsNewSheet(entries: service.pendingEntries) {
                    service.markCurrentVersionSeen()
                    isPresented = false
                }
            }
            .task {
                // Defer one frame so first paint isn't blocked by the sheet.
                await Task.yield()
                if service.hasPendingEntries {
                    isPresented = true
                } else {
                    service.markFreshInstallIfNeeded()
                }
            }
    }

    // MARK: Private

    @State private var isPresented = false
    @State private var service = WhatsNewService(platform: .iOS)
}

extension View {
    func whatsNewPresenter() -> some View {
        modifier(WhatsNewPresenter())
    }
}
