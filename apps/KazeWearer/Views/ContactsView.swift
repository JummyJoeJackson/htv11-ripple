import KazeKit
import SwiftUI

struct ContactsView: View {
    @Environment(WearerStore.self) private var store
    @State private var contacts: [ContactInput] = []
    @State private var editing: EditingContact?
    @State private var loaded = false

    private struct EditingContact: Identifiable {
        let id = UUID()
        let index: Int?
        let contact: ContactInput
    }

    var body: some View {
        List {
            Section {
                if contacts.isEmpty {
                    Text("No trusted contacts yet.").foregroundStyle(.secondary)
                }
                ForEach(contacts.indices, id: \.self) { index in
                    Button {
                        editing = EditingContact(index: index, contact: contacts[index])
                    } label: {
                        HStack {
                            Text("\(index + 1).").foregroundStyle(.secondary)
                            VStack(alignment: .leading) {
                                Text(contacts[index].name).foregroundStyle(.primary)
                                Text(contacts[index].phone).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                    }
                }
                .onMove { contacts.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { contacts.remove(atOffsets: $0) }
            } header: {
                Text("Alerted in this order")
            } footer: {
                Text("If an accepted temporary helper is covering you, they're alerted first. Then these contacts, one at a time, until someone acknowledges.")
            }

            Section {
                Button {
                    editing = EditingContact(index: nil, contact: ContactInput(name: "", phone: ""))
                } label: {
                    Label("Add trusted contact", systemImage: "person.badge.plus")
                }
                .disabled(contacts.count >= 6)
            }

            Section {
                Button {
                    Task { _ = await store.saveContacts(contacts) }
                } label: {
                    Text("Save contacts").frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Trusted contacts")
        .toolbar { EditButton() }
        .sheet(item: $editing) { item in
            ContactEditView(contact: item.contact) { updated in
                if let index = item.index, contacts.indices.contains(index) {
                    contacts[index] = updated
                } else {
                    contacts.append(updated)
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            contacts = (store.state?.profile.contacts ?? []).map {
                ContactInput(id: $0.id, name: $0.name, phone: $0.phone, share: $0.share)
            }
            loaded = true
        }
    }
}

private struct ContactEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State var contact: ContactInput
    let onSave: (ContactInput) -> Void

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
                    Toggle("Your name", isOn: $contact.share.name)
                    Toggle("Venue", isOn: $contact.share.venue)
                    Toggle("Last-known location", isOn: $contact.share.location)
                    Toggle("Your phone number", isOn: $contact.share.contactInfo)
                    Toggle("Help card", isOn: $contact.share.helpCard)
                } header: {
                    Text("During an alert they may see")
                } footer: {
                    Text("Nothing is shared outside an alert.")
                }
            }
            .navigationTitle(contact.id == nil ? "New contact" : "Edit contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(contact)
                        dismiss()
                    }
                    .disabled(contact.name.trimmingCharacters(in: .whitespaces).isEmpty || contact.phone.filter(\.isNumber).count < 10)
                }
            }
        }
    }
}
