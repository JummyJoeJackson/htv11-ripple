import Foundation
import KazeEngine
import Vapor

/// Reads configuration from environment variables. See docs/RUNNING.md.
func configure(_ app: Application) async throws {
    let env = ProcessInfo.processInfo.environment
    let port = Int(env["KAZE_PORT"] ?? "") ?? 8080
    app.http.server.configuration.hostname = env["KAZE_HOST"] ?? "0.0.0.0"
    app.http.server.configuration.port = port

    let serverDirectory = ServerPaths.serverDirectory()
    let publicDirectory = env["KAZE_PUBLIC_DIR"] ?? serverDirectory + "/Public"
    let dataFile = env["KAZE_DATA_FILE"] ?? serverDirectory + "/.data/kaze.json"

    let lanAddress = LANAddress.ipv4()
    let baseURL = env["KAZE_PUBLIC_BASE_URL"] ?? "http://\(lanAddress ?? "localhost"):\(port)"
    let adminSecret = env["KAZE_ADMIN_SECRET"] ?? "kaze-demo"
    let recipients = env["KAZE_DEMO_RECIPIENTS"].map { list in
        Set(list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    let engine = Engine(
        storageURL: URL(fileURLWithPath: dataFile),
        config: EngineConfig(publicBaseURL: baseURL, demoRecipients: recipients, adminSecret: adminSecret)
    )
    let sender = makeSender(env: env, app: app, baseURL: baseURL)

    app.middleware = Middlewares()
    app.middleware.use(KazeErrorMiddleware())
    try routes(app, engine: engine, publicDirectory: publicDirectory, twilioAuthToken: env["TWILIO_AUTH_TOKEN"], baseURL: baseURL)

    let worker = Worker(engine: engine, sender: sender, logger: app.logger)
    app.lifecycle.use(WorkerLifecycle(worker: worker))

    app.logger.notice("KAZE server listening on port \(port)")
    app.logger.notice("Phones should use server address: \(baseURL)")
    app.logger.notice("Responder links will start with: \(baseURL)/r/…")
    app.logger.notice("SMS route: \(sender.name)\(recipients.map { " (demo recipients only: \($0.count))" } ?? "")")
    app.logger.notice("Data file: \(dataFile)")
    if env["KAZE_ADMIN_SECRET"] == nil {
        app.logger.warning("KAZE_ADMIN_SECRET isn't set; the admin secret is \"kaze-demo\".")
    }
}

func makeSender(env: [String: String], app: Application, baseURL: String) -> MessageSender {
    switch (env["KAZE_SMS"] ?? "console").lowercased() {
    case "twilio":
        guard let sid = env["TWILIO_ACCOUNT_SID"], let token = env["TWILIO_AUTH_TOKEN"], let from = env["TWILIO_FROM"] else {
            app.logger.error("KAZE_SMS=twilio needs TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN and TWILIO_FROM. Falling back to console.")
            return ConsoleSender()
        }
        let callback = baseURL.hasPrefix("https://") ? baseURL + "/v1/webhooks/twilio" : nil
        return TwilioSender(client: app.client, accountSid: sid, authToken: token, from: from, statusCallback: callback)
    case "messages":
        #if os(macOS)
        return MessagesAppSender(service: env["KAZE_MESSAGES_SERVICE"] ?? "iMessage")
        #else
        app.logger.error("KAZE_SMS=messages only works on macOS. Falling back to console.")
        return ConsoleSender()
        #endif
    default:
        return ConsoleSender()
    }
}
