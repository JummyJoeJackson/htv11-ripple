#if os(iOS)
import SwiftUI
import UIKit

public extension View {
    /// A visible dismissal control for text, multiline and number keyboards.
    /// Uses the keyboard safe area so it also works in sheets and onboarding.
    func keyboardDismissControl() -> some View {
        modifier(KeyboardDismissControl())
    }
}

private struct KeyboardDismissControl: ViewModifier {
    @State private var keyboardVisible = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if keyboardVisible {
                    HStack {
                        Spacer()
                        Button {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        } label: {
                            Label("Done", systemImage: "checkmark")
                                .font(.body.weight(.semibold))
                                .frame(minHeight: 44)
                                .padding(.horizontal, 12)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                        .accessibilityLabel("Done editing")
                        .accessibilityHint("Hides the keyboard without changing your text.")
                    }
                    .padding(.horizontal, 12)
                    .background(.regularMaterial)
                    .overlay(alignment: .top) { Divider() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                keyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardVisible = false
            }
    }
}
#endif
