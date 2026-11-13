import MapKit
import SwiftUI

// MARK: - EventDetailView

struct EventDetailView: View {
    // MARK: Internal

    @EnvironmentObject var config: ServerConfig

    let eventId: String

    var body: some View {
        Group {
            if let event {
                eventContent(event)
            } else if isLoading {
                ProgressView()
            } else if let error {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
            }
        }
        .navigationTitle("Event")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if event != nil {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingEditSheet = true
                        } label: {
                            Label("Edit Event", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            showingDeleteAlert = true
                        } label: {
                            Label("Delete Event", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .task { await loadEvent() }
        .refreshable { await loadEvent() }
        .sheet(isPresented: $showingRejectSheet) {
            if let event {
                RejectEventSheet(eventId: event.id) { updated in
                    self.event = updated
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            if let event {
                EditEventSheet(event: event) { updated in
                    self.event = updated
                }
            }
        }
        .alert("Delete Event?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await deleteEvent() }
            }
        } message: {
            Text("This will permanently delete this event.")
        }
        .alert("Review", isPresented: .init(
            get: { reviewSuccess != nil },
            set: {
                if !$0 {
                    reviewSuccess = nil
                }
            }
        )) {
            Button("OK") { reviewSuccess = nil }
        } message: {
            if let msg = reviewSuccess {
                Text(msg)
            }
        }
    }

    // MARK: Private

    @State private var event: EventDetailResponse?
    @State private var submitterStats: SubmitterStatsResponse?
    @State private var isLoading = true
    @State private var error: String?
    @State private var showingRejectSheet = false
    @State private var showingEditSheet = false
    @State private var showingDeleteAlert = false
    @State private var isReviewing = false
    @State private var reviewSuccess: String?
    @Environment(\.dismiss) private var dismiss

    private var api: APIClient {
        APIClient(config: config)
    }

    private func loadEvent() async {
        isLoading = true
        error = nil
        do {
            event = try await api.getEvent(id: eventId)
            if let callsign = event?.submittedBy {
                submitterStats = try? await api.getSubmitterHistory(callsign: callsign)
            }
        } catch where !error.isCancellation {
            error = error.localizedDescription
        } catch {}
        isLoading = false
    }

    private func approveEvent() async {
        isReviewing = true
        do {
            let updated = try await api.reviewEvent(id: eventId, action: "approve")
            event = updated
            reviewSuccess = "Event approved."
        } catch {
            self.error = error.localizedDescription
        }
        isReviewing = false
    }

    private func deleteEvent() async {
        do {
            try await api.deleteEvent(id: eventId)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - EventDetailView Sections

private extension EventDetailView {
    func eventContent(_ event: EventDetailResponse) -> some View {
        List {
            submitterSection(event)
            eventInfoSection(event)
            locationSection(event)
            if event.status == "pending" {
                reviewActionsSection(event)
            }
            if event.status == "rejected" {
                rejectionSection(event)
            }
            if event.status == "approved" {
                Section {
                    Label("This event is live and visible to users.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
    }

    func submitterSection(_ event: EventDetailResponse) -> some View {
        Section("Submitter") {
            HStack {
                Text(event.submittedBy).font(.headline).fontDesign(.monospaced)
                Spacer()
                EventStatusBadge(status: event.status)
            }
            LabeledContent("Submitted") {
                Text(event.createdAt.formatted(date: .abbreviated, time: .shortened))
            }
            if let stats = submitterStats {
                LabeledContent("History") {
                    Text("\(stats.totalApproved) approved, \(stats.totalRejected) rejected, " +
                        "\(stats.totalPending) pending")
                        .font(.caption)
                }
            }
        }
    }

    func eventInfoSection(_ event: EventDetailResponse) -> some View {
        Section("Event Details") {
            LabeledContent("Name") { Text(event.name) }
            LabeledContent("Type") { EventTypeBadge(eventType: event.eventType) }
            LabeledContent("Date") {
                VStack(alignment: .trailing) {
                    Text(event.startDate.formatted(date: .abbreviated, time: .shortened))
                    if let endDate = event.endDate {
                        Text("to \(endDate.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(event.timezone).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            if let cost = event.cost, !cost.isEmpty {
                LabeledContent("Cost") { Text(cost) }
            }
            if let url = event.url, !url.isEmpty {
                LabeledContent("Website") {
                    Link(url, destination: URL(string: url) ?? URL(string: "about:blank")!)
                        .font(.caption).lineLimit(1)
                }
            }
            if let description = event.description, !description.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description").font(.subheadline).foregroundStyle(.secondary)
                    Text(description).font(.body)
                }
            }
        }
    }

    func locationSection(_ event: EventDetailResponse) -> some View {
        Section("Location") {
            if let venue = event.venueName, !venue.isEmpty {
                LabeledContent("Venue") { Text(venue) }
            }
            LabeledContent("Address") { Text(event.address).multilineTextAlignment(.trailing) }
            LabeledContent("City") { Text(locationText(event)) }
            Map(initialPosition: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: event.latitude, longitude: event.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            ))) {
                Marker(event.name, coordinate: CLLocationCoordinate2D(
                    latitude: event.latitude, longitude: event.longitude
                ))
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }

    func reviewActionsSection(_ event: EventDetailResponse) -> some View {
        Section("Review") {
            HStack(spacing: 16) {
                Button { Task { await approveEvent() } } label: {
                    Label("Approve", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.green).disabled(isReviewing)
                Button { showingRejectSheet = true } label: {
                    Label("Reject", systemImage: "xmark.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.red).disabled(isReviewing)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        }
    }

    func rejectionSection(_ event: EventDetailResponse) -> some View {
        Section("Rejection") {
            if let reviewedBy = event.reviewedBy {
                LabeledContent("Reviewed by") { Text(reviewedBy) }
            }
            if let reviewedAt = event.reviewedAt {
                LabeledContent("Reviewed") {
                    Text(reviewedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
            if let reason = event.rejectionReason, !reason.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reason").font(.subheadline).foregroundStyle(.secondary)
                    Text(reason).foregroundStyle(.red)
                }
            }
        }
    }

    func locationText(_ event: EventDetailResponse) -> String {
        if let state = event.state, !state.isEmpty {
            return "\(event.city), \(state), \(event.country)"
        }
        return "\(event.city), \(event.country)"
    }
}

// MARK: - RejectEventSheet

struct RejectEventSheet: View {
    // MARK: Internal

    @EnvironmentObject var config: ServerConfig

    let eventId: String
    let onRejected: (EventDetailResponse) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Quick Reasons") {
                    ForEach(quickReasons, id: \.self) { quickReason in
                        Button {
                            reason = quickReason
                        } label: {
                            HStack {
                                Text(quickReason)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if reason == quickReason {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }

                Section("Custom Reason") {
                    TextField("Reason for rejection", text: $reason, axis: .vertical)
                        .lineLimit(3 ... 6)
                }

                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("Reject Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Reject") {
                        Task { await reject() }
                    }
                    .disabled(reason.isEmpty || isSubmitting)
                    .tint(.red)
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var reason = ""
    @State private var isSubmitting = false
    @State private var error: String?

    private let quickReasons = [
        "Incomplete information",
        "Duplicate event",
        "Not ham radio related",
        "Inappropriate content",
    ]

    private func reject() async {
        isSubmitting = true
        error = nil
        let api = APIClient(config: config)
        do {
            let updated = try await api.reviewEvent(id: eventId, action: "reject", reason: reason)
            onRejected(updated)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSubmitting = false
    }
}

// MARK: - EditEventSheet

struct EditEventSheet: View {
    // MARK: Lifecycle

    init(event: EventDetailResponse, onSaved: @escaping (EventDetailResponse) -> Void) {
        self.event = event
        self.onSaved = onSaved
        _name = State(initialValue: event.name)
        _description = State(initialValue: event.description ?? "")
        _venueName = State(initialValue: event.venueName ?? "")
        _address = State(initialValue: event.address)
        _city = State(initialValue: event.city)
        _state = State(initialValue: event.state ?? "")
        _country = State(initialValue: event.country)
        _cost = State(initialValue: event.cost ?? "")
        _url = State(initialValue: event.url ?? "")
    }

    // MARK: Internal

    @EnvironmentObject var config: ServerConfig

    let event: EventDetailResponse
    let onSaved: (EventDetailResponse) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    TextField("Name", text: $name)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3 ... 6)
                }

                Section("Location") {
                    TextField("Venue Name", text: $venueName)
                    TextField("Address", text: $address)
                    TextField("City", text: $city)
                    TextField("State", text: $state)
                    TextField("Country", text: $country)
                }

                Section("Details") {
                    TextField("Cost", text: $cost)
                    TextField("Website URL", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                }

                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(name.isEmpty || address.isEmpty || isSubmitting)
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var description: String
    @State private var venueName: String
    @State private var address: String
    @State private var city: String
    @State private var state: String
    @State private var country: String
    @State private var cost: String
    @State private var url: String
    @State private var isSubmitting = false
    @State private var error: String?

    private func save() async {
        isSubmitting = true
        error = nil
        let api = APIClient(config: config)
        let request = UpdateEventRequest(
            name: name,
            description: description.isEmpty ? nil : description,
            venueName: venueName.isEmpty ? nil : venueName,
            address: address,
            city: city,
            state: state.isEmpty ? nil : state,
            country: country,
            cost: cost.isEmpty ? nil : cost,
            url: url.isEmpty ? nil : url
        )
        do {
            let updated = try await api.updateEvent(id: event.id, request)
            onSaved(updated)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSubmitting = false
    }
}
