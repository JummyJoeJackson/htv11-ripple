import RippleKit
import SwiftUI
import UIKit

/// Permanent contacts by name and phone number, each in Tier 1 or Tier 2,
/// plus one-hour temporary contacts.
struct ContactsView: View {
    @Environment(WearerStore.self) private var store
    @State private var editing: EditingContact?
    @State private var showInvite = false

    private struct EditingContact: Identifiable {
        let id = UUID()
        let contact: PermanentContact
        let isNew: Bool
    }

    var body: some View {
        List {
            ForEach(Tier.allCases, id: \.self) { tier in
                Section {
                    let contacts = store.config.contacts.filter { $0.tier == tier }
                    if contacts.isEmpty {
                        Text("Nobody in \(tier.label) yet.").foregroundStyle(.secondary)
                    }
                    ForEach(contacts) { contact in
                        Button {
                            editing = EditingContact(contact: contact, isNew: false)
                        } label: {
                            ContactRow(name: contact.name, phone: contact.phone, shareLocation: contact.shareLocation)
                        }
                    }
                    .onDelete { offsets in delete(offsets, in: tier) }
                } header: {
                    Text(tier.label)
                } footer: {
                    Text(tier == .one
                         ? "Texted first if you don't respond. Active temporary contacts join Tier 1."
                         : "Texted if nobody in Tier 1 taps their link within the acknowledge window.")
                }
            }

            Section {
                Button {
                    editing = EditingContact(contact: PermanentContact(name: "", phone: ""), isNew: true)
                } label: {
                    Label("Add contact", systemImage: "person.badge.plus")
                }
            }

            Section {
                if store.temporaryContacts.isEmpty {
                    Text("No temporary contacts.").foregroundStyle(.secondary)
                }
                ForEach(store.temporaryContacts) { contact in
                    TemporaryContactRow(contact: contact)
                }
                Button {
                    showInvite = true
                } label: {
                    Label("Invite for one hour", systemImage: "qrcode")
                }
            } header: {
                Text("Temporary contacts")
            } footer: {
                Text("Someone nearby, such as a friend at the venue, can agree to be a contact for one hour. They're texted with Tier 1 until the session ends or you remove them.")
            }
        }
        .navigationTitle("Contacts")
        .sheet(item: $editing) { item in
            ContactEditView(contact: item.contact, isNew: item.isNew) { updated in
                save(updated)
            } onDelete: {
                remove(item.contact.id)
            }
        }
        .sheet(isPresented: $showInvite) {
            InviteTemporaryView()
        }
    }

    private func save(_ contact: PermanentContact) {
        var config = store.config
        if let index = config.contacts.firstIndex(where: { $0.id == contact.id }) {
            config.contacts[index] = contact
        } else {
            config.contacts.append(contact)
        }
        store.save(config)
    }

    private func remove(_ id: String) {
        var config = store.config
        config.contacts.removeAll { $0.id == id }
        store.save(config)
    }

    private func delete(_ offsets: IndexSet, in tier: Tier) {
        let contacts = store.config.contacts.filter { $0.tier == tier }
        let ids = offsets.map { contacts[$0].id }
        var config = store.config
        config.contacts.removeAll { ids.contains($0.id) }
        store.save(config)
    }
}

private struct ContactRow: View {
    let name: String
    let phone: String
    let shareLocation: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(name).foregroundStyle(.primary)
                Text(phone).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Label(shareLocation ? "Location on" : "Location off", systemImage: shareLocation ? "location.fill" : "location.slash")
                .font(.caption)
                .foregroundStyle(shareLocation ? Color.blue : Color.secondary)
        }
    }
}

private struct TemporaryContactRow: View {
    @Environment(WearerStore.self) private var store
    let contact: TemporaryContactView

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ContactRow(name: contact.name, phone: contact.phone, shareLocation: contact.shareLocation)
            }
            TimelineView(.periodic(from: .now, by: 5)) { context in
                Text(stateText(at: context.date))
                    .font(.caption)
                    .foregroundStyle(contact.isEligible(at: context.date) ? Color.green : Color.secondary)
            }
            if contact.state == .invited || contact.state == .active {
                Button("Remove now", role: .destructive) {
                    Task { await store.removeTemporary(contact) }
                }
                .font(.subheadline)
            }
        }
    }

    private func stateText(at date: Date) -> String {
        if contact.isEligible(at: date), let expires = contact.expiresAt {
            let consent = contact.consentAt.map { "Agreed at \($0.shortTime). " } ?? ""
            return consent + "Active until \(expires.shortTime)."
        }
        if contact.state == .active { return "Expired." }
        return contact.state.label
    }
}

private struct ContactEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State var contact: PermanentContact
    let isNew: Bool
    let onSave: (PermanentContact) -> Void
    let onDelete: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Contact") {
                    TextField("Name", text: $contact.name)
                        .textContentType(.name)
                    TextField("Phone, with area code", text: $contact.phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                }
                Section {
                    Picker("Tier", selection: $contact.tier) {
                        Text("Tier 1: texted first").tag(Tier.one)
                        Text("Tier 2: if Tier 1 doesn't respond").tag(Tier.two)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    Toggle("Share my location in alerts", isOn: $contact.shareLocation)
                } footer: {
                    Text("Off by default. When on, alert texts to this contact include a map link from one location fix taken when the alarm starts.")
                }
                if !isNew {
                    Section {
                        Button("Remove contact", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New contact" : "Edit contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(contact)
                        dismiss()
                    }
                    .disabled(contact.name.trimmingCharacters(in: .whitespaces).isEmpty || Phone.normalize(contact.phone) == nil)
                }
            }
        }
    }
}

/// Invite someone for a one-hour session. They agree on a web page, which
/// records their consent; they're not texted until then.
private struct InviteTemporaryView: View {
    @Environment(WearerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var phone = ""
    @State private var shareLocation = false
    @State private var invitation: InviteTemporaryResponse?

    var body: some View {
        NavigationStack {
            Group {
                if let invitation {
                    InvitationQRView(invitation: invitation)
                } else {
                    Form {
                        Section("Who") {
                            TextField("Name", text: $name)
                            TextField("Phone, with area code", text: $phone)
                                .keyboardType(.phonePad)
                        }
                        Section {
                            Toggle("Share my location in alerts", isOn: $shareLocation)
                        } footer: {
                            Text("They join Tier 1 for one hour from when they agree.")
                        }
                        Section {
                            Button {
                                Task {
                                    invitation = await store.inviteTemporary(name: name, phone: phone, shareLocation: shareLocation)
                                }
                            } label: {
                                Text("Create invitation").frame(maxWidth: .infinity)
                            }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || Phone.normalize(phone) == nil || store.pending != nil)
                            if let banner = store.banner, !banner.ok {
                                Text(banner.text).foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
            .navigationTitle(invitation == nil ? "Temporary contact" : "Ask them to scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(invitation == nil ? "Cancel" : "Done") { dismiss() }
                }
            }
        }
    }
}

private struct InvitationQRView: View {
    let invitation: InviteTemporaryResponse

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let image = QRCode.image(for: invitation.inviteURL) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 280)
                        .padding(16)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityLabel("QR code for the temporary contact invitation")
                }
                Text("\(invitation.contact.name) scans this and taps \"I agree\". Their one-hour session starts then.")
                    .multilineTextAlignment(.center)
                if let url = URL(string: invitation.inviteURL) {
                    ShareLink(item: url) {
                        Label("Send the link instead", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(24)
        }
    }
}
