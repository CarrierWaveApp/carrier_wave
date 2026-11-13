//
//  FT8AudioOverloadBanner.swift
//  CarrierWave
//

import SwiftUI
import UIKit

/// Banner shown when sustained input RMS indicates a hot or clipping mic input,
/// which paints the waterfall in wide-band red and destroys decode quality.
/// Gives the user concrete, actionable advice they can take without leaving the app.
struct FT8AudioOverloadBanner: View {
    // MARK: Internal

    let state: FT8AudioOverloadTracker.State

    var body: some View {
        if state != .ok {
            content
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: Private

    private var headline: String {
        switch state {
        case .critical: "Audio is clipping"
        case .ok: ""
        }
    }

    private var advice: String {
        switch state {
        case .critical:
            "Samples are pinned to full-scale for several seconds — decodes will fail. "
                + "Turn down the radio's AF level, the gain knob on your USB interface, "
                + "or iOS Settings → Sounds & Haptics → Headphone Audio. The level meter "
                + "should peak in yellow, not red."
        case .ok:
            ""
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.headline)
                Text(headline)
                    .font(.subheadline.bold())
                Spacer()
            }
            Text(advice)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.9))
            Button {
                openAudioSettings()
            } label: {
                HStack(spacing: 4) {
                    Text("Open Settings")
                    Image(systemName: "arrow.up.right.square")
                }
                .font(.caption.bold())
            }
            .buttonStyle(.borderedProminent)
            .tint(.white.opacity(0.25))
            .foregroundStyle(.white)
            .controlSize(.mini)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .foregroundStyle(.white)
    }

    private var background: some View {
        Color.red.opacity(0.92)
    }

    private func openAudioSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
