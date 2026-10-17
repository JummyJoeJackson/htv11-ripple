import Foundation
import RippleEngine
import Vapor

/// Checks backup deadlines twice a second and hands backup texts to the SMS
/// route outside the engine, so a slow provider never blocks other work.
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
            while !Task.isCancelled {
                let outbound = await engine.tick()
                for message in outbound {
                    Task {
                        let result = await sender.send(to: message.to, body: message.body)
                        await engine.recordSendResult(messageId: message.messageId, result: result)
                    }
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        logger.notice("Backup worker started")
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
