import AppKit
import SwiftUI

// MARK: - TableDoubleClickModifier

/// Installs a double-click action on the nearest `NSTableView` in the
/// same SwiftUI hosting branch. Applied via `.onTableDoubleClick {}`.
struct TableDoubleClickModifier: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .overlay {
                TableDoubleClickHelper(action: action)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func onTableDoubleClick(perform action: @escaping () -> Void) -> some View {
        modifier(TableDoubleClickModifier(action: action))
    }
}

// MARK: - TableDoubleClickHelper

private struct TableDoubleClickHelper: NSViewRepresentable {
    // MARK: - DoubleClickInstallerView

    /// Walks up the view tree looking for the nearest common ancestor
    /// that contains an NSTableView, then installs doubleAction on it.
    final class DoubleClickInstallerView: NSView {
        // MARK: Internal

        var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleInstall()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            scheduleInstall()
        }

        // MARK: Private

        private var installed = false

        private func scheduleInstall() {
            guard !installed, window != nil else {
                return
            }
            // Defer to let SwiftUI finish laying out the NSTableView.
            DispatchQueue.main.async { [weak self] in
                self?.installDoubleClick()
            }
        }

        private func installDoubleClick() {
            guard !installed, let coordinator else {
                return
            }
            // Walk up ancestors; at each level search that subtree
            // for an NSTableView. The first hit is the closest table
            // to this view in the hierarchy.
            var ancestor: NSView? = superview
            while let current = ancestor {
                if let table = findTableView(in: current) {
                    table.doubleAction = #selector(coordinator.onDoubleClick)
                    table.target = coordinator
                    installed = true
                    return
                }
                ancestor = current.superview
            }
        }

        private func findTableView(in view: NSView) -> NSTableView? {
            if let table = view as? NSTableView {
                return table
            }
            for child in view.subviews {
                if let table = findTableView(in: child) {
                    return table
                }
            }
            return nil
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        // MARK: Lifecycle

        init(action: @escaping () -> Void) {
            self.action = action
        }

        // MARK: Internal

        var action: () -> Void

        @objc func onDoubleClick() {
            action()
        }
    }

    let action: () -> Void

    func makeNSView(context: Context) -> DoubleClickInstallerView {
        let view = DoubleClickInstallerView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_: DoubleClickInstallerView, context: Context) {
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }
}
