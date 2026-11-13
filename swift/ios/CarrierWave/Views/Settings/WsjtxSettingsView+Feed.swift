//
//  WsjtxSettingsView+Feed.swift
//  CarrierWave
//
//  The live feed section of `WsjtxSettingsView`: one line per decode, logged
//  QSO, skipped duplicate, or listener event, newest first (CAR-282).
//

import CarrierWaveData
import SwiftUI

extension WsjtxSettingsView {
    var feedSection: some View {
        Section {
            if service.recentEvents.isEmpty {
                Text(service.isRunning ? "Waiting for WSJT-X…" : "Turn the listener on to see decodes and logged QSOs.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(service.recentEvents.reversed()) { event in
                    feedRow(event)
                }
            }
        } header: {
            HStack {
                Text("Live feed")
                Spacer()
                if !service.recentEvents.isEmpty {
                    Button("Clear") { service.clearFeed() }
                        .font(.caption)
                        .textCase(nil)
                }
            }
        }
    }

    private func feedRow(_ event: WsjtxIngestEvent) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Self.timeFormatter.string(from: event.date))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Image(systemName: icon(for: event.kind))
                .foregroundStyle(color(for: event.kind))
                .frame(width: 14)
            Text(event.text)
                .font(event.kind == .decode ? .caption.monospaced() : .callout)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func icon(for kind: WsjtxIngestEvent.Kind) -> String {
        switch kind {
        case .info: "info.circle"
        case .decode: "waveform"
        case .qsoLogged: "checkmark.circle.fill"
        case .duplicate: "arrow.triangle.2.circlepath"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    private func color(for kind: WsjtxIngestEvent.Kind) -> Color {
        switch kind {
        case .info: .secondary
        case .decode: .blue
        case .qsoLogged: .green
        case .duplicate: .orange
        case .error: .red
        }
    }
}
