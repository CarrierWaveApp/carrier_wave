import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - ScanConfigSheet

/// Configuration sheet shown after camera capture or photo selection, before OCR
/// processing. Lets the user set RST order, default date, callsign, and edit
/// (rotate/crop) individual page images.
struct ScanConfigSheet: View {
    // MARK: Internal

    @Binding var rstOrder: RSTOrder
    @Binding var defaultDate: Date
    @Binding var myCallsign: String
    @Binding var images: [UIImage]

    let onProcess: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    EditablePagePreview(
                        images: $images,
                        editingIndex: $editingIndex
                    )
                } header: {
                    Text("Pages (\(images.count))")
                } footer: {
                    Text("Tap a page to rotate or crop it.")
                }

                Section {
                    Picker("RST Order", selection: $rstOrder) {
                        ForEach(RSTOrder.allCases, id: \.self) { order in
                            Text(order.label).tag(order)
                        }
                    }
                } header: {
                    Text("RST Parsing")
                } footer: {
                    Text(rstOrderFooter)
                }

                Section {
                    DatePicker(
                        "Default Date",
                        selection: $defaultDate,
                        displayedComponents: .date
                    )
                } header: {
                    Text("Fallback Date")
                } footer: {
                    Text("Used for rows that don't have a date.")
                }

                Section {
                    TextField("My Callsign", text: $myCallsign)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } header: {
                    Text("Station")
                }
            }
            .navigationTitle("Scan Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Process") { onProcess() }
                        .disabled(myCallsign.isEmpty || images.isEmpty)
                }
            }
            .sheet(item: $editingIndex) { item in
                PageEditSheet(
                    image: images[item.index],
                    onSave: { edited in
                        images[item.index] = edited
                    },
                    onDelete: {
                        images.remove(at: item.index)
                    }
                )
            }
        }
    }

    // MARK: Private

    @State private var editingIndex: EditablePageIndex?

    private var rstOrderFooter: String {
        switch rstOrder {
        case .receivedFirst:
            "When two RSTs appear without R/S suffix, the first is their report to you."
        case .sentFirst:
            "When two RSTs appear without R/S suffix, the first is your report to them."
        }
    }
}

// MARK: - EditablePageIndex

/// Identifiable wrapper for a page index so it can drive a `.sheet(item:)`.
struct EditablePageIndex: Identifiable {
    let index: Int

    var id: Int {
        index
    }
}

// MARK: - EditablePagePreview

/// Horizontal scrolling thumbnails with tap-to-edit.
struct EditablePagePreview: View {
    @Binding var images: [UIImage]
    @Binding var editingIndex: EditablePageIndex?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                    Button {
                        editingIndex = EditablePageIndex(index: index)
                    } label: {
                        VStack(spacing: 4) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(.secondary.opacity(0.3), lineWidth: 1)
                                )

                            Text("Page \(index + 1)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
