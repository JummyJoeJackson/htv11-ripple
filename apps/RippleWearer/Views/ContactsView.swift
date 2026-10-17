import RippleKit
import SwiftUI
import UIKit

/// Permanent contacts by name and phone number, each in Tier 1 or Tier 2,
/// plus one-hour temporary contacts, as cards with a filter across the top.
struct ContactsView: View {
    @Environment(WearerStore.self) private var store
    @State private var editing: EditingContact?
    @State private var showInvite = false
    @State private var filter: ContactFilter = .all
    @State private var removing: TemporaryContactView?

    private struct EditingContact: Identifiable {
        let id = UUID()
        let contact: PermanentContact
        let isNew: Bool
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(title: "Contacts") {
                    HeaderIconButton(systemImage: "plus", label: "Add contact") { addContact() }
                }

                FilterTabs(selection: $filter)

                ForEach(Tier.allCases, id: \.self) { tier in
                    if filter == .all || filter == ContactFilter(tier) {
                        let contacts = store.config.contacts.filter { $0.tier == tier }
                        SectionTitle(title: tier.label, note: tier == .one ? "Texted first" : "Texted if nobody in Tier 1 responds")
                        if contacts.isEmpty {
                            FormNote("Nobody in \(tier.label) yet.")
                        }
                        ForEach(contacts) { contact in
                            Button {
                                editing = EditingContact(contact: contact, isNew: false)
                            } label: {
                                ContactCard(name: contact.name, phone: contact.phone, tag: tier.label, tagTint: Theme.accent) {
                                    LocationLine(shared: contact.shareLocation)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens this contact to edit or remove.")
                        }
                    }
                }

                if filter == .all || filter == .temporary {
                    SectionTitle(title: "Temporary contacts", note: "Join Tier 1 while active")
                    if store.temporaryContacts.isEmpty {
                        FormNote("No one-hour contacts.")
                    }
                    ForEach(store.temporaryContacts) { contact in
                        TemporaryContactCard(contact: contact) { removing = contact }
                    }
                    Button {
                        showInvite = true
                    } label: {
                        Label("Invite someone for one hour", systemImage: "qrcode")
                    }
                    .buttonStyle(.rippleLink)
                    .font(Theme.labelBold)
                }

                Button {
                    addContact()
                } label: {
                    Label("Add contact", systemImage: "person.badge.plus")
                }
                .buttonStyle(.ripplePrimary)
                .padding(.top, 8)
            }
            .padding(Theme.spacing)
        }
        .rippleScreen(background: .two)
        .toolbar(.hidden, for: .navigationBar)
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
        .confirmationDialog("Remove \(removing?.name ?? "this contact") now?",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Remove now", role: .destructive) {
                if let contact = removing {
                    Task { await store.removeTemporary(contact) }
                }
                removing = nil
            }
            Button("Cancel", role: .cancel) { removing = nil }
        }
    }

    private func addContact() {
        editing = EditingContact(contact: PermanentContact(name: "", phone: ""), isNew: true)
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
}

private enum ContactFilter: CaseIterable {
    case all, tierOne, tierTwo, temporary

    init(_ tier: Tier) { self = tier == .one ? .tierOne : .tierTwo }

    var title: String {
        switch self {
        case .all: return "All"
        case .tierOne: return "Tier 1"
        case .tierTwo: return "Tier 2"
        case .temporary: return "Temporary"
        }
    }
}

/// Underlined text tabs: All, Tier 1, Tier 2, Temporary.
private struct FilterTabs: View {
    @Binding var selection: ContactFilter

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ContactFilter.allCases, id: \.self) { filter in
                let selected = filter == selection
                Button {
                    selection = filter
                } label: {
                    VStack(spacing: 6) {
                        Text(filter.title)
                            .font(selected ? Theme.labelBold : Theme.label)
                            .foregroundStyle(selected ? Theme.accent : Theme.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Capsule()
                            .fill(selected ? Theme.accent : .clear)
                            .frame(height: 3)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(filter.title)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.divider).frame(height: 1)
        }
    }
}

/// A contact as a white card: initials, name, phone, one detail line, a tag
/// and a chevron.
private struct ContactCard<Detail: View>: View {
    let name: String
    let phone: String
    let tag: String
    let tagTint: Color
    @ViewBuilder let detail: Detail

