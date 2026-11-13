import CarrierWaveData
import PhotosUI
import SwiftUI

// MARK: - SessionMetadataEditResult

/// Result of editing session metadata
struct SessionMetadataEditResult {
    let title: String?
    let watts: Int?
    let radio: String?
    let antenna: String?
    let key: String?
    let mic: String?
    let extraEquipment: String?
    let attendees: String?
    let operatorCallsigns: [String]
    let notes: String?
    let qsoComment: String?
    /// New callsign, if changed (nil means no change)
    let newCallsign: String?
    /// New park reference, if changed (nil means no change)
    let newParkReference: String?
    let addedPhotos: [UIImage]
    let deletedPhotoFilenames: [String]
}

// MARK: - SessionMetadataEditSheet

/// Unified edit sheet for all session types (replaces ActivationMetadataEditSheet)
struct SessionMetadataEditSheet: View {
    // MARK: Lifecycle

    init(
        session: LoggingSession,
        metadata: ActivationMetadata?,
        userGrid: String?,
        onSave: @escaping (SessionMetadataEditResult) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.session = session
        self.userGrid = userGrid
        self.onSave = onSave
        self.onCancel = onCancel
        isPOTA = session.isPOTA

        _callsign = State(initialValue: session.myCallsign)
        originalCallsign = session.myCallsign
        _title = State(initialValue: session.customTitle ?? metadata?.title ?? "")
        _wattsText = State(initialValue: (session.power ?? metadata?.watts).map { String($0) } ?? "")
        _radio = State(initialValue: session.myRig)
        _antenna = State(initialValue: session.myAntenna)
        _key = State(initialValue: session.myKey)
        _mic = State(initialValue: session.myMic)
        _extraEquipment = State(initialValue: session.extraEquipment ?? "")
        _attendees = State(initialValue: session.attendees ?? "")
        _operatorsText = State(initialValue: session.operatorCallsigns.joined(separator: ", "))
        _notes = State(initialValue: session.notes ?? "")
        _qsoComment = State(initialValue: session.qsoComment ?? "")
        _parkReference = State(initialValue: session.parkReference ?? "")
        _existingPhotoFilenames = State(initialValue: session.photoFilenames)
        originalParkReference = session.parkReference ?? ""
        sessionID = session.id
    }

    // MARK: Internal

    let session: LoggingSession

    var body: some View {
        NavigationStack {
            Form {
                callsignSection
                titleSection
                equipmentSection
                operatorsSection
                attendeesSection
                photosSection
                qsoCommentSection
                notesSection
                if isPOTA {
                    parkSection
                }
                totaSection
            }
            .navigationTitle("Edit Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .confirmationDialog(
                "Change Callsign",
                isPresented: $showCallsignChangeConfirmation,
                titleVisibility: .visible
            ) {
                Button("Change Callsign") {
                    proceedAfterCallsignConfirmation()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "This will update your callsign on all QSOs in this session" +
                        " from \(originalCallsign) to \(normalizedCallsign)."
                )
            }
            .confirmationDialog(
                "Change Park Reference",
                isPresented: $showParkChangeConfirmation,
                titleVisibility: .visible
            ) {
                Button("Change Park", role: .destructive) {
                    commitSave(
                        confirmCallsignChange: callsignChanged,
                        confirmParkChange: true
                    )
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "This will update all QSOs from \(originalParkReference) to " +
                        "\(normalizedParkReference) and clear their POTA upload status."
                )
            }
        }
        .sheet(item: $activePickerCategory) { category in
            InventoryPickerSheet(
                category: category,
                selection: equipmentBinding(for: category)
            )
            .landscapeAdaptiveDetents(portrait: [.medium])
        }
        .landscapeAdaptiveDetents(portrait: [.large])
    }

    // MARK: Private

