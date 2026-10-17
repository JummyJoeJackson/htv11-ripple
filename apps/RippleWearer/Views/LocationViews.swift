import MapKit
import RippleKit
import SwiftUI

/// A map with a pin and a circle showing how accurate a location fix is.
struct LocationMap: View {
    let fix: LocationFix

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: fix.latitude, longitude: fix.longitude)
    }

    var body: some View {
        Map(initialPosition: .camera(MapCamera(centerCoordinate: coordinate, distance: max(600, fix.accuracyMeters * 8)))) {
            MapCircle(center: coordinate, radius: max(fix.accuracyMeters, 5))
                .foregroundStyle(Theme.accent.opacity(0.18))
                .stroke(Theme.accent, lineWidth: 2)
            Marker("You", systemImage: "person.fill", coordinate: coordinate)
                .tint(Theme.accent)
        }
        .mapControlVisibility(.hidden)
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Map showing your location, accurate to about \(Int(fix.accuracyMeters.rounded())) metres")
        // A fix taken at a new time is a new map, so it recenters.
        .id(fix)
    }
}

/// When and how accurately a fix was taken, in plain words.
struct LocationFixDetails: View {
    let fix: LocationFix

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Taken at \(fix.capturedAt.shortTime)", systemImage: "clock")
            Label("Accurate to about \(Int(fix.accuracyMeters.rounded())) m", systemImage: "scope")
        }
        .font(Theme.label)
        .foregroundStyle(Theme.secondaryText)
    }
}

// MARK: - Session: the location sent with the last alert

/// Shows exactly what contacts were sent, so the wearer can check it.
struct SentLocationCard: View {
    @Environment(WearerStore.self) private var store

    var body: some View {
        let _ = store.revision
        if let alarm = store.coordinator.lastVisibleAlarm {
            Card("Location sent") {
                if let fix = alarm.location {
                    LocationMap(fix: fix)
                    LocationFixDetails(fix: fix)
                    Text(recipientsText(alarm))
                        .font(Theme.body)
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if let url = URL(string: fix.mapURL) {
                        Link(destination: url) {
                            Label("Open in Maps", systemImage: "map")
                        }
                        .buttonStyle(.rippleSecondary)
                        .accessibilityHint("Opens the same map link your contacts got.")
                    }
                } else if alarm.recipients.contains(where: \.shareLocation) {
                    FormNote("No location was sent with this alarm. Location may be off for Ripple, or the iPhone couldn't find it in time.")
                } else {
                    FormNote("No location was sent. None of your contacts have location sharing on.")
                }
            }
        } else {
            Card("Location sent") {
                FormNote("No alerts yet. The location sent with your next alert will show here. To see where your iPhone thinks you are now, use Settings → Check my location.")
            }
        }
    }

    /// Who received the map link: texted contacts that have sharing on.
    private func recipientsText(_ alarm: Alarm) -> String {
        let texted = Set(alarm.textedRecipientIds)
        let sharing = alarm.recipients.filter(\.shareLocation)
        let sentTo = sharing.filter { texted.contains($0.id) }.map(\.name)
        if !sentTo.isEmpty {
            return "Sent to " + ListFormatter.localizedString(byJoining: sentTo) + "."
        }
        return "Will be sent to " + ListFormatter.localizedString(byJoining: sharing.map(\.name)) + " if they're texted."
    }
}

// MARK: - Settings: check my location now

/// Takes one location fix on request and shows it, so the wearer can make
/// sure it's right before an alert. Nothing is sent or tracked.
struct LocationCheckView: View {
    @Environment(WearerStore.self) private var store
    @State private var fix: LocationFix?
    @State private var checking = false
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                Card {
                    Text("See where your iPhone thinks you are. This is the kind of location your contacts get in an alert.")
                        .font(Theme.body)
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    FormNote("Nothing is sent to anyone, and Ripple never tracks your location.")
                }

                if let fix {
                    Card("Your location now") {
                        LocationMap(fix: fix)
                        LocationFixDetails(fix: fix)
                    }
                } else if failed {
                    Card {
                        Label("Couldn't find your location.", systemImage: "location.slash")
                            .font(Theme.body.weight(.semibold))
                            .foregroundStyle(Theme.text)
                        FormNote("Location for Ripple: \(store.location.statusText). Allow it in the iPhone's Settings, then try again.")
                    }
                }

                Button {
                    check()
                } label: {
                    Label(checking ? "Checking…" : (fix == nil ? "Check my location" : "Check again"), systemImage: "location")
                }
                .buttonStyle(.ripplePrimary)
                .disabled(checking)
                .accessibilityHint("Takes one location reading now and shows it on a map.")
            }
            .padding(Theme.spacing)
        }
        .rippleScreen(background: .three)
        .navigationTitle("Check my location")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func check() {
        checking = true
        failed = false
        store.location.requestPermission()
        store.location.requestOneFix { newFix in
            checking = false
            if let newFix {
                fix = newFix
            } else {
                failed = true
            }
        }
    }
}

// MARK: - Previews

private let previewFix = LocationFix(latitude: 43.4723, longitude: -80.5449, accuracyMeters: 12, capturedAt: .now)

#Preview("Location map") {
    ScrollView {
        Card("Location sent") {
            LocationMap(fix: previewFix)
            LocationFixDetails(fix: previewFix)
            Text("Sent to Maya Chen.").font(Theme.body).foregroundStyle(Theme.text)
            Button {} label: { Label("Open in Maps", systemImage: "map") }.buttonStyle(.rippleSecondary)
        }
        .padding(Theme.spacing)
    }
    .rippleScreen()
}

#Preview("Location map, largest text") {
    ScrollView {
        Card("Location sent") {
            LocationMap(fix: previewFix)
            LocationFixDetails(fix: previewFix)
        }
        .padding(Theme.spacing)
    }
    .rippleScreen()
    .dynamicTypeSize(.accessibility3)
}

#Preview("Check my location") {
    NavigationStack { LocationCheckView() }.environment(WearerStore())
}
