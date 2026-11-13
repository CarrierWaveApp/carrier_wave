//
//  FrequencyScopeListCenteringTests.swift
//  CarrierWaveTests
//
//  Regression coverage for CAR-346: the wizard's frequency scope readout and
//  reticle disagreed (reticle on 14.051, readout 14.068). The scope read the
//  centered row as `contentOffset / rowHeight`, but a `LazyVStack` gives rows it
//  hasn't rendered an estimated height, so after a jump the offset no longer
//  maps to a row: straight after opening on 14.068 the arithmetic said 14.094.
//  Hosts the real `FrequencyScopeList`, reproduces the wizard's expand path
//  (animated insertion + scroll command in the same update), then scrolls and
//  checks the selection follows the row that is actually under the reticle.
//

import SwiftUI
import XCTest
@testable import CarrierWave

// MARK: - FrequencyScopeListCenteringTests

@MainActor
final class FrequencyScopeListCenteringTests: XCTestCase {
    // MARK: Internal

    func testReadoutFollowsReticleAfterOpeningOnFarFrequency() async throws {
        let rows = FrequencyScopeLogic.buildRows(
            band: "20m", mode: "CW", license: .general, step: 1_000, spots: []
        )
        let targetHz = 14_068_000
        XCTAssertNotNil(rows.firstIndex { $0.hz == targetHz })
        let model = ScopeHarnessModel(centerHz: targetHz)
        let window = try hostWindow(ScopeHarness(model: model, rows: rows))
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(300))

        // Same sequence as FrequencyScopeField's summary button.
        withAnimation(.easeInOut(duration: 0.22)) { model.expanded = true }
        model.command = ScopeScrollCommand(hz: targetHz, animated: false, nonce: 1)
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(model.centerHz, targetHz, "opening the scope must not move the selection")

        // Scroll up three rows. They're on screen, so their real 34 pt heights
        // are laid out and the row under the reticle is unambiguous: 14.065.
        let scrollView = try XCTUnwrap(Self.verticalScrollView(in: window))
        let offset = scrollView.contentOffset
        scrollView.setContentOffset(
            CGPoint(x: offset.x, y: offset.y - 3 * FrequencyScopeList.rowHeight), animated: false
        )
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(model.centerHz, 14_065_000, "readout must follow the row under the reticle")
    }

    // MARK: Private

    private static func verticalScrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height {
            return scroll
        }
        for subview in view.subviews {
            if let found = verticalScrollView(in: subview) {
                return found
            }
        }
        return nil
    }

    private func hostWindow(_ root: some View) throws -> UIWindow {
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene
        )
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = UIHostingController(rootView: root)
        window.windowLevel = .alert + 1
        window.makeKeyAndVisible()
        return window
    }
}

// MARK: - ScopeHarnessModel

@Observable
@MainActor
private final class ScopeHarnessModel {
    // MARK: Lifecycle

    init(centerHz: Int) {
        self.centerHz = centerHz
    }

    // MARK: Internal

    var expanded = false
    var command: ScopeScrollCommand?
    var centerHz: Int
}

// MARK: - ScopeHarness

/// Mirrors how FrequencyScopeField inserts the scope: collapsed by default,
/// inserted with the same transition when expanded.
private struct ScopeHarness: View {
    @Bindable var model: ScopeHarnessModel

    let rows: [ScopeRowInfo]

    var body: some View {
        VStack(spacing: 0) {
            // Mid-screen like the wizard's Form row, clear of the status-bar safe area.
            Color.clear.frame(height: 240)
            if model.expanded {
                FrequencyScopeList(
                    rows: rows, isGood: true, isDataMode: false,
                    rowsVersion: 0, scrollCommand: model.command, centerHz: $model.centerHz
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Spacer(minLength: 0)
        }
    }
}