    @State private var callsign: String
    @State private var title: String
    @State private var wattsText: String
    @State private var radio: String?
    @State private var antenna: String?
    @State private var key: String?
    @State private var mic: String?
    @State private var extraEquipment: String
    @State private var attendees: String
    @State private var operatorsText: String
    @State private var notes: String
    @State private var qsoComment: String
    @State private var parkReference: String
    @State private var existingPhotoFilenames: [String]
    @State private var deletedPhotoFilenames: [String] = []
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var addedImages: [UIImage] = []

    @State private var showCallsignChangeConfirmation = false
    @State private var showParkChangeConfirmation = false
    @State private var activePickerCategory: EquipmentCategory?

    private let userGrid: String?
    private let onSave: (SessionMetadataEditResult) -> Void
    private let onCancel: () -> Void
    private let isPOTA: Bool
    private let originalCallsign: String
    private let originalParkReference: String
    private let sessionID: UUID

    private var parsedWatts: Int? {
        guard !wattsText.isEmpty else {
            return nil
        }
        return Int(wattsText)
    }

    private var normalizedCallsign: String {
        callsign.trimmingCharacters(in: .whitespaces).uppercased()
    }

    private var callsignChanged: Bool {
        normalizedCallsign != originalCallsign
    }

    private var normalizedParkReference: String {
        ParkReference.sanitizeMulti(parkReference) ?? parkReference.uppercased()
    }

    private var parkChanged: Bool {
        normalizedParkReference != originalParkReference
    }
}

// MARK: - Sections

extension SessionMetadataEditSheet {
    var callsignSection: some View {
        Section {
            TextField("Callsign", text: $callsign)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
        } header: {
            Text("My Callsign")
        } footer: {
            if callsignChanged {
                Label(
                    "Changing your callsign will update all QSOs in this session.",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
            }
        }
    }

    var titleSection: some View {
        Section {
            TextField("Session title", text: $title)
                .textInputAutocapitalization(.words)
        } header: {
            Text("Title")
        } footer: {
            Text("Optional name for this session")
        }
    }

    var equipmentSection: some View {
        Section {
            HStack {
                TextField("100", text: $wattsText)
                    .keyboardType(.numberPad)
                Text("W")
                    .foregroundStyle(.secondary)
            }

            equipmentRow("Radio", icon: "radio", value: radio) {
                activePickerCategory = .radio
            }
            equipmentRow(
                "Antenna", icon: "antenna.radiowaves.left.and.right", value: antenna
            ) {
                activePickerCategory = .antenna
            }
            equipmentRow("Key", icon: "pianokeys", value: key) {
                activePickerCategory = .key
            }
            equipmentRow("Mic", icon: "mic", value: mic) {
                activePickerCategory = .microphone
            }

            TextField("Other equipment", text: $extraEquipment)
                .textInputAutocapitalization(.sentences)
        } header: {
            Text("Equipment")
        }
    }

    var operatorsSection: some View {
        Section {
            TextField("e.g. W1AW, K3LR", text: $operatorsText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
        } header: {
            Text("Additional Operators")
        } footer: {
            Text("Comma-separated callsigns for multi-op sessions")
        }
    }

    var attendeesSection: some View {
        Section {
            TextField("e.g. KI7QCF, N0CALL", text: $attendees)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
        } header: {
            Text("Attendees")
        }
    }

    var photosSection: some View {
        Section {
            let visibleFilenames = existingPhotoFilenames.filter {
                !deletedPhotoFilenames.contains($0)
            }
            if !visibleFilenames.isEmpty || !addedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(visibleFilenames, id: \.self) { filename in
                            existingPhotoThumbnail(filename)
                        }
                        ForEach(addedImages.indices, id: \.self) { index in
                            addedPhotoThumbnail(index)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            PhotosPicker(
                selection: $selectedPhotos,
                maxSelectionCount: 10,
                matching: .images
            ) {
                Label("Add Photos", systemImage: "photo.badge.plus")
            }
            .onChange(of: selectedPhotos) { _, items in
                Task {
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data)
                        {
                            addedImages.append(image)
                        }
                    }
                    selectedPhotos = []
                }
            }
        } header: {
            Text("Photos")
        }
    }

    var qsoCommentSection: some View {
        Section {
            TextField("Added to every QSO", text: $qsoComment, axis: .vertical)
                .lineLimit(2 ... 4)
        } header: {
            Text("QSO Comment")
        } footer: {
            Text("This comment is prepended to each QSO's notes when logged")
        }
    }

    var notesSection: some View {
        Section {
            TextField("Session notes", text: $notes, axis: .vertical)
                .lineLimit(3 ... 8)
        } header: {
            Text("Notes")
        }
    }

    var parkSection: some View {
        Section {
            ParkEntryField(
                parkReference: $parkReference,
                label: "Parks",
                placeholder: "K-1234",
                userGrid: userGrid,
                defaultCountry: "US"
            )
        } header: {
            Text("Parks")
        } footer: {
            if parkChanged {
                Label(
                    "Changing parks will update all QSOs and clear POTA upload status.",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
            }
        }
    }
}

// MARK: - Helpers

extension SessionMetadataEditSheet {
    func equipmentRow(
        _ label: String, icon: String, value: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Label(label, systemImage: icon)
                    .foregroundStyle(.primary)
                Spacer()
                Text(value ?? "None")
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    func equipmentBinding(
        for category: EquipmentCategory
    ) -> Binding<String?> {
        switch category {
        case .radio: $radio
        case .antenna: $antenna
        case .key: $key
        case .microphone: $mic
        case .accessory: .constant(nil)
        }
    }

    func existingPhotoThumbnail(_ filename: String) -> some View {
        let url = SessionPhotoManager.photoURL(filename: filename, sessionID: sessionID)
        return ZStack(alignment: .topTrailing) {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.gray.opacity(0.3)
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button {
                deletedPhotoFilenames.append(filename)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white, .red)
                    .font(.title3)
            }
            .offset(x: 4, y: -4)
        }
    }

    func addedPhotoThumbnail(_ index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: addedImages[index])
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Button {
                addedImages.remove(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white, .red)
                    .font(.title3)
            }
            .offset(x: 4, y: -4)
        }
    }

