import CarrierWaveCore
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
    let notes: String?
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
        isPOTA = session.activationType == .pota

        _title = State(initialValue: session.customTitle ?? metadata?.title ?? "")
        _wattsText = State(initialValue: (session.power ?? metadata?.watts).map { String($0) } ?? "")
        _radio = State(initialValue: session.myRig)
        _antenna = State(initialValue: session.myAntenna)
        _key = State(initialValue: session.myKey)
        _mic = State(initialValue: session.myMic)
        _extraEquipment = State(initialValue: session.extraEquipment ?? "")
        _attendees = State(initialValue: session.attendees ?? "")
        _notes = State(initialValue: session.notes ?? "")
        _parkReference = State(initialValue: session.parkReference ?? "")
        _existingPhotoFilenames = State(initialValue: session.photoFilenames)
        originalParkReference = session.parkReference ?? ""
        sessionID = session.id
    }

    // MARK: Internal

    var body: some View {
        NavigationStack {
            Form {
                titleSection
                equipmentSection
                attendeesSection
                photosSection
                notesSection
                if isPOTA {
                    parkSection
                }
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
                "Change Park Reference",
                isPresented: $showParkChangeConfirmation,
                titleVisibility: .visible
            ) {
                Button("Change Park", role: .destructive) {
                    commitSave(confirmParkChange: true)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "This will update all QSOs from \(originalParkReference) to " +
                        "\(normalizedParkReference) and clear their POTA upload status."
                )
            }
        }
        .sheet(isPresented: $showRadioPicker) {
            RadioPickerSheet(selection: $radio)
                .landscapeAdaptiveDetents(portrait: [.medium])
        }
        .sheet(isPresented: $showAntennaPicker) {
            EquipmentPickerSheet(equipmentType: .antenna, selection: $antenna)
                .landscapeAdaptiveDetents(portrait: [.medium])
        }
        .sheet(isPresented: $showKeyPicker) {
            EquipmentPickerSheet(equipmentType: .key, selection: $key)
                .landscapeAdaptiveDetents(portrait: [.medium])
        }
        .sheet(isPresented: $showMicPicker) {
            EquipmentPickerSheet(equipmentType: .mic, selection: $mic)
                .landscapeAdaptiveDetents(portrait: [.medium])
        }
        .landscapeAdaptiveDetents(portrait: [.large])
    }

    // MARK: Private

    @State private var title: String
    @State private var wattsText: String
    @State private var radio: String?
    @State private var antenna: String?
    @State private var key: String?
    @State private var mic: String?
    @State private var extraEquipment: String
    @State private var attendees: String
    @State private var notes: String
    @State private var parkReference: String
    @State private var existingPhotoFilenames: [String]
    @State private var deletedPhotoFilenames: [String] = []
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var addedImages: [UIImage] = []

    @State private var showParkChangeConfirmation = false
    @State private var showRadioPicker = false
    @State private var showAntennaPicker = false
    @State private var showKeyPicker = false
    @State private var showMicPicker = false

    private let session: LoggingSession
    private let userGrid: String?
    private let onSave: (SessionMetadataEditResult) -> Void
    private let onCancel: () -> Void
    private let isPOTA: Bool
    private let originalParkReference: String
    private let sessionID: UUID

    private var parsedWatts: Int? {
        guard !wattsText.isEmpty else {
            return nil
        }
        return Int(wattsText)
    }

    private var normalizedParkReference: String {
        ParkReference.sanitizeMulti(parkReference) ?? parkReference.uppercased()
    }

    private var parkChanged: Bool {
        normalizedParkReference != originalParkReference
    }

    // MARK: - Sections

    private var titleSection: some View {
        Section {
            TextField("Session title", text: $title)
                .textInputAutocapitalization(.words)
        } header: {
            Text("Title")
        } footer: {
            Text("Optional name for this session")
        }
    }

    private var equipmentSection: some View {
        Section {
            HStack {
                TextField("100", text: $wattsText)
                    .keyboardType(.numberPad)
                Text("W")
                    .foregroundStyle(.secondary)
            }

            equipmentRow("Radio", icon: "radio", value: radio) {
                showRadioPicker = true
            }
            equipmentRow(
                "Antenna", icon: "antenna.radiowaves.left.and.right", value: antenna
            ) {
                showAntennaPicker = true
            }
            equipmentRow("Key", icon: "pianokeys", value: key) {
                showKeyPicker = true
            }
            equipmentRow("Mic", icon: "mic", value: mic) {
                showMicPicker = true
            }

            TextField("Other equipment", text: $extraEquipment)
                .textInputAutocapitalization(.sentences)
        } header: {
            Text("Equipment")
        }
    }

    private var attendeesSection: some View {
        Section {
            TextField("e.g. KI7QCF, N0CALL", text: $attendees)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
        } header: {
            Text("Attendees")
        }
    }

    private var photosSection: some View {
        Section {
            // Existing photos
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

    private var notesSection: some View {
        Section {
            TextField("Session notes", text: $notes, axis: .vertical)
                .lineLimit(3 ... 8)
        } header: {
            Text("Notes")
        }
    }

    private var parkSection: some View {
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
        if isPOTA, parkChanged {
            showParkChangeConfirmation = true
        } else {
            commitSave(confirmParkChange: false)
        }
    }

    func commitSave(confirmParkChange: Bool) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let trimmedEquipment = extraEquipment.trimmingCharacters(in: .whitespaces)
        let trimmedAttendees = attendees.trimmingCharacters(in: .whitespaces)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)

        let result = SessionMetadataEditResult(
            title: trimmedTitle.isEmpty ? nil : trimmedTitle,
            watts: parsedWatts,
            radio: radio,
            antenna: antenna,
            key: key,
            mic: mic,
            extraEquipment: trimmedEquipment.isEmpty ? nil : trimmedEquipment,
            attendees: trimmedAttendees.isEmpty ? nil : trimmedAttendees,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            newParkReference: confirmParkChange ? normalizedParkReference : nil,
            addedPhotos: addedImages,
            deletedPhotoFilenames: deletedPhotoFilenames
        )
        onSave(result)
    }
}
