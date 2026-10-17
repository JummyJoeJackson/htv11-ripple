import Foundation
import RippleEngine
import RippleKit
import Vapor

/// Prints backup texts to the server log instead of sending them. The
/// default, so the whole flow can be tried without an SMS account.
struct ConsoleSender: MessageSender {
    let name = "console (backup texts are printed, not sent)"

    func send(to: String, body: String) async -> SendResult {
        print("──── Backup SMS to \(to) ────\n\(body)\n──────────────────────────────")
        return SendResult(status: .submitted, providerMessageId: "console-" + String(UUID().uuidString.prefix(8)))
    }
}

/// Twilio Programmable Messaging, the backup sender in the PRD. Credentials stay on the server.
struct TwilioSender: MessageSender {
    let name = "twilio"
    let client: Client
    let accountSid: String
    let authToken: String
    let from: String
    let statusCallback: String?

    private struct MessageResource: Decodable {
        let sid: String
    }

    private struct ErrorResource: Decodable {
        let message: String?
        let code: Int?
    }

    func send(to: String, body: String) async -> SendResult {
        let uri = URI(string: "https://api.twilio.com/2010-04-01/Accounts/\(accountSid)/Messages.json")
        var headers = HTTPHeaders()
        headers.basicAuthorization = BasicAuthorization(username: accountSid, password: authToken)
        do {
            let response = try await client.post(uri, headers: headers) { request in
                var form = ["To": to, "From": from, "Body": body]
                if let statusCallback {
                    form["StatusCallback"] = statusCallback
                }
                try request.content.encode(form, as: .urlEncodedForm)
            }
            if (200..<300).contains(response.status.code) {
                let resource = try? response.content.decode(MessageResource.self)
                return SendResult(status: .submitted, providerMessageId: resource?.sid)
            }
            let problem = try? response.content.decode(ErrorResource.self)
            return SendResult(status: .failed, error: problem?.message ?? "Twilio returned status \(response.status.code)")
        } catch {
            // We can't tell whether Twilio accepted it.
            return SendResult(status: .unknown, error: "No confirmed response from Twilio: \(error.localizedDescription)")
        }
    }
}

#if os(macOS)
/// Sends backup texts through the Messages app on the Mac running the server.
/// Needs a signed-in Messages account (and Text Message Forwarding for SMS).
/// macOS asks for Automation permission the first time.
struct MessagesAppSender: MessageSender {
    let service: String

    var name: String { "macOS Messages (\(service))" }

    private var script: String {
        """
        on run argv
            set targetPhone to item 1 of argv
            set messageText to item 2 of argv
            tell application "Messages"
                set targetService to 1st account whose service type = \(service == "SMS" ? "SMS" : "iMessage")
                set targetBuddy to participant targetPhone of targetService
                send messageText to targetBuddy
            end tell
        end run
        """
    }

    func send(to: String, body: String) async -> SendResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script, to, body]
            let errorPipe = Pipe()
            process.standardError = errorPipe
            process.standardOutput = Pipe()
            process.terminationHandler = { finished in
                let errorText = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if finished.terminationStatus == 0 {
                    continuation.resume(returning: SendResult(status: .submitted))
                } else {
                    continuation.resume(returning: SendResult(status: .failed, error: errorText.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: SendResult(status: .failed, error: error.localizedDescription))
            }
        }
    }
}
#endif
