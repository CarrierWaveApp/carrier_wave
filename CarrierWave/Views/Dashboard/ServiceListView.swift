import CarrierWaveCore
import SwiftUI

// MARK: - ServiceStatus

/// Represents the connection/configuration status of a service
enum ServiceStatus {
    case connected
    case pending
    case notConfigured
    case maintenance

    // MARK: Internal

    var color: Color {
        switch self {
        case .connected:
            .green
        case .pending:
            .orange
        case .notConfigured:
            Color(.systemGray3)
        case .maintenance:
            .orange
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .connected:
            "Connected"
        case .pending:
            "Pending"
        case .notConfigured:
            "Not configured"
        case .maintenance:
            "Maintenance"
        }
    }
}

// MARK: - ServiceIdentifier

/// Identifier for services including iCloud which isn't in ServiceType
enum ServiceIdentifier: Hashable, Identifiable {
    case service(ServiceType)
    case icloud

    // MARK: Internal

    var id: String {
        switch self {
        case let .service(type):
            "service-\(type.rawValue)"
        case .icloud:
            "icloud"
        }
    }

    var displayName: String {
        switch self {
        case let .service(type):
            type.displayName
        case .icloud:
            "iCloud"
        }
    }
}

// MARK: - ServiceInfo

/// Data model for displaying a service in the list
struct ServiceInfo: Identifiable {
    let id: ServiceIdentifier
    let name: String
    let status: ServiceStatus
    let primaryStat: String?
    let secondaryStat: String?
    let tertiaryInfo: String?
    let showWarning: Bool
    let isSyncing: Bool

    /// Convenience for getting ServiceType if applicable
    var serviceType: ServiceType? {
        if case let .service(type) = id {
            return type
        }
        return nil
    }
}

// MARK: - ServiceRow

/// A single row in the services list following HIG grouped list style
struct ServiceRow: View {
    let service: ServiceInfo
    let serviceSyncStates: [ServiceType: ServiceSyncPhase]

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(service.status.color)
                .frame(width: 10, height: 10)
                .accessibilityLabel(service.status.accessibilityLabel)

            // Service name
            Text(service.name)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer()

            // Stats or status text
            if service.isSyncing, let serviceType = service.serviceType {
                SyncingIndicator(
                    servicePhase: serviceSyncStates[serviceType],
                    serviceType: serviceType
                )
            } else if let primary = service.primaryStat {
                HStack(spacing: 8) {
                    // Stack stats vertically, right-aligned
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(primary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if let secondary = service.secondaryStat {
                            Text(secondary)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        if let tertiary = service.tertiaryInfo {
                            Text(tertiary)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    if service.showWarning {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Attention needed")
                    }
                }
            } else {
                Text(service.tertiaryInfo ?? "Not configured")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }

            // Disclosure indicator
            Image(systemName: "chevron.right")
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

// MARK: - SyncingIndicator

/// Compact syncing indicator for the service row
struct SyncingIndicator: View {
    // MARK: Internal

    let servicePhase: ServiceSyncPhase?
    let serviceType: ServiceType

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.caption)
                .rotationEffect(.degrees(rotation))

            Text(statusText)
                .font(.subheadline)
        }
        .foregroundStyle(isActive ? .blue : .secondary)
        .onAppear {
            guard !reduceMotion else {
                return
            }
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }

    // MARK: Private

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation: Double = 0

    private var isActive: Bool {
        switch servicePhase {
        case .downloading,
             .uploading:
            true
        default:
            false
        }
    }

    private var statusText: String {
        switch servicePhase {
        case .downloading:
            "Downloading"
        case .uploading:
            "Uploading"
        case .downloaded:
            "Downloaded"
        case .complete:
            "Complete"
        case .error:
            "Error"
        default:
            "Waiting"
        }
    }
}
