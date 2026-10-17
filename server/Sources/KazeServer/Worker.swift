import Foundation
import KazeEngine
import Vapor

/// Runs due jobs four times a second and hands outbound messages to the
/// messaging adapter outside the engine, so a slow provider never blocks
/// state changes.
final class Worker: @unchecked Sendable {
    let engine: Engine
    let sender: MessageSender
    let logger: Logger
    private var task: Task<Void, Never>?

    init(engine: Engine, sender: MessageSender, logger: Logger) {
        self.engine = engine
        self.sender = sender
        self.logger = logger
    }

    func start() {
        let engine = self.engine
        let sender = self.sender
        task = Task {
            await engine.recoverAfterRestart()
            while !Task.isCancelled {
                let outbound = await engine.tick()
                for message in outbound {
                    Task {
                        let result = await sender.send(to: message.to, body: message.body)
                        await engine.recordSendResult(deliveryId: message.deliveryId, result: result)
                    }
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        logger.notice("Job worker started")
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}

struct WorkerLifecycle: LifecycleHandler {
    let worker: Worker

    func didBoot(_ application: Application) throws {
        worker.start()
    }

    func shutdown(_ application: Application) {
        worker.stop()
    }
}
