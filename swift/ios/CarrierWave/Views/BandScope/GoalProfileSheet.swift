import SwiftUI

// MARK: - GoalProfileSheet

/// Profile picker + minimal editor (spec §16). One profile active at a
/// time; built-ins first, user-defined after. Deliberately spare — if
/// telemetry shows profiles unused, this UI stays cheap.
struct GoalProfileSheet: View {
    // MARK: Internal

    let model: BandScopeViewModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.profileStore.allProfiles) { profile in
                        profileRow(profile)
                    }
                } footer: {
                    Text("Club filtering is SKCC-complete; LICW/CWOps identity appears in spot details only.")
                }
                Section {
                    Button {
                        editorProfile = newProfile()
                    } label: {
                        Label("New profile", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("Goal Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(item: $editorProfile) { profile in
            GoalProfileEditor(profile: profile, model: model)
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var editorProfile: GoalProfile?

    private func profileRow(_ profile: GoalProfile) -> some View {
        Button {
            model.profileStore.activeProfileID = profile.id
            model.applyProfile()
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .foregroundStyle(.primary)
                    if !profile.isBuiltIn {
                        Text("Custom")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if profile.id == model.profileStore.activeProfileID {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                }
            }
        }
        .swipeActions(edge: .trailing) {
            if !profile.isBuiltIn {
                Button("Delete", role: .destructive) {
                    model.profileStore.deleteUserProfile(id: profile.id)
                    model.applyProfile()
                }
                Button("Edit") {
                    editorProfile = profile
                }
            }
        }
    }

    private func newProfile() -> GoalProfile {
        GoalProfile(
            id: "user.\(UUID().uuidString)",
            name: "",
            predicate: .neededOnly,
            goals: GoalProfile.Goal.allCases,
            clubs: []
        )
    }
}

// MARK: - GoalProfileEditor

/// Minimal user-defined profile editor: name, feed predicate, goals that
/// light `needed`, clubs that light `club`.
struct GoalProfileEditor: View {
    // MARK: Lifecycle

    init(profile: GoalProfile, model: BandScopeViewModel) {
        self.model = model
        _draft = State(initialValue: profile)
    }

    // MARK: Internal

    let model: BandScopeViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Profile name", text: $draft.name)
                }
                Section("Feed") {
                    Picker("Include", selection: $draft.predicate) {
                        Text("Everything").tag(GoalProfile.Predicate.all)
                        Text("Park activity").tag(GoalProfile.Predicate.parks)
                        Text("DXCC needs").tag(GoalProfile.Predicate.dxccNeeded)
                        Text("Club members").tag(GoalProfile.Predicate.clubMembers)
                        Text("Any need").tag(GoalProfile.Predicate.neededOnly)
                    }
                }
                Section("Goals that light orange") {
                    ForEach(GoalProfile.Goal.allCases, id: \.self) { goal in
                        Toggle(goalLabel(goal), isOn: goalBinding(goal))
                    }
                }
                Section("Clubs") {
                    ForEach(GoalProfile.Club.allCases, id: \.self) { club in
                        Toggle(club.rawValue.uppercased(), isOn: clubBinding(club))
                    }
                }
            }
            .navigationTitle(draft.name.isEmpty ? "New Profile" : draft.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.profileStore.saveUserProfile(draft)
                        model.profileStore.activeProfileID = draft.id
                        model.applyProfile()
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var draft: GoalProfile

    private func goalLabel(_ goal: GoalProfile.Goal) -> String {
        switch goal {
        case .dxcc: "DXCC"
        case .was: "Worked All States"
        case .parks: "Parks (POTA)"
        case .wwff: "WWFF"
        case .custom: "Custom patterns"
        }
    }

    private func goalBinding(_ goal: GoalProfile.Goal) -> Binding<Bool> {
        Binding(
            get: { draft.goals.contains(goal) },
            set: { isOn in
                if isOn {
                    if !draft.goals.contains(goal) {
                        draft.goals.append(goal)
                    }
                } else {
                    draft.goals.removeAll { $0 == goal }
                }
            }
        )
    }

    private func clubBinding(_ club: GoalProfile.Club) -> Binding<Bool> {
        Binding(
            get: { draft.clubs.contains(club) },
            set: { isOn in
                if isOn {
                    if !draft.clubs.contains(club) {
                        draft.clubs.append(club)
                    }
                } else {
                    draft.clubs.removeAll { $0 == club }
                }
            }
        )
    }
}
