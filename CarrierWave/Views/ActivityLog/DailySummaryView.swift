import SwiftData
import SwiftUI
import UIKit

// MARK: - DailySummaryView

/// Full day's activity with band timeline and complete QSO list.
/// Navigated to from "See All" in RecentQSOsSection.
struct DailySummaryView: View {
    // MARK: Internal

    let manager: ActivityLogManager

    @Environment(\.modelContext) var modelContext

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                dateHeader
                statsCard

                if !dayQSOs.isEmpty {
                    BandTimelineView(qsos: dayQSOs)
                    qsoList
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Daily Activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    shareButton
                    dayNavigationButtons
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let image = shareCardImage {
                ShareActivitySheet(image: image)
            }
        }
        .task {
            loadDayQSOs()
        }
        .onChange(of: selectedDate) {
            loadDayQSOs()
        }
    }

    // MARK: Private

    @State private var selectedDate = Date()
    @State private var dayQSOs: [QSO] = []
    @State private var showingShareSheet = false

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }

    private var shareCardImage: UIImage? {
        let callsign = manager.activeLog?.myCallsign ?? ""
        let bands = Set(dayQSOs.map(\.band))
        let modes = Set(dayQSOs.map(\.mode))
        let content = ShareCardContent.forDailyActivity(
            callsign: callsign,
            date: selectedDate,
            qsoCount: dayQSOs.count,
            bands: bands,
            modes: modes
        )
        return ShareCardRenderer.render(content: content)
    }

    private var dateHeader: some View {
        Text(dateFormatter.string(from: selectedDate))
            .font(.headline)
    }

    private var statsCard: some View {
        let bands = Set(dayQSOs.map(\.band))
        let modes = Set(dayQSOs.map(\.mode))

        return VStack(alignment: .leading, spacing: 4) {
            Text("\(dayQSOs.count) QSO\(dayQSOs.count == 1 ? "" : "s")")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 8) {
                Text("\(bands.count) band\(bands.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\u{00B7}")
                    .foregroundStyle(.secondary)
                Text("\(modes.count) mode\(modes.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var qsoList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("QSOs")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            LazyVStack(spacing: 0) {
                ForEach(dayQSOs) { qso in
                    dailyQSORow(qso)

                    if qso.id != dayQSOs.last?.id {
                        Divider()
                            .padding(.leading, 60)
                    }
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var dayNavigationButtons: some View {
        HStack(spacing: 12) {
            Button {
                selectedDate = Calendar.current.date(
                    byAdding: .day, value: -1, to: selectedDate
                ) ?? selectedDate
            } label: {
                Image(systemName: "chevron.left")
            }

            Button {
                selectedDate = Calendar.current.date(
                    byAdding: .day, value: 1, to: selectedDate
                ) ?? selectedDate
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(Calendar.current.isDateInToday(selectedDate))
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        if !dayQSOs.isEmpty {
            Button {
                showingShareSheet = true
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
        }
    }

    private func dailyQSORow(_ qso: QSO) -> some View {
        HStack(spacing: 8) {
            Text(formatTime(qso.timestamp))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)

            Text(qso.callsign)
                .font(.subheadline.weight(.semibold).monospaced())

            bandModeBadge(band: qso.band, mode: qso.mode)

            if let park = qso.theirParkReference {
                Text(park)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(qso.rstSent ?? "599")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func bandModeBadge(band: String, mode: String) -> some View {
        Text("\(band) \(mode)")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(bandColor(band))
            .background(bandColor(band).opacity(0.15))
            .clipShape(Capsule())
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    private func loadDayQSOs() {
        guard let log = manager.activeLog else {
            dayQSOs = []
            return
        }

        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let logId = log.id
        let predicate = #Predicate<QSO> { qso in
            qso.loggingSessionId == logId
                && !qso.isHidden
                && qso.timestamp >= startOfDay
                && qso.timestamp < endOfDay
        }

        var descriptor = FetchDescriptor<QSO>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 500

        dayQSOs = (try? modelContext.fetch(descriptor)) ?? []
    }
}

// MARK: - ShareActivitySheet

/// UIActivityViewController wrapper for sharing a rendered image
private struct ShareActivitySheet: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
