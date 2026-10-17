import SwiftUI
import UIKit

struct PinSetupView: View {
    @Environment(WearerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var safety = ""
    @State private var duress = ""

    private var valid: Bool {
        (4...8).contains(safety.count) && (4...8).contains(duress.count) && safety != duress
            && safety.allSatisfy(\.isNumber) && duress.allSatisfy(\.isNumber)
    }

    var body: some View {
        Form {
            Section {
                SecureField("4 to 8 digits", text: $safety)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
            } header: {
                Text("Safety PIN")
            } footer: {
                Text("Cancels a false alarm. Everyone already contacted gets an update.")
            }

            Section {
                SecureField("4 to 8 digits, different from the safety PIN", text: $duress)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
            } header: {
                Text("Duress PIN")
            } footer: {
                Text("Looks exactly like a cancellation on your screen, but silently sends or keeps the alert going. Use it if someone is making you cancel.")
            }

            Section {
                Button {
                    Task {
                        if await store.savePins(safety: safety, duress: duress) {
                            dismiss()
                        }
                    }
                } label: {
                    Text("Save PINs").frame(maxWidth: .infinity)
                }
                .disabled(!valid)
                if !safety.isEmpty && safety == duress {
                    Text("The two PINs must be different.").foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("PINs")
    }
}

/// One PIN screen for both PINs. The safety PIN and the duress PIN produce the
/// same result here; only the server knows which one was entered.
struct PinPadView: View {
    @Environment(WearerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    @State private var done = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(.green)
                    Text("Cancelled.")
                        .font(.largeTitle.weight(.bold))
                } else {
                    Text("Enter your PIN to cancel")
                        .font(.title2.weight(.semibold))
                    SecureField("PIN", text: $pin)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .font(.system(.largeTitle, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                        .focused($focused)
                    if let error {
                        Text(error).foregroundStyle(.red).multilineTextAlignment(.center)
                    }
                    BigButton(title: "Submit", systemImage: "lock.open.fill") {
                        submit()
                    }
                    .disabled(pin.count < 4 || store.pending != nil)
                }
                Spacer()
            }
            .padding(24)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(done ? "Close" : "Back") { dismiss() }
                }
            }
            .onAppear { focused = true }
        }
    }

    private func submit() {
        let entered = pin
        Task {
            if await store.cancelWithPin(entered) {
                error = nil
                done = true
                pin = ""
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                dismiss()
            } else {
                error = store.banner?.text ?? "Not confirmed."
                pin = ""
            }
        }
    }
}
