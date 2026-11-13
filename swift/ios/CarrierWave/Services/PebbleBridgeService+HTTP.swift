import Foundation

// MARK: - HTTPRequest

/// Minimal HTTP/1.1 request parser. Returns nil while headers are still being
/// accumulated, returns a parsed request once headers and the declared body
/// length have arrived. We only parse what the Pebble bridge needs: method,
/// path, and a JSON body small enough to fit in one read.
nonisolated struct HTTPRequest {
    let method: String
    let path: String
    let body: Data

    static func parse(_ buffer: Data) -> HTTPRequest? {
        guard let separator = buffer.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) else {
            return nil
        }
        let headerData = buffer.subdata(in: 0 ..< separator.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return nil
        }

        let lines = headerText.split(
            separator: "\r\n", omittingEmptySubsequences: false
        )
        guard let requestLine = lines.first else {
            return nil
        }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            return nil
        }
        let method = String(parts[0]).uppercased()
        let path = String(parts[1])

        var contentLength = 0
        for line in lines.dropFirst() {
            let segments = line.split(
                separator: ":", maxSplits: 1, omittingEmptySubsequences: false
            )
            guard segments.count == 2 else {
                continue
            }
            let header = segments[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = segments[1].trimmingCharacters(in: .whitespaces)
            if header == "content-length", let length = Int(value) {
                contentLength = length
            }
        }

        let bodyStart = separator.upperBound
        let available = buffer.count - bodyStart
        if available < contentLength {
            return nil
        }
        let body = buffer.subdata(
            in: bodyStart ..< (bodyStart + contentLength)
        )
        return HTTPRequest(method: method, path: path, body: body)
    }
}

// MARK: - HTTPResponse

/// Frames an HTTP/1.1 response. Connection: close so the bridge can cancel
/// after the single response without negotiating keep-alive — Pebble JS
/// opens a fresh `XMLHttpRequest` per call.
nonisolated enum HTTPResponse {
    // MARK: Internal

    static func json(status: Int, payload: some Encodable) -> Data {
        let data = (try? JSONEncoder().encode(payload)) ?? Data("{}".utf8)
        return frame(status: status, contentType: "application/json", body: data)
    }

    static func empty(status: Int) -> Data {
        frame(status: status, contentType: "application/json", body: Data())
    }

    // MARK: Private

    private static func frame(status: Int, contentType: String, body: Data) -> Data {
        let reason = reasonPhrase(for: status)
        var head = ""
        head += "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n"
        head += "\r\n"
        var out = Data(head.utf8)
        out.append(body)
        return out
    }

    private static func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200: "OK"
        case 400: "Bad Request"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 500: "Internal Server Error"
        default: "Status"
        }
    }
}
