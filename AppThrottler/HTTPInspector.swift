import Foundation

// MARK: - Resource Type

enum ResourceType: String, Codable, CaseIterable, Identifiable {
    case document = "Document"
    case xhr = "XHR/Fetch"
    case css = "CSS"
    case js = "JavaScript"
    case image = "Image"
    case font = "Font"
    case media = "Media"
    case websocket = "WebSocket"
    case manifest = "Manifest"
    case json = "JSON"
    case xml = "XML"
    case text = "Plain Text"
    case other = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .document: return "doc.text"
        case .xhr: return "arrow.left.arrow.right.circle"
        case .css: return "paintbrush"
        case .js: return "chevron.left.forwardslash.chevron.right"
        case .image: return "photo"
        case .font: return "textformat"
        case .media: return "play.rectangle"
        case .websocket: return "bolt.horizontal"
        case .manifest: return "list.bullet.rectangle"
        case .json: return "curlybraces"
        case .xml: return "chevron.left.slash.chevron.right"
        case .text: return "doc.plaintext"
        case .other: return "questionmark.circle"
        }
    }

    var color: String {
        switch self {
        case .document: return "blue"
        case .xhr: return "purple"
        case .css: return "cyan"
        case .js: return "yellow"
        case .image: return "green"
        case .font: return "orange"
        case .media: return "pink"
        case .websocket: return "mint"
        case .manifest: return "gray"
        case .json: return "indigo"
        case .xml: return "teal"
        case .text: return "gray"
        case .other: return "gray"
        }
    }
}

// MARK: - HTTP Transaction

struct HTTPTransaction: Identifiable, Codable, Hashable {
    let id: String
    var timestamp: Date
    var method: String
    var url: String
    var host: String
    var path: String
    var requestHeaders: [String: String]
    var requestBody: String?
    var statusCode: Int?
    var responseHeaders: [String: String]?
    var responseBody: String?
    var duration: TimeInterval?
    var requestSize: Int
    var responseSize: Int

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: HTTPTransaction, rhs: HTTPTransaction) -> Bool { lhs.id == rhs.id }

    var fullURL: String {
        "https://\(host)\(path)"
    }

    var statusClass: String {
        guard let code = statusCode else { return "pending" }
        switch code {
        case 200..<300: return "success"
        case 300..<400: return "redirect"
        case 400..<500: return "client_error"
        case 500..<600: return "server_error"
        default: return "other"
        }
    }

    var resourceType: ResourceType {
        let ext = path.components(separatedBy: "?").first?.components(separatedBy: ".").last?.lowercased() ?? ""
        let contentType = (responseHeaders?["Content-Type"] ?? responseHeaders?["content-type"] ?? "").lowercased()
        let accept = (requestHeaders["Accept"] ?? requestHeaders["accept"] ?? "").lowercased()
        let lowerPath = path.lowercased()

        // WebSocket
        if lowerPath.contains("ws") || lowerPath.contains("socket") || contentType.contains("websocket") {
            return .websocket
        }

        // By file extension
        switch ext {
        case "html", "htm", "shtml", "asp", "aspx", "jsp", "php": return .document
        case "css": return .css
        case "js", "mjs", "jsx", "ts", "tsx": return .js
        case "json": return .json
        case "xml", "svg", "rss", "atom": return .xml
        case "jpg", "jpeg", "png", "gif", "webp", "avif", "ico", "bmp", "tiff", "heic", "heif": return .image
        case "woff", "woff2", "ttf", "otf", "eot": return .font
        case "mp4", "mp3", "webm", "ogg", "wav", "avi", "mov", "flv", "m4a", "m4v": return .media
        case "manifest", "webmanifest": return .manifest
        case "txt", "csv", "log": return .text
        default: break
        }

        // By Content-Type
        if contentType.contains("html") || contentType.contains("xhtml") { return .document }
        if contentType.contains("javascript") || contentType.contains("ecmascript") { return .js }
        if contentType.contains("css") { return .css }
        if contentType.contains("json") { return .json }
        if contentType.contains("xml") { return .xml }
        if contentType.contains("image/") { return .image }
        if contentType.contains("font/") || contentType.contains("woff") { return .font }
        if contentType.contains("video/") || contentType.contains("audio/") { return .media }
        if contentType.contains("text/plain") { return .text }

        // By Accept header
        if accept.contains("json") || accept.contains("application/json") { return .json }
        if accept.contains("html") { return .document }
        if accept.contains("xml") { return .xml }

        // API path heuristic
        if lowerPath.contains("/api/") || lowerPath.contains("/v1/") || lowerPath.contains("/v2/") ||
           lowerPath.contains("/graphql") || lowerPath.contains("/rest/") {
            return .xhr
        }

        // No extension + no content type = likely XHR
        if ext.isEmpty && (contentType.isEmpty || contentType.contains("octet-stream")) {
            return .xhr
        }

        return .other
    }

    var formattedDuration: String {
        guard let d = duration else { return "..." }
        if d < 1 { return String(format: "%.0fms", d * 1000) }
        return String(format: "%.2fs", d)
    }

    var curlCommand: String {
        var cmd = "curl -X \(method) '\(fullURL)'"
        for (key, value) in requestHeaders.sorted(by: { $0.key < $1.key }) {
            if key.lowercased() != "host" {
                cmd += " \\\n  -H '\(key): \(value)'"
            }
        }
        if let body = requestBody, !body.isEmpty {
            cmd += " \\\n  -d '\(body)'"
        }
        return cmd
    }

    init(id: String = UUID().uuidString, timestamp: Date = Date(), method: String = "GET",
         url: String = "", host: String = "", path: String = "/",
         requestHeaders: [String: String] = [:], requestBody: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.method = method
        self.url = url
        self.host = host
        self.path = path
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.requestSize = 0
        self.responseSize = 0
    }
}