    func save() {
        if callsignChanged {
            showCallsignChangeConfirmation = true
        } else if isPOTA, parkChanged {
            showParkChangeConfirmation = true
        } else {
            commitSave(confirmCallsignChange: false, confirmParkChange: false)
        }
    }

    /// Called after callsign confirmation — check if park also needs confirming
    private func proceedAfterCallsignConfirmation() {
        if isPOTA, parkChanged {
            showParkChangeConfirmation = true
        } else {
            commitSave(confirmCallsignChange: true, confirmParkChange: false)
        }
    }

    func commitSave(confirmCallsignChange: Bool, confirmParkChange: Bool) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let trimmedEquipment = extraEquipment.trimmingCharacters(in: .whitespaces)
        let trimmedAttendees = attendees.trimmingCharacters(in: .whitespaces)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)
        let trimmedQSOComment = qsoComment.trimmingCharacters(in: .whitespaces)

        let result = SessionMetadataEditResult(
            title: trimmedTitle.isEmpty ? nil : trimmedTitle,
            watts: parsedWatts,
            radio: radio,
            antenna: antenna,
            key: key,
            mic: mic,
            extraEquipment: trimmedEquipment.isEmpty ? nil : trimmedEquipment,
            attendees: trimmedAttendees.isEmpty ? nil : trimmedAttendees,
            operatorCallsigns: parseOperatorCallsigns(operatorsText),
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            qsoComment: trimmedQSOComment.isEmpty ? nil : trimmedQSOComment,
            newCallsign: confirmCallsignChange ? normalizedCallsign : nil,
            newParkReference: confirmParkChange ? normalizedParkReference : nil,
            addedPhotos: addedImages,
            deletedPhotoFilenames: deletedPhotoFilenames
        )
        onSave(result)
    }

    private func parseOperatorCallsigns(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .filter { !$0.isEmpty }
    }
}
