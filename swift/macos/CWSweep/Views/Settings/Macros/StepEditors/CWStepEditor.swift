import CarrierWaveData
import SwiftUI

// MARK: - CWStepEditor

/// Editor for `.sendCW(text:)`. ASCII-only (the verifier rejects
/// non-ASCII) and accepts `{arg.foo}` / `{ctx.MYCALL}` placeholders for
/// runtime substitution. The editor previews the resolved text using
/// `MacroContext.preview` so the user can sanity-check templating.
struct CWStepEditor: View {
    // MARK: Internal

    @Binding var text: String

    var body: some View {
        Form {
            Section("Morse Text") {
                TextField("CQ CQ DE {ctx.MYCALL}", text: $text, axis: .vertical)
                    .lineLimit(3 ... 8)
                    .font(.body.monospaced())
                if !text.allSatisfy(\.isASCII) {
                    Text("Non-ASCII characters present — the verifier will block save.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Section("Preview (with W6JY / W1AW context)") {
                Text(previewText.isEmpty ? "(empty)" : previewText)
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Section("Templating") {
                ForEach(Self.tokens, id: \.token) { token in
                    Button {
                        text.append(token.token)
                    } label: {
                        HStack {
                            Text(token.token)
                                .font(.body.monospaced())
                            Spacer()
                            Text(token.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Send CW")
    }

    // MARK: Private

    private struct TokenSuggestion {
        let token: String
        let description: String
    }

    private static let tokens: [TokenSuggestion] = [
        .init(token: "{ctx.MYCALL}", description: "Your callsign"),
        .init(token: "{ctx.CALL}", description: "Contact's callsign"),
        .init(token: "{ctx.RST}", description: "Sent RST"),
        .init(token: "{ctx.NR}", description: "Serial #"),
        .init(token: "{ctx.PARK}", description: "POTA reference"),
        .init(token: "{ctx.EXCH}", description: "Contest exchange"),
    ]

    private var previewText: String {
        let engine = MacroTemplateEngine(args: [])
        // Qualify with module — CW Sweep also has a local `MacroContext`
        // struct in Services/PTT/MacroEngine.swift for the F-key macro
        // system, which shadows the package type here.
        let preview = CarrierWaveData.MacroContext.preview
        let values: [String: String] = [
            "ctx.MYCALL": preview.myCall ?? "",
            "ctx.MYNAME": preview.myName ?? "",
            "ctx.MYGRID": preview.myGrid ?? "",
            "ctx.CALL": preview.contactCall ?? "",
            "ctx.NAME": preview.contactName ?? "",
            "ctx.RST": preview.rstSent ?? "",
            "ctx.RSTR": preview.rstReceived ?? "",
            "ctx.NR": preview.serial.map { String(format: "%03d", $0) } ?? "",
            "ctx.EXCH": preview.exchange ?? "",
            "ctx.PARK": preview.park ?? "",
        ]
        return (try? engine.resolve(text, values: values)) ?? text
    }
}