// MARK: - HTTP Inspector

@MainActor
class HTTPInspector: ObservableObject {
    @Published var transactions: [HTTPTransaction] = []
    @Published var isCapturing = false
    @Published var selectedTransaction: HTTPTransaction?
    @Published var filterText: String = ""
    @Published var filterMethod: String = ""
    @Published var filterStatus: String = ""
    @Published var filterType: String = ""
    @Published var showReplaySheet = false
    @Published var showCurlSheet = false
    @Published var mockEnabled = false
    @Published var mockRules: [MockRule] = []

    private var captureProcess: Process?
    private var maxTransactions = 5000

    struct MockRule: Identifiable, Codable {
        let id: String
        var urlPattern: String
        var statusCode: Int
        var headers: [String: String]
        var body: String
        var enabled: Bool

        init(urlPattern: String, statusCode: Int = 200, body: String = "{}") {
            self.id = UUID().uuidString
            self.urlPattern = urlPattern
            self.statusCode = statusCode
            self.headers = ["Content-Type": "application/json"]
            self.body = body
            self.enabled = true
        }
    }

    var filteredTransactions: [HTTPTransaction] {
        transactions.filter { tx in
            if !filterText.isEmpty {
                let q = filterText.lowercased()
                guard tx.url.lowercased().contains(q) ||
                      tx.host.lowercased().contains(q) ||
                      tx.path.lowercased().contains(q) else { return false }
            }
            if !filterMethod.isEmpty, tx.method != filterMethod { return false }
            if !filterStatus.isEmpty {
                guard let code = tx.statusCode else { return filterStatus == "pending" }
                switch filterStatus {
                case "2xx": guard (200..<300).contains(code) else { return false }
                case "3xx": guard (300..<400).contains(code) else { return false }
                case "4xx": guard (400..<500).contains(code) else { return false }
                case "5xx": guard (500..<600).contains(code) else { return false }
                default: break
                }
            }
            if !filterType.isEmpty, tx.resourceType.rawValue != filterType { return false }
            return true
        }
    }

    func typeCounts() -> [(ResourceType, Int)] {
        var counts: [ResourceType: Int] = [:]
        for tx in transactions {
            counts[tx.resourceType, default: 0] += 1
        }
        return ResourceType.allCases.compactMap { type in
            guard let count = counts[type], count > 0 else { return nil }
            return (type, count)
        }
    }

    // MARK: - Capture