    var body: some View {
        HStack(spacing: 14) {
            InitialsCircle(name: name)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(Theme.body.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text(phone)
                    .font(Theme.label)
                    .foregroundStyle(Theme.secondaryText)
                detail
            }
            Spacer(minLength: 8)
            Text(tag)
                .font(Theme.labelBold)
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(tagTint.opacity(0.14), in: Capsule())
            Image(systemName: "chevron.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: Theme.listRowHeight, alignment: .leading)
        .rippleCard()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Two initials on a soft color picked from the name, so each person keeps
/// the same color.
private struct InitialsCircle: View {
    let name: String

    private static let tints: [Color] = [
        Theme.accent, Theme.safe, Color(red: 0x4F / 255, green: 0x46 / 255, blue: 0xE5 / 255), Theme.checkIn, Theme.responding,
    ]

    var body: some View {
        let initials = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        let tint = Self.tints[abs(name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }) % Self.tints.count]
        Text(initials.isEmpty ? "?" : initials)
            .font(.title3.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 52, height: 52)
            .background(tint.opacity(0.12), in: Circle())
            .accessibilityHidden(true)
    }
}

private struct LocationLine: View {
    let shared: Bool

    var body: some View {
        Label(shared ? "Shares location" : "Location not shared", systemImage: shared ? "location.fill" : "location.slash")
            .font(Theme.label)
            .foregroundStyle(shared ? Theme.accent : Theme.secondaryText)
    }
}

private struct TemporaryContactCard: View {
    let contact: TemporaryContactView
    let onRemove: () -> Void

    var body: some View {
        let removable = contact.state == .invited || contact.state == .active
        Button {
            if removable { onRemove() }
        } label: {
            ContactCard(name: contact.name, phone: contact.phone, tag: "Temporary", tagTint: Theme.safe) {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Label(stateText(at: context.date), systemImage: "clock")
                        .font(Theme.label)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!removable)
        .accessibilityHint(removable ? "Asks to remove this contact now." : "")
    }

    private func stateText(at date: Date) -> String {
        if contact.isEligible(at: date), let expires = contact.expiresAt {
            let minutes = max(1, Int(expires.timeIntervalSince(date) / 60))
            return "Expires in \(minutes) min"
        }
        if contact.state == .active { return "Expired" }
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
            RippleForm {
                Section {
                    TextField("Name", text: $contact.name)
                        .textContentType(.name)
                    TextField("Phone, with area code", text: $contact.phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                } header: {
                    SectionHeader("Contact")
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
                    FormNote("Adds a map link to their alert texts.")
                }
                if !isNew {
                    Section {
                        Button("Remove contact", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                        .frame(minHeight: Theme.minTarget)
                        .buttonStyle(.rippleDestructiveLink)
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
                    RippleForm {
                        Section {
                            TextField("Name", text: $name)
                            TextField("Phone, with area code", text: $phone)
                                .keyboardType(.phonePad)
                        } header: {
                            SectionHeader("Who")
                        }
                        Section {
                            Toggle("Share my location in alerts", isOn: $shareLocation)
                        } footer: {
                            FormNote("They join Tier 1 for one hour.")
                        }
                        Section {
                            Button {
                                Task {
                                    invitation = await store.inviteTemporary(name: name, phone: phone, shareLocation: shareLocation)
                                }
                            } label: {
                                Text("Create invitation")
                            }
                            .buttonStyle(.ripplePrimary)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || Phone.normalize(phone) == nil || store.pending != nil)
                            if let banner = store.banner, !banner.ok {
                                Label(banner.text, systemImage: "exclamationmark.triangle.fill")
                                    .font(Theme.label)
                                    .foregroundStyle(Theme.checkIn)
                            }
                        }
                    }
                }
            }
            .navigationTitle(invitation == nil ? "One-hour contact" : "Ask them to scan")
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
                Text("\(invitation.contact.name) scans this and taps \"I agree\". Their one hour starts then.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                if let url = URL(string: invitation.inviteURL) {
                    ShareLink(item: url) {
                        Label("Send the link instead", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.rippleSecondary)
                }
            }
            .padding(24)
        }
        .rippleScreen()
    }
}

#Preview("Contacts") {
    NavigationStack { ContactsView() }.environment(WearerStore())
}

#Preview("Contacts, largest text") {
    NavigationStack { ContactsView() }.environment(WearerStore()).dynamicTypeSize(.accessibility3)
}
