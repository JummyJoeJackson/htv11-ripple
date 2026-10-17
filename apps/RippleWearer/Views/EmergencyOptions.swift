import RippleKit
import SwiftUI
import UIKit

/// Ways to get help from the Home "Call for Help" button: call 911 (first),
/// call one of your contacts, or text all of them a Ripple help alert. Each action
/// asks once more before it runs, so a tremor tap can't set it off.
struct EmergencyOptionsSheet: View {
    @Environment(WearerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private enum Pending: Identifiable {
        case call(name: String, phone: String)
        case textAll
        case emergency

        var id: String {
            switch self {
            case .call(_, let phone): return "call-\(phone)"
            case .textAll: return "text"
            case .emergency: return "911"
            }
        }
    }

    @State private var pending: Pending?

    var body: some View {
        let contacts = callableContacts
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: "Emergency services")
                    OptionRow(icon: "staroflife.fill", tint: Theme.alert,
                              title: "Call 911",
                              detail: "For a medical emergency") {
                        pending = .emergency
                    }
                    FormNote("Ripple isn't an emergency service. Calling 911 uses your iPhone's phone app.")
                    SectionTitle(title: "Call a contact")
                    if contacts.isEmpty {
                        FormNote("Add a contact first, so you have someone to call.")
                    }
                    ForEach(contacts, id: \.phone) { contact in
                        OptionRow(icon: "phone.fill", tint: Theme.accent,
                                  title: "Call \(contact.name)",
                                  detail: contact.detail) {
                            pending = .call(name: contact.name, phone: contact.phone)
                        }
                    }

                    SectionTitle(title: "Text everyone")
                    OptionRow(icon: "message.fill", tint: Theme.checkIn,
                              title: "Send a help alert",
                              detail: "Texts all your contacts now") {
                        pending = .textAll
                    }

                }
                .padding(Theme.spacing)
            }
            .rippleScreen(background: .three)
            .navigationTitle("Get help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .confirmationDialog(Text(confirmTitle), isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                                titleVisibility: .visible, presenting: pending) { action in
                Button(LocalizedStringKey(confirmButton(action)), role: .destructive) { run(action) }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var confirmTitle: LocalizedStringKey {
        switch pending {
        case .call(let name, _): return "Call \(name)?"
        case .textAll: return "Text all your contacts for help?"
        case .emergency: return "Call 911?"
        case nil: return ""
        }
    }

    private func confirmButton(_ action: Pending) -> String {
        switch action {
        case .call: return "Call"
        case .textAll: return "Send help alert"
        case .emergency: return "Call 911"
        }
    }

    private func run(_ action: Pending) {
        switch action {
        case .call(_, let phone):
            call(phone)
        case .textAll:
            store.requestHelpFromPhone()
            dismiss()
        case .emergency:
            call("911")
        }
        pending = nil
    }

    private func call(_ number: String) {
        guard let url = URL(string: "tel://\(number)") else { return }
        openURL(url) { accepted in
            if !accepted {
                store.banner = Banner(text: "This device can't make phone calls.", ok: false)
            }
        }
    }

    /// Tier 1 first, then Tier 2, then active one-hour contacts.
    private var callableContacts: [(name: String, phone: String, detail: String)] {
        let permanent = store.config.contacts
            .sorted { $0.tier.rawValue < $1.tier.rawValue }
            .compactMap { contact -> (String, String, String)? in
                guard let phone = Phone.normalize(contact.phone) else { return nil }
                return (contact.name, phone, "\(contact.tier.label) · \(contact.phone)")
            }
        let temporary = store.temporaryContacts
            .filter { $0.isEligible(at: Date()) }
            .compactMap { contact -> (String, String, String)? in
                guard let phone = Phone.normalize(contact.phone) else { return nil }
                return (contact.name, phone, "One-hour contact · \(contact.phone)")
            }
        return (permanent + temporary).map { (name: $0.0, phone: $0.1, detail: $0.2) }
    }
}

/// One big option: colored icon, title, detail and a chevron.
private struct OptionRow: View {
    let icon: String
    let tint: Color
    let title: LocalizedStringKey
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(tint, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.body.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Text(LocalizedStringKey(detail))
                        .font(Theme.label)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: Theme.listRowHeight, alignment: .leading)
            .rippleCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Asks before it goes ahead.")
    }
}

#Preview("Get help") {
    EmergencyOptionsSheet().environment(WearerStore())
}
