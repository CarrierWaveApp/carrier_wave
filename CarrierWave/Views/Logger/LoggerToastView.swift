// Logger Toast View
//
// Toast notification system for the logger, including friend/club member alerts.

import CarrierWaveData
import SwiftUI

// MARK: - ToastType

enum ToastType: Sendable {
    case success
    case error
    case warning
    case info
    case friendSpotted(callsign: String, frequency: Double, mode: String)
    case qsoLogged(callsign: String)
    case spotPosted
    case commandExecuted(String)

    // MARK: Internal

    var icon: String {
        switch self {
        case .success,
             .qsoLogged:
            "checkmark.circle.fill"
        case .error: "xmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        case .friendSpotted: "star.fill"
        case .spotPosted: "antenna.radiowaves.left.and.right"
        case .commandExecuted: "terminal.fill"
        }
    }

    var color: Color {
        switch self {
        case .success,
             .qsoLogged,
             .spotPosted:
            .green
        case .error: .red
        case .warning: .orange
        case .info: .blue
        case .friendSpotted: .yellow
        case .commandExecuted: .purple
        }
    }

    var title: String {
        switch self {
        case .success: "Success"
        case .error: "Error"
        case .warning: "Warning"
        case .info: "Info"
        case let .friendSpotted(callsign, _, _): "\(callsign) Spotted!"
        case let .qsoLogged(callsign): "QSO Logged: \(callsign)"
        case .spotPosted: "Spot Posted"
        case let .commandExecuted(cmd): cmd
        }
    }
}

// MARK: - Toast

struct Toast: Identifiable, Sendable {
    // MARK: Lifecycle

    init(type: ToastType, message: String, duration: TimeInterval = 3.0) {
        self.type = type
        self.message = message
        self.duration = duration
    }

    // MARK: Internal

    let id = UUID()
    let type: ToastType
    let message: String
    let duration: TimeInterval
}

// MARK: - ToastManager

@MainActor
@Observable
final class ToastManager {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = ToastManager()

    private(set) var currentToast: Toast?

    func show(_ toast: Toast) {
        dismissTask?.cancel()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            currentToast = toast
        }

        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(toast.duration * 1_000_000_000))
            if !Task.isCancelled {
                dismiss()
            }
        }
    }

    func show(_ type: ToastType, message: String, duration: TimeInterval = 3.0) {
        show(Toast(type: type, message: message, duration: duration))
    }

    func dismiss() {
        dismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            currentToast = nil
        }
    }

    // MARK: - Convenience Methods

    func success(_ message: String) {
        show(.success, message: message)
    }

    func error(_ message: String) {
        show(.error, message: message, duration: 5.0)
    }

    func warning(_ message: String) {
        show(.warning, message: message, duration: 4.0)
    }

    func info(_ message: String) {
        show(.info, message: message)
    }

    func qsoLogged(callsign: String) {
        show(.qsoLogged(callsign: callsign), message: "Contact saved to log")
    }

    func spotPosted(park: String) {
        show(.spotPosted, message: "Spotted at \(park)")
    }

    func spotPosted(park: String, comment: String) {
        show(.spotPosted, message: "Spotted at \(park): \(comment)")
    }

    func friendSpotted(callsign: String, frequency: Double, mode: String) {
        show(
            .friendSpotted(callsign: callsign, frequency: frequency, mode: mode),
            message: "\(String(format: "%.1f", frequency)) kHz \(mode)",
            duration: 5.0
        )
    }

    func commandExecuted(_ command: String, result: String) {
        show(.commandExecuted(command), message: result)
    }

    // MARK: Private

    private var dismissTask: Task<Void, Never>?
}

// MARK: - LoggerToastView

struct LoggerToastView: View {
    let toast: Toast
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.type.icon)
                .font(.system(size: 20))
                .foregroundStyle(toast.type.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(toast.type.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(toast.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.height < -20 {
                        onDismiss()
                    }
                }
        )
    }
}

// MARK: - ToastContainerModifier

struct ToastContainerModifier: ViewModifier {
    // MARK: Internal

    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content

            if let toast = toastManager.currentToast {
                LoggerToastView(toast: toast) {
                    toastManager.dismiss()
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    )
                )
                .zIndex(1_000)
            }
        }
    }

    // MARK: Private

    @State private var toastManager = ToastManager.shared
}

extension View {
    /// Add toast notification support to a view
    func toastContainer() -> some View {
        modifier(ToastContainerModifier())
    }
}

// MARK: - FriendSpotToastView

/// Special toast for friend/club member spots with action button
struct FriendSpotToastView: View {
    let callsign: String
    let frequency: Double
    let mode: String
    let onTune: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.yellow.opacity(0.2))
                        .frame(width: 44, height: 44)

                    Image(systemName: "star.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.yellow)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(callsign) is on the air!")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text("\(String(format: "%.1f", frequency)) kHz \(mode)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Button(action: onTune) {
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("Tune to \(callsign)")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.yellow)
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
}

// MARK: - Previews

#Preview("Success Toast") {
    VStack {
        Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .overlay(alignment: .top) {
        LoggerToastView(
            toast: Toast(type: .success, message: "Operation completed successfully")
        ) {}
            .padding()
    }
}

#Preview("QSO Logged Toast") {
    VStack {
        Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .overlay(alignment: .top) {
        LoggerToastView(
            toast: Toast(type: .qsoLogged(callsign: "W1AW"), message: "Contact saved to log")
        ) {}
            .padding()
    }
}

#Preview("Friend Spotted Toast") {
    VStack {
        Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .overlay(alignment: .top) {
        FriendSpotToastView(
            callsign: "K3ABC",
            frequency: 14_060.0,
            mode: "CW",
            onTune: {},
            onDismiss: {}
        )
        .padding()
    }
}
