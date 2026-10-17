import CoreImage.CIFilterBuiltins
import KazeKit
import SwiftUI
import UIKit

/// Invite consenting venue staff to cover you for a set period. They're not
/// counted as coverage until they verify their phone and accept.
struct InviteHelperView: View {
    @Environment(WearerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var helperName = ""
    @State private var helperPhone = ""
    @State private var venue = ""
    @State private var minutes = 60
    @State private var share = SharePermissions.helperDefault
    @State private var invitation: InviteHelperResponse?

    var body: some View {
        NavigationStack {
            Group {
                if let invitation {
                    InvitationQRView(invitation: invitation)
                } else {
                    form
                }
            }
            .navigationTitle(invitation == nil ? "Invite a helper" : "Show this to the helper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(invitation == nil ? "Cancel" : "Done") { dismiss() }
                }
            }
        }
        .onAppear {
            if venue.isEmpty { venue = store.state?.session?.venue ?? "" }
        }
    }

    private var form: some View {
        Form {
            Section {
                TextField("Helper's name", text: $helperName)
                TextField("Helper's phone, with area code", text: $helperPhone)
                    .keyboardType(.phonePad)
                TextField("Venue", text: $venue)
            } header: {
                Text("Helper")
            } footer: {
                Text("Use preapproved staff. Verifying a phone number doesn't prove employment or training.")
            }

            Section("Coverage") {
                Picker("Covers you for", selection: $minutes) {
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                    Text("2 hours").tag(120)
                    Text("4 hours").tag(240)
                }
            }

            Section {
                Toggle("Your name", isOn: $share.name)
                Toggle("Venue", isOn: $share.venue)
                Toggle("Last-known location", isOn: $share.location)
                Toggle("Your phone number", isOn: $share.contactInfo)
                Toggle("Help card", isOn: $share.helpCard)
            } header: {
                Text("During an alert they may see")
            }

            Section {
                Button {
                    Task {
                        invitation = await store.inviteHelper(InviteHelperRequest(
                            helperName: helperName, helperPhone: helperPhone, venue: venue, durationMinutes: minutes, share: share
                        ))
                    }
                } label: {
                    Text("Create invitation").frame(maxWidth: .infinity)
                }
                .disabled(helperName.isEmpty || helperPhone.filter(\.isNumber).count < 10 || venue.isEmpty || store.pending != nil)
                if let banner = store.banner, !banner.ok {
                    Text(banner.text).foregroundStyle(.red)
                }
            }
        }
    }
}

private struct InvitationQRView: View {
    let invitation: InviteHelperResponse

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let image = QRCode.image(for: invitation.enrollURL) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 280)
                        .padding(16)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityLabel("QR code for the helper invitation")
                }
                Text("\(invitation.coverage.helperName) scans this to verify their phone and accept coverage at \(invitation.coverage.venue) until \(invitation.coverage.endsAt.shortTime).")
                    .multilineTextAlignment(.center)
                Text("The code only shows the coverage terms. Nothing about you is shown unless there's an alert.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let url = URL(string: invitation.enrollURL) {
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

enum QRCode {
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        let context = CIContext()
        guard let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
