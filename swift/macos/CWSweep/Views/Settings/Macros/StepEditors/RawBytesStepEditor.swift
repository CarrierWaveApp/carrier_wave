import CarrierWaveData
import SwiftUI

// MARK: - RawBytesStepEditor

/// Editor for `.rawBytes(protocol:bytes:)`. The danger surface — sends
/// opaque bytes that bypass the catalog's safety net. Always shows a
/// red warning banner; live-validates the hex string; requires a
/// protocol selection.
struct RawBytesStepEditor: View {
    // MARK: Internal

    @Binding var protocolName: String
    @Binding var bytes: String

    var body: some View {
        Form {
            warningSection
            protocolSection
            bytesSection
        }
        .navigationTitle("Raw Bytes")
    }

    // MARK: Private

    private var headerText: String {
        switch protocolName {
        case "kenwood": "Bytes (ASCII allowed)"
        default: "Hex Bytes"
        }
    }

    private var parsedSummary: String {
        if let parseError {
            return parseError
        }
        let cleaned = bytes
            .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        if cleaned.isEmpty {
            return "0 bytes"
        }
        if protocolName == "kenwood" {
            return "\(cleaned.count) chars"
        }
        return "\(cleaned.count / 2) bytes"
    }

    private var parseError: String? {
        guard protocolName != "kenwood" else {
            return nil
        }
        let cleaned = bytes
            .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        if cleaned.isEmpty {
            return nil
        }
        guard cleaned.count.isMultiple(of: 2) else {
            return "Odd hex digit count"
        }
        for char in cleaned where char.hexDigitValue == nil {
            return "Non-hex character: \(char)"
        }
        return nil
    }

    private var warningSection: some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Unverified raw bytes")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(.red)
                    Text("These bytes bypass the catalog. The verifier " +
                        "treats unknown opcodes as transmit-capable. The " +
                        "safety gate requires explicit per-spec confirmation " +
                        "before each run.")
                        .font(.caption)
                }
            }
        }
        .listRowBackground(Color.red.opacity(0.08))
    }

    private var protocolSection: some View {
        Section("Protocol") {
            Picker("Protocol", selection: $protocolName) {
                ForEach(RadioCommandProtocol.allCases, id: \.rawValue) { rigProtocol in
                    Text(rigProtocol.displayName).tag(rigProtocol.rawValue)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var bytesSection: some View {
        Section {
            TextField("FE FE 94 E0 1C 00 00 FD", text: $bytes, axis: .vertical)
                .lineLimit(2 ... 6)
                .font(.body.monospaced())

            HStack {
                Text(parsedSummary)
                    .font(.caption.monospaced())
                    .foregroundStyle(parseError == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.red))
                Spacer()
            }
        } header: {
            Text(headerText)
        } footer: {
            Text("Hex bytes. Whitespace and `0x` prefixes are ignored. " +
                "Framing (CI-V preamble, Kenwood `;`) is applied by the " +
                "executor — author the inner payload only.")
                .font(.caption)
        }
    }
}
