import Foundation
import RippleEngine
import RippleKit
import Vapor

/// Renders every error as `{"code": …, "message": …}`.
struct RippleErrorMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        do {
            return try await next.respond(to: request)
        } catch let error as EngineError {
            return errorResponse(status: error.status, code: error.code, message: error.message)
        } catch is DecodingError {
            return errorResponse(status: 400, code: "bad_request", message: "The request body wasn't in the expected format.")
        } catch let error as AbortError {
            return errorResponse(status: Int(error.status.code), code: "error", message: error.reason)
        } catch {
            request.logger.report(error: error)
            return errorResponse(status: 500, code: "server_error", message: "Something went wrong on the server.")
        }
    }

    func errorResponse(status: Int, code: String, message: String) -> Response {
        let body = APIErrorBody(code: code, message: message)
        let data = (try? RippleJSON.encoder.encode(body)) ?? Data()
        return Response(status: HTTPResponseStatus(statusCode: status), headers: jsonHeaders(), body: .init(data: data))
    }
}

func jsonHeaders() -> HTTPHeaders {
    var headers = HTTPHeaders()
    headers.add(name: .contentType, value: "application/json; charset=utf-8")
    headers.add(name: .cacheControl, value: "no-store")
    return headers
}

func json<T: Encodable>(_ value: T, status: HTTPResponseStatus = .ok) throws -> Response {
    let data = try RippleJSON.encoder.encode(value)
    return Response(status: status, headers: jsonHeaders(), body: .init(data: data))
}

/// Decodes a JSON body with the shared date format.
func decodeBody<T: Decodable>(_ type: T.Type, _ request: Request) throws -> T {
    guard let text = request.body.string, let data = text.data(using: .utf8) else {
        throw EngineError(status: 400, code: "bad_request", message: "The request body is missing.")
    }
    return try RippleJSON.decoder.decode(T.self, from: data)
}

extension Request {
    var bearerToken: String? { headers.bearerAuthorization?.token }
    var idempotencyKey: String? { headers.first(name: "Idempotency-Key") }

    func pathValue(_ name: String) throws -> String {
        guard let value = parameters.get(name), !value.isEmpty else {
            throw EngineError(status: 400, code: "bad_request", message: "Missing \(name).")
        }
        return value
    }
}
