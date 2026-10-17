import Foundation
import KazeKit
import Observation
import WatchKit

struct PendingCommand: Equatable {
    let id: String
    let kind: WatchCommandKind
}

struct WatchFeedback: Equatable, Identifiable {
    let id = UUID()
    let text: String
    let ok: Bool
}

/// Watch state. Input is shown as pending until the backend accepted it
/// (through the iPhone). Haptics and the countdown are display only.
@MainActor
@Observable
final class WatchStore {
    private(set) var state: WatchState?
    private(set) var pending: PendingCommand?
    var feedback: WatchFeedback?
    private(set) var phoneReachable = false

    private let link = WatchLink()
    @ObservationIgnored private var hapticTask: Task<Void, Never>?
    @ObservationIgnored private var pingTask: Task<Void, Never>?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?

    init() {
        link.onState = { [weak self] state in
            self?.apply(state)
        }
        link.onReachability = { [weak self] reachable in
            self?.phoneReachable = reachable
        }
        link.activate()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.link.ping()
                if let self { self.phoneReachable = self.link.isReachable }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    var isAwaitingCheckIn: Bool { state?.checkInId != nil }

    private func apply(_ newState: WatchState) {
        let previousCheckIn = state?.checkInId
        state = newState
        if let checkIn = newState.checkInId, checkIn != previousCheckIn {
            startCheckInHaptics()
        }
        if newState.checkInId == nil {
            stopHaptics()
        }
    }

    // MARK: Commands

    func confirm() {
        send(.confirm)
    }

    func help() {
        send(.help)
    }

    private func send(_ kind: WatchCommandKind) {
        guard pending == nil else { return }
        let command = WatchCommand(kind: kind, checkInId: kind == .confirm ? state?.checkInId : nil)
        guard link.isReachable else {
            feedback = WatchFeedback(text: "Not sent. iPhone isn't connected.", ok: false)
            WKInterfaceDevice.current().play(.failure)
            return
        }
        pending = PendingCommand(id: command.id, kind: kind)
        WKInterfaceDevice.current().play(.click)
        link.send(command) { [weak self] reply in
            self?.finish(command, reply: reply)
        }
        // If no answer comes back, say so instead of implying success.
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled else { return }
            self?.finish(command, reply: nil)
        }
    }

    private func finish(_ command: WatchCommand, reply: WatchCommandReply?) {
        guard pending?.id == command.id else { return }
        pending = nil
        timeoutTask?.cancel()
        if let reply, reply.ok {
            feedback = WatchFeedback(text: reply.message, ok: true)
            WKInterfaceDevice.current().play(.success)
            if command.kind == .confirm { stopHaptics() }
        } else {
            feedback = WatchFeedback(text: reply?.message ?? "Not confirmed. Check your iPhone.", ok: false)
            WKInterfaceDevice.current().play(.failure)
        }
    }

    // MARK: Haptics

    /// A strong, repeating haptic while a check-in waits for an answer.
    private func startCheckInHaptics() {
        hapticTask?.cancel()
        hapticTask = Task { [weak self] in
            var count = 0
            while !Task.isCancelled, count < 60 {
                guard let self, self.isAwaitingCheckIn else { return }
                WKInterfaceDevice.current().play(.notification)
                count += 1
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func stopHaptics() {
        hapticTask?.cancel()
        hapticTask = nil
    }
}
