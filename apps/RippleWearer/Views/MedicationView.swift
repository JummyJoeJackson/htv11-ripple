import RippleKit
import SwiftUI

/// Dose times, the wait for "Took my meds", and the last dose taken. Opened
/// from the Medication card on Home and from Settings.
struct MedicationView: View {
    @Environment(WearerStore.self) private var store
    @State private var times: [MedicationTime] = []
    @State private var grace = 30
    @State private var loaded = false

    private var changed: Bool {
        times != store.config.medicationTimes || grace != store.config.medicationGraceMinutes
    }

    var body: some View {
        let _ = store.revision
        let coordinator = store.coordinator
        RippleForm {
            if coordinator.pendingDoseAt != nil {
                Section {
                    Button {
                        store.tookMedsFromPhone()
                    } label: {
                        Label("I took them", systemImage: "checkmark")
                    }
                    .buttonStyle(.ripplePrimary)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } header: {
                    SectionHeader("Time for your meds")
                }
            }

            Section {
                if let next = coordinator.nextDoseAt {
                    StatusRow(label: "Next dose", value: next.shortTime)
                }
                if let taken = coordinator.lastMedsTakenAt {
                    StatusRow(label: "Last taken", value: taken.dayAndTime)
                }
                if !coordinator.monitoring {
                    Label("Turn on monitoring to get reminders.", systemImage: "exclamationmark.circle")
                        .font(Theme.label)
                        .foregroundStyle(Theme.checkIn)
                }
            }

            Section {
                ForEach($times) { $time in
                    DatePicker("Dose", selection: Binding(
                        get: { time.asTodayDate },
                        set: { time.setTime(from: $0) }
                    ), displayedComponents: .hourAndMinute)
                }
                .onDelete { times.remove(atOffsets: $0) }
                Button {
                    times.append(MedicationTime(hour: 8, minute: 0))
                } label: {
                    Label("Add a dose time", systemImage: "plus.circle")
                }
                .buttonStyle(.rippleLink)
            } header: {
                SectionHeader("Dose times")
            } footer: {
                FormNote("Swipe left to remove one.")
            }

            if !times.isEmpty {
                Section {
                    Picker("Wait for \"Took my meds\"", selection: $grace) {
                        ForEach([1, 5, 15, 30, 45, 60, 90, 120], id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            Section {
                Button("Save medication times") {
                    Haptics.success()
                    var updated = store.config
                    updated.medicationTimes = times.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
                    updated.medicationGraceMinutes = grace
                    store.save(updated)
                    times = updated.medicationTimes
                    store.banner = Banner(text: "Medication times saved.", ok: true)
                }
                .buttonStyle(.ripplePrimary)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .disabled(!changed)
            }
        }
        .navigationTitle("Medication")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            times = store.config.medicationTimes
            grace = store.config.medicationGraceMinutes
        }
    }
}

#Preview("Medication") {
    NavigationStack { MedicationView() }.environment(WearerStore())
}
