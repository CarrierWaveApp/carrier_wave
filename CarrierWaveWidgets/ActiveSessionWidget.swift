import SwiftUI
import WidgetKit

// MARK: - SessionEntry

struct SessionEntry: TimelineEntry {
    let date: Date
    let session: WidgetSessionSnapshot?
}

// MARK: - SessionTimelineProvider

struct SessionTimelineProvider: TimelineProvider {
    func placeholder(in _: Context) -> SessionEntry {
        SessionEntry(date: Date(), session: WidgetSessionSnapshot(
            isActive: true, parkReference: "K-1234", parkName: "Example Park",
            frequency: "14.062", mode: "CW", qsoCount: 15,
            startedAt: Date().addingTimeInterval(-45 * 60),
            lastCallsign: "W1AW", activationType: "POTA",
            updatedAt: Date()
        ))
    }

    func getSnapshot(in _: Context, completion: @escaping (SessionEntry) -> Void) {
        let session = WidgetDataReader.readSession()
        completion(SessionEntry(date: Date(), session: session))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<SessionEntry>) -> Void) {
        let session = WidgetDataReader.readSession()
        let entry = SessionEntry(date: Date(), session: session)
        // Refresh every 5 minutes during active session, 30 min otherwise
        let interval: TimeInterval = session?.isActive == true ? 5 * 60 : 30 * 60
        let nextUpdate = Date().addingTimeInterval(interval)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

// MARK: - ActiveSessionSmallView

struct ActiveSessionSmallView: View {
    // MARK: Internal

    let session: WidgetSessionSnapshot?

    var body: some View {
        if let session, session.isActive {
            activeContent(session)
        } else {
            inactiveContent
        }
    }

    // MARK: Private

    private var inactiveContent: some View {
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No Session")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Start a session\nin the app")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func activeContent(_ session: WidgetSessionSnapshot) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text("On Air")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }

            if let park = session.parkReference {
                Text(park)
                    .font(.subheadline.weight(.semibold).monospaced())
                    .lineLimit(1)
            }

            Text("\(session.qsoCount)")
                .font(.system(.title, design: .rounded, weight: .bold))

            Text("QSOs")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let callsign = session.lastCallsign {
                Text(callsign)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let started = session.startedAt {
                Text(started, style: .timer)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

// MARK: - ActiveSessionMediumView

struct ActiveSessionMediumView: View {
    // MARK: Internal

    let session: WidgetSessionSnapshot?

    var body: some View {
        if let session, session.isActive {
            activeContent(session)
        } else {
            inactiveContent
        }
    }

    // MARK: Private

    private var inactiveContent: some View {
        HStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("No Active Session")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("Open Carrier Wave to start logging")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding()
    }

    private func activeContent(_ session: WidgetSessionSnapshot) -> some View {
        HStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("\(session.qsoCount)")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text("QSOs")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            sessionDetails(session)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
    }

    private func sessionDetails(_ session: WidgetSessionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text("On Air")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }

            if let park = session.parkReference {
                Text(park)
                    .font(.subheadline.weight(.semibold).monospaced())
            }

            if let freq = session.frequency, let mode = session.mode {
                Text("\(freq) MHz  \(mode)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            } else if let mode = session.mode {
                Text(mode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let callsign = session.lastCallsign {
                HStack(spacing: 4) {
                    Text("Last:")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(callsign)
                        .font(.caption.weight(.medium).monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if let started = session.startedAt {
                Text(started, style: .timer)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - ActiveSessionAccessoryRectangularView

struct ActiveSessionAccessoryRectangularView: View {
    let session: WidgetSessionSnapshot?

    var body: some View {
        if let session, session.isActive {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.caption2)
                        if let park = session.parkReference {
                            Text(park)
                                .font(.caption2.weight(.semibold))
                        } else {
                            Text("On Air")
                                .font(.caption2.weight(.semibold))
                        }
                    }
                    Text("\(session.qsoCount) QSOs")
                        .font(.caption.weight(.bold))
                }
                Spacer()
            }
        } else {
            Text("No session")
                .font(.caption)
        }
    }
}

// MARK: - ActiveSessionWidget

struct ActiveSessionWidget: Widget {
    let kind = "ActiveSessionWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SessionTimelineProvider()) { entry in
            Group {
                switch entry.widgetFamily {
                case .accessoryRectangular:
                    ActiveSessionAccessoryRectangularView(session: entry.session)
                case .systemMedium:
                    ActiveSessionMediumView(session: entry.session)
                default:
                    ActiveSessionSmallView(session: entry.session)
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
            .widgetURL(URL(string: WidgetShared.DeepLink.logger))
        }
        .configurationDisplayName("Active Session")
        .description("Shows your current logging session with QSO count.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

// MARK: - Preview

private extension SessionEntry {
    var widgetFamily: WidgetFamily {
        .systemSmall
    }
}
