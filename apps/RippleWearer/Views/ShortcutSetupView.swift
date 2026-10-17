import RippleKit
import SwiftUI
import UIKit

/// All six installation links and the remaining device setup, in one place.
struct ShortcutSetupView: View {
    @Environment(WearerStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var showLinkError = false
    @State private var testContactId = ""
    @State private var replyText = ""
    @State private var senderName = ""
    private let links = ShortcutLinks.bundled

    var body: some View {
        RippleForm {
            Section {
                Text("Install each shortcut, tap Add Shortcut in Shortcuts, then return here to continue.")
                    .foregroundStyle(Theme.secondaryText)
                    .listRowBackground(Color.clear)
            }

            Section {
                ForEach(RippleShortcut.phone) { shortcut in
                    installRow(shortcut)
                }
                DisclosureGroup("Set up reply automations") {
                    ShortcutSetupStep(number: 1, text: "Open Shortcuts → Automation → + → Message. Leave Sender as anyone so temporary contacts can reply too.")
                    ShortcutSetupStep(number: 2, text: "Set Message Contains to Ripple accept. Choose Run Immediately → Next → Ripple Accept, passing it the message.")
                    Button("Copy Ripple accept") { UIPasteboard.general.string = "Ripple accept" }
                        .buttonStyle(.rippleLink)
                    ShortcutSetupStep(number: 3, text: "Add a second Message automation for Ripple join. Again choose Run Immediately and Ripple Accept. Keep both automations.")
                    Button("Copy Ripple join") { UIPasteboard.general.string = "Ripple join" }
                        .buttonStyle(.rippleLink)
                    Button {
                        openURL(URL(string: "shortcuts://")!) { accepted in
                            showLinkError = !accepted
                        }
                    } label: {
                        Label("Open Shortcuts", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.rippleLink)
                }

                DisclosureGroup("Test and troubleshoot") {
                    phoneChecks
                }
            } header: {
                SectionHeader("iPhone · 2 shortcuts")
            } footer: {
                FormNote("Keep both shortcut names. Both reply automations use Ripple Accept; Ripple runs Ripple Alert directly.")
            }

            Section {
                ForEach(RippleShortcut.watch) { shortcut in
                    installRow(shortcut)
                }
                DisclosureGroup("Assign gestures in the Watch app") {
                    ShortcutSetupStep(number: 1, text: "Install all four Watch shortcuts above. In each shortcut's details, turn on Show on Apple Watch and wait for it to sync. Install Ripple on your Watch first.")
                    ShortcutSetupStep(number: 2, text: "On your iPhone, open Watch → Accessibility → AssistiveTouch → Hand Gestures. Turn on AssistiveTouch and Hand Gestures.")
                    ShortcutSetupStep(number: 3, text: "Open each gesture, choose Shortcuts, and select the Ripple shortcut with the same name. Pinch may be called Tap, and double pinch may be called Double Tap.")
                    ShortcutSetupStep(number: 4, text: "Set Activation Gesture to None, so double clench can run its shortcut.")
                    ShortcutSetupStep(number: 5, text: "Return to Ripple Settings. Turn on Hand gestures to dismiss, choose a Dismiss gesture, and Save. Wait until Watch has your settings says Yes.")
                    ShortcutSetupStep(number: 6, text: "Keep Hand gestures to trigger alarm off while checking setup. With no alarm running, try each gesture and check the Gesture counter in Ripple on your Watch. During an alarm, complete your dismiss sequence with no more than 5 seconds between gestures.")
                    ShortcutSetupStep(number: 7, text: "To ask for help with a gesture, tell your contacts first. Turn on Hand gestures to trigger alarm, choose an Alarm gesture, and Save. Completing it texts your contacts immediately, even with no alarm running.")
                }
            } header: {
                SectionHeader("Apple Watch · 4 shortcuts")
            } footer: {
                FormNote("Optional, for AssistiveTouch gestures. These assignments apply across the Watch and turn off Apple's native double tap. Changing either Ripple sequence later doesn't require new shortcuts.")
            }
        }
        .navigationTitle("Ripple shortcuts")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Couldn't open Shortcuts", isPresented: $showLinkError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Check that Shortcuts is installed and that you have an internet connection, then try again.")
        }
        .onAppear {
            senderName = store.config.shortcutName
            if testContactId.isEmpty { testContactId = store.config.contacts.first?.id ?? "" }
        }
    }

    private func installRow(_ shortcut: RippleShortcut) -> some View {
        let url = links.url(for: shortcut)
        return Button {
            guard let url else { return }
            openURL(url) { accepted in
                // Opening a link doesn't establish that the user added the shortcut.
                showLinkError = !accepted
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: shortcut.rawValue)
                        .font(Theme.labelBold)
                        .foregroundStyle(Theme.text)
                    Text(LocalizedStringKey(url == nil ? "Install link coming soon" : shortcut.detail))
                        .font(Theme.label)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 4)
                Label("Install", systemImage: "arrow.down.circle")
                    .font(Theme.labelBold)
                    .fixedSize()
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.rippleLink)
        .disabled(url == nil)
        .accessibilityLabel("Install \(shortcut.rawValue)")
        .accessibilityHint(url == nil ? "The install link isn't available yet." : "Opens the shortcut's installation page. Tap Add Shortcut, then return to Ripple.")
    }

    @ViewBuilder
    private var phoneChecks: some View {
        if store.config.contacts.isEmpty {
            FormNote("Add a contact in Ripple before sending a test.")
        } else {
            Picker("Send to", selection: $testContactId) {
                ForEach(store.config.contacts) { contact in
                    Text(contact.name).tag(contact.id)
                }
            }
            Button("Send test message") {
                if let contact = store.config.contacts.first(where: { $0.id == testContactId }) {
                    store.sendTestMessage(to: contact)
                }
            }
            .buttonStyle(.rippleLink)
            .disabled(testContactId.isEmpty)
        }
        if let result = store.testResult { FormNote(result) }
        FormNote("Confirm the text arrived on the other phone. Then test a real reply to check your automation. Sending while this iPhone is locked or Ripple is in the background is unverified.")

        TextField("Ripple accept 4821 or Ripple join 583921", text: $replyText)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
        Button("Try this reply") {
            store.acceptReply(text: replyText, from: nil)
            replyText = ""
        }
        .buttonStyle(.rippleLink)
        .disabled(ReplyCode.acceptCode(in: replyText) == nil && JoinCode.code(in: replyText) == nil)
        FormNote("For troubleshooting only. This bypasses the Message automation. Use an active alert or invitation code.")

        TextField("Alert shortcut name", text: $senderName)
            .autocorrectionDisabled()
        Button("Save shortcut name") {
            var updated = store.config
            updated.shortcutName = senderName.trimmingCharacters(in: .whitespacesAndNewlines)
            store.save(updated)
        }
        .buttonStyle(.rippleLink)
        .disabled(senderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || senderName == store.config.shortcutName)
    }
}

private struct ShortcutSetupStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(Theme.labelBold)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Theme.accent, in: Circle())
                .accessibilityHidden(true)
            Text(LocalizedStringKey(text))
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number). \(text)")
    }
}

#Preview("Ripple shortcuts") {
    NavigationStack { ShortcutSetupView() }.environment(WearerStore())
}

#Preview("Ripple shortcuts, largest text") {
    NavigationStack { ShortcutSetupView() }.environment(WearerStore()).dynamicTypeSize(.accessibility3)
}
