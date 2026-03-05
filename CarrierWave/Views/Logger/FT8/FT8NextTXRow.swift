//
//  FT8NextTXRow.swift
//  CarrierWave
//

import SwiftUI

// MARK: - FT8NextTXRow

struct FT8NextTXRow: View {
    // MARK: Internal

    struct MessageOption: Identifiable {
        let id = UUID()
        let message: String
        let label: String
        let isAutoSelected: Bool
    }

    let nextMessage: String?
    let stepIndex: Int
    let totalSteps: Int
    let isOverrideActive: Bool
    let allMessages: [MessageOption]
    let onOverride: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            collapsedRow
            if isExpanded {
                overrideList
            }
        }
        .background(
            isOverrideActive
                ? Color.orange.opacity(0.1)
                : Color(.tertiarySystemGroupedBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            isOverrideActive
                ? RoundedRectangle(cornerRadius: 8)
                .inset(by: 0.5)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                : nil
        )
    }

    // MARK: Private

    @State private var isExpanded = false

    private var collapsedRow: some View {
        Button {
            withAnimation(.spring(duration: 0.3, bounce: 0.0)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                if let msg = nextMessage {
                    Text(msg)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                } else {
                    Text("--")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Text("auto \u{00B7} \(stepIndex)/\(totalSteps)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var overrideList: some View {
        VStack(spacing: 0) {
            Divider()
            ForEach(allMessages) { option in
                Button {
                    onOverride(option.message)
                    withAnimation { isExpanded = false }
                } label: {
                    HStack(spacing: 8) {
                        Image(
                            systemName: option.isAutoSelected
                                ? "largecircle.fill.circle" : "circle"
                        )
                        .font(.caption)
                        .foregroundStyle(option.isAutoSelected ? Color.accentColor : .secondary)

                        Text(option.message)
                            .font(.caption.monospaced())
                            .lineLimit(1)

                        Spacer()

                        Text(option.label)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
