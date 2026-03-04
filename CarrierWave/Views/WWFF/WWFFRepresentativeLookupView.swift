// WWFF Representative Lookup View
//
// Allows users to find their WWFF national program representative
// and compose an email for log submissions or inquiries.
// Lookup by WWFF reference, program code, or country search.

import SwiftUI

// MARK: - WWFFRepresentativeLookupView

struct WWFFRepresentativeLookupView: View {
    // MARK: Internal

    var body: some View {
        List {
            lookupSection

            if let rep = selectedRepresentative {
                representativeDetailSection(rep)
                emailComposeSection(rep)
            }

            if selectedRepresentative == nil, searchText.isEmpty {
                allRepresentativesSection
            }
        }
        .navigationTitle("WWFF Representatives")
        .searchable(text: $searchText, prompt: "Search by country or program code")
        .onChange(of: searchText) { _, newValue in
            performSearch(newValue)
        }
    }

    // MARK: Private

    @State private var searchText = ""
    @State private var selectedRepresentative: WWFFRepresentative?
    @State private var referenceInput = ""
    @State private var searchResults: [WWFFRepresentative] = []
    @State private var userCallsign = ""
    @State private var activationDate = ""
    @State private var qsoCount = ""

    @ViewBuilder
    private var lookupSection: some View {
        Section("Find by Reference") {
            HStack {
                TextField("WWFF Reference (e.g., KFF-1234)", text: $referenceInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()

                Button("Look Up") {
                    lookupByReference()
                }
                .buttonStyle(.bordered)
                .disabled(referenceInput.isEmpty)
            }
        }
    }

    private func representativeDetailSection(
        _ rep: WWFFRepresentative
    ) -> some View {
        Section("Representative") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(rep.country, systemImage: "globe")
                        .font(.headline)
                    Spacer()
                    Text(rep.programCode)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.fill.tertiary)
                        .clipShape(Capsule())
                }

                Divider()

                contactRow(
                    label: "Coordinator",
                    callsign: rep.coordinatorCallsign,
                    name: rep.coordinatorName
                )

                if let logMgr = rep.logManagerCallsign {
                    contactRow(label: "Log Manager", callsign: logMgr, name: nil)
                }

                if let awardMgr = rep.awardManagerCallsign,
                   awardMgr != rep.coordinatorCallsign
                {
                    contactRow(label: "Award Manager", callsign: awardMgr, name: nil)
                }

                if let website = rep.website, let url = URL(string: website) {
                    Link(destination: url) {
                        Label(website, systemImage: "link")
                            .font(.subheadline)
                    }
                }

                if rep.email == nil {
                    Text("Email not publicly listed. Look up callsign on QRZ.com for contact info.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func contactRow(
        label: String,
        callsign: String,
        name: String?
    ) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            if let name {
                Text("\(name) (\(callsign))")
                    .font(.subheadline)
            } else {
                Text(callsign)
                    .font(.subheadline.monospaced())
            }
        }
    }

    private func emailComposeSection(
        _ rep: WWFFRepresentative
    ) -> some View {
        Section("Compose Email") {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Your Callsign", text: $userCallsign)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()

                TextField("Activation Date (YYYY-MM-DD)", text: $activationDate)
                    .keyboardType(.numbersAndPunctuation)

                TextField("Number of QSOs", text: $qsoCount)
                    .keyboardType(.numberPad)

                if let url = composeMailtoURL(for: rep) {
                    Link(destination: url) {
                        Label(
                            "Open in Mail",
                            systemImage: "envelope"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(userCallsign.isEmpty)
                } else {
                    Text(
                        "No email on file. Use QRZ.com to find \(rep.coordinatorCallsign)'s email."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var allRepresentativesSection: some View {
        let reps = searchResults.isEmpty
            ? WWFFRepresentativeDirectory.allRepresentatives
            : searchResults

        Section("All Programs (\(reps.count))") {
            ForEach(reps) { rep in
                Button {
                    selectedRepresentative = rep
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(rep.country)
                                .font(.subheadline)
                            Text(rep.coordinatorCallsign)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(rep.programCode)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.primary)
            }
        }
    }

    private func lookupByReference() {
        let trimmed = referenceInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        selectedRepresentative = WWFFRepresentativeDirectory.representative(
            forReference: trimmed
        )
    }

    private func performSearch(_ query: String) {
        if query.isEmpty {
            searchResults = []
            return
        }
        searchResults = WWFFRepresentativeDirectory.search(query)
        if searchResults.count == 1 {
            selectedRepresentative = searchResults.first
        }
    }

    private func composeMailtoURL(for rep: WWFFRepresentative) -> URL? {
        let ref = referenceInput.isEmpty
            ? "XXFF-0000"
            : referenceInput.uppercased()
        let programCode = WWFFRepresentativeDirectory.extractProgramCode(
            from: ref
        )
        let subject = WWFFRepresentativeDirectory.logSubmissionSubject(
            reference: ref,
            callsign: userCallsign.uppercased(),
            date: activationDate.isEmpty ? "TBD" : activationDate
        )
        let body = WWFFRepresentativeDirectory.logSubmissionBody(
            reference: ref,
            callsign: userCallsign.uppercased(),
            date: activationDate.isEmpty ? "TBD" : activationDate,
            qsoCount: Int(qsoCount) ?? 0,
            programCode: programCode
        )
        return WWFFRepresentativeDirectory.mailtoURL(
            representative: rep,
            subject: subject,
            body: body
        )
    }
}
