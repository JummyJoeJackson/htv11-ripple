import KazeKit
import SwiftUI
import UIKit

/// A rounded card used for every section of the home screen.
struct Card<Content: View>: View {
    let title: String?
    let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Colour plus icon plus text: status is never shown by colour alone.
struct ToneBadge: View {
    let tone: StatusTone

    var body: some View {
        Label(tone.label, systemImage: tone.symbol)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tone.color.opacity(0.18), in: Capsule())
            .foregroundStyle(tone == .awaiting ? Color.primary : tone.color)
    }
}

/// Seconds remaining until a backend deadline, corrected for clock offset.
/// Display only: no timer on this device can cause or prevent an alert.
struct CountdownText: View {
    let deadline: Date
    let serverOffset: TimeInterval
    var prefix = ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = Int(deadline.timeIntervalSince(context.date.addingTimeInterval(serverOffset)).rounded(.up))
            Text(remaining > 0 ? "\(prefix)\(format(remaining))" : "Deadline passed")
                .monospacedDigit()
        }
    }

    private func format(_ seconds: Int) -> String {
        if seconds < 120 { return "\(seconds) s" }
        let minutes = seconds / 60
        if minutes < 120 { return "\(minutes) min \(seconds % 60) s" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }
}

struct BigButton: View {
    let title: String
    let systemImage: String
    var tint: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.title3.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
    }
}

extension Date {
    var shortTime: String {
        formatted(date: .omitted, time: .shortened)
    }

    var timeWithSeconds: String {
        formatted(.dateTime.hour().minute().second())
    }
}