    func startCapture(pid: Int32) {
        stopCapture()

        let ports = getProcessPorts(pid: pid)
        guard !ports.isEmpty else { return }

        // Use tcpdump to capture HTTP traffic
        let filter = ports.map { "port \($0)" }.joined(separator: " or ")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/tcpdump")
        process.arguments = ["-i", "any", "-nn", "-A", "-s", "0", filter]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                self?.parseHTTPFromCapture(text)
            }
        }

        do {
            try process.run()
            captureProcess = process
            isCapturing = true
        } catch {
            isCapturing = false
        }
    }

    func stopCapture() {
        captureProcess?.terminate()
        captureProcess = nil
        isCapturing = false
    }

    private func parseHTTPFromCapture(_ text: String) {
        let blocks = text.components(separatedBy: "\r\n\r\n")
        for i in stride(from: 0, to: blocks.count, by: 2) {
            guard i < blocks.count else { continue }
            let headerBlock = blocks[i]

            // Parse request line
            let lines = headerBlock.components(separatedBy: "\r\n")
            guard let firstLine = lines.first else { continue }

            let parts = firstLine.split(separator: " ", maxSplits: 2)
            guard parts.count >= 2 else { continue }

            let method = String(parts[0])
            let path = String(parts[1])

            // Check if it's a valid HTTP method
            let httpMethods = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"]
            guard httpMethods.contains(method) else { continue }

            var headers: [String: String] = [:]
            var host = ""
            for line in lines.dropFirst() {
                if let colonIdx = line.firstIndex(of: ":") {
                    let key = String(line[line.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
                    let value = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                    headers[key] = value
                    if key.lowercased() == "host" { host = value }
                }
            }

            var body: String? = nil
            if i + 1 < blocks.count {
                let possibleBody = blocks[i + 1].trimmingCharacters(in: .whitespacesAndNewlines)
                if !possibleBody.isEmpty && !possibleBody.hasPrefix("HTTP/") && !possibleBody.hasPrefix("GET ") {
                    body = possibleBody
                }
            }

            // Check for status line (response)
            if firstLine.hasPrefix("HTTP/") {
                if parts.count >= 2, let code = Int(parts[1]) {
                    // This is a response - match to pending request
                    if let idx = transactions.lastIndex(where: { $0.statusCode == nil }) {
                        transactions[idx].statusCode = code
                        transactions[idx].responseHeaders = headers
                        transactions[idx].responseBody = body
                        transactions[idx].duration = Date().timeIntervalSince(transactions[idx].timestamp)
                    }
                }
                continue
            }

            // Request
            let tx = HTTPTransaction(
                timestamp: Date(), method: method, url: "https://\(host)\(path)",
                host: host, path: path, requestHeaders: headers, requestBody: body
            )
            transactions.append(tx)

            if transactions.count > maxTransactions {
                transactions.removeFirst(transactions.count - maxTransactions)
            }
        }
    }

    // MARK: - Replay

    func replay(_ tx: HTTPTransaction) async -> HTTPTransaction? {
        var request = URLRequest(url: URL(string: tx.fullURL)!)
        request.httpMethod = tx.method
        for (key, value) in tx.requestHeaders {
            if key.lowercased() != "host" {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        if let body = tx.requestBody {
            request.httpBody = body.data(using: .utf8)
        }

        var result = HTTPTransaction(
            method: tx.method, url: tx.fullURL, host: tx.host, path: tx.path,
            requestHeaders: tx.requestHeaders, requestBody: tx.requestBody
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResp = response as? HTTPURLResponse {
                result.statusCode = httpResp.statusCode
                result.responseHeaders = httpResp.allHeaderFields as? [String: String]
                result.responseBody = String(data: data, encoding: .utf8)
                result.duration = Date().timeIntervalSince(result.timestamp)
                result.responseSize = data.count
            }
        } catch {
            result.responseBody = "Error: \(error.localizedDescription)"
        }

        return result
    }

    // MARK: - cURL

    func exportAsCurl(_ tx: HTTPTransaction) -> String {
        tx.curlCommand
    }

    func importFromCurl(_ curl: String) -> HTTPTransaction? {
        let components = curl.components(separatedBy: " ")
        var method = "GET"
        var url = ""
        var headers: [String: String] = [:]
        var body: String?

        var i = 0
        while i < components.count {
            let c = components[i].trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            switch c {
            case "curl": break
            case "-X":
                if i + 1 < components.count { method = components[i + 1]; i += 1 }
            case "-H":
                if i + 1 < components.count {
                    let header = components[i + 1].trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                    if let colon = header.firstIndex(of: ":") {
                        let key = String(header[header.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
                        let val = String(header[header.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                        headers[key] = val
                    }
                    i += 1
                }
            case "-d", "--data":
                if i + 1 < components.count { body = components[i + 1].trimmingCharacters(in: CharacterSet(charactersIn: "'\"")); i += 1 }
            default:
                if c.hasPrefix("http") { url = c }
            }
            i += 1
        }

        guard !url.isEmpty, let parsedURL = URL(string: url) else { return nil }

        return HTTPTransaction(
            method: method, url: url,
            host: parsedURL.host ?? "",
            path: parsedURL.path.isEmpty ? "/" : parsedURL.path + (parsedURL.query.map { "?\($0)" } ?? ""),
            requestHeaders: headers, requestBody: body
        )
    }

    // MARK: - Mock

    func addMockRule(pattern: String, statusCode: Int, body: String) {
        mockRules.append(MockRule(urlPattern: pattern, statusCode: statusCode, body: body))
    }

    func removeMockRule(at offsets: IndexSet) {
        mockRules.remove(atOffsets: offsets)
    }

    // MARK: - Session Save/Load

    func saveSession(to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(transactions) {
            try? data.write(to: url)
        }
    }

    func loadSession(from url: URL) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let loaded = try? decoder.decode([HTTPTransaction].self, from: data) else { return }
        transactions = loaded
    }

    // MARK: - Diff

    func diff(_ a: HTTPTransaction, _ b: HTTPTransaction) -> [DiffLine] {
        var lines: [DiffLine] = []

        // Compare headers
        let allKeys = Set(a.requestHeaders.keys).union(b.requestHeaders.keys)
        for key in allKeys.sorted() {
            let va = a.requestHeaders[key] ?? "(missing)"
            let vb = b.requestHeaders[key] ?? "(missing)"
            if va != vb {
                lines.append(DiffLine(type: .removed, content: "\(key): \(va)", side: .left))
                lines.append(DiffLine(type: .added, content: "\(key): \(vb)", side: .right))
            }
        }

        // Compare body
        let bodyA = a.requestBody ?? "(empty)"
        let bodyB = b.requestBody ?? "(empty)"
        if bodyA != bodyB {
            lines.append(DiffLine(type: .removed, content: "Body: \(bodyA)", side: .left))
            lines.append(DiffLine(type: .added, content: "Body: \(bodyB)", side: .right))
        }

        // Compare response
        let respA = a.responseBody ?? "(no response)"
        let respB = b.responseBody ?? "(no response)"
        if respA != respB {
            lines.append(DiffLine(type: .removed, content: "Response: \(respA.prefix(200))", side: .left))
            lines.append(DiffLine(type: .added, content: "Response: \(respB.prefix(200))", side: .right))
        }

        if lines.isEmpty {
            lines.append(DiffLine(type: .context, content: "这两个请求完全相同", side: .left))
        }

        return lines
    }

    // MARK: - Helpers

    struct DiffLine: Identifiable {
        let id = UUID()
        let type: DiffType
        let content: String
        let side: DiffSide

        enum DiffType { case added, removed, context }
        enum DiffSide { case left, right }
    }

    private func getProcessPorts(pid: Int32) -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-i", "-n", "-P", "-p", "\(pid)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run(); process.waitUntilExit() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var ports = Set<String>()
        for line in output.components(separatedBy: "\n").dropFirst() {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard cols.count >= 9 else { continue }
            let parts = cols[8].components(separatedBy: "->")
            let localParts = parts[0].components(separatedBy: ":")
            if let port = localParts.last, port != "*", Int(port) != nil {
                ports.insert(port)
            }
        }
        return Array(ports)
    }

    func clearTransactions() {
        transactions.removeAll()
        selectedTransaction = nil
    }
}
