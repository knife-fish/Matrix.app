import Foundation

nonisolated enum Aria2Error: LocalizedError {
    case invalidURL
    case invalidResponse
    case rpcError(String)
    case decodingError(underlying: Error, responsePreview: String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return L10n.text("rpc_error_invalid_url", language: .system)
        case .invalidResponse:
            return L10n.text("rpc_error_invalid_response", language: .system)
        case .rpcError(let message):
            return message
        case .decodingError(let error, let responsePreview):
            let detail: String
            if let responsePreview, !responsePreview.isEmpty {
                detail = "\(error.localizedDescription) | Response: \(responsePreview)"
            } else {
                detail = error.localizedDescription
            }
            return L10n.format("rpc_error_decoding", language: .system, detail)
        }
    }
}

nonisolated struct Aria2Request: Codable {
    let jsonrpc: String
    let id: String
    let method: String
    let params: [AnyCodable]
}

nonisolated struct Aria2Response<T: Codable>: Codable {
    let jsonrpc: String
    let id: String
    let result: T?
    let error: Aria2ErrorDetail?
}

nonisolated struct Aria2ErrorDetail: Codable {
    let code: Int
    let message: String
}

nonisolated struct Aria2MulticallItem<T: Codable>: Codable {
    let values: [T]
    let error: Aria2ErrorDetail?

    init(from decoder: Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer() {
            if let value = try? singleValue.decode(T.self) {
                values = [value]
                error = nil
                return
            }

            if let decodedError = try? singleValue.decode(Aria2ErrorDetail.self) {
                values = []
                error = decodedError
                return
            }
        }

        var container = try decoder.unkeyedContainer()

        if let value = try? container.decode(T.self) {
            values = [value]
            error = nil
            return
        }

        if let decodedError = try? container.decode(Aria2ErrorDetail.self) {
            values = []
            error = decodedError
            return
        }

        values = []
        error = nil
    }
}

nonisolated struct Aria2Status: Codable {
    let gid: String
    let status: String
    let totalLength: String
    let completedLength: String
    let downloadSpeed: String
    let uploadSpeed: String?
    let connections: String
    let errorCode: String?
    let errorMessage: String?
    let numSeeders: String?
    let seeder: String?
    let pieceLength: String?
    let bitfield: String?
    let dir: String?
    let files: [Aria2File]?
    let bittorrent: Aria2BitTorrent?

    private enum CodingKeys: String, CodingKey {
        case gid
        case status
        case totalLength
        case completedLength
        case downloadSpeed
        case uploadSpeed
        case connections
        case errorCode
        case errorMessage
        case numSeeders
        case seeder
        case pieceLength
        case bitfield
        case dir
        case files
        case bittorrent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gid = try container.decodeLossyString(forKey: .gid)
        status = try container.decodeLossyString(forKey: .status)
        totalLength = try container.decodeLossyString(forKey: .totalLength, defaultValue: "0")
        completedLength = try container.decodeLossyString(forKey: .completedLength, defaultValue: "0")
        downloadSpeed = try container.decodeLossyString(forKey: .downloadSpeed, defaultValue: "0")
        uploadSpeed = try container.decodeLossyStringIfPresent(forKey: .uploadSpeed)
        connections = try container.decodeLossyString(forKey: .connections, defaultValue: "0")
        errorCode = try container.decodeLossyStringIfPresent(forKey: .errorCode)
        errorMessage = try container.decodeLossyStringIfPresent(forKey: .errorMessage)
        numSeeders = try container.decodeLossyStringIfPresent(forKey: .numSeeders)
        seeder = try container.decodeLossyStringIfPresent(forKey: .seeder)
        pieceLength = try container.decodeLossyStringIfPresent(forKey: .pieceLength)
        bitfield = try container.decodeLossyStringIfPresent(forKey: .bitfield)
        dir = try container.decodeLossyStringIfPresent(forKey: .dir)
        files = try container.decodeIfPresent([Aria2File].self, forKey: .files)
        bittorrent = try? container.decodeIfPresent(Aria2BitTorrent.self, forKey: .bittorrent)
    }
}

nonisolated struct Aria2File: Codable {
    let index: String
    let path: String
    let length: String
    let completedLength: String
    let selected: String
    let uris: [Aria2Uri]?

    private enum CodingKeys: String, CodingKey {
        case index
        case path
        case length
        case completedLength
        case selected
        case uris
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decodeLossyString(forKey: .index)
        path = try container.decodeLossyString(forKey: .path, defaultValue: "")
        length = try container.decodeLossyString(forKey: .length, defaultValue: "0")
        completedLength = try container.decodeLossyString(forKey: .completedLength, defaultValue: "0")
        selected = try container.decodeLossyString(forKey: .selected, defaultValue: "false")
        uris = try container.decodeIfPresent([Aria2Uri].self, forKey: .uris)
    }
}

nonisolated struct Aria2Uri: Codable {
    let uri: String
    let status: String

    private enum CodingKeys: String, CodingKey {
        case uri
        case status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uri = try container.decodeLossyString(forKey: .uri, defaultValue: "")
        status = try container.decodeLossyString(forKey: .status, defaultValue: "")
    }
}

nonisolated struct Aria2Peer: Codable, Hashable {
    let peerId: String?
    let ip: String
    let port: String
    let bitfield: String?
    let amChoking: String?
    let peerChoking: String?
    let downloadSpeed: String?
    let uploadSpeed: String?
    let seeder: String?

    private enum CodingKeys: String, CodingKey {
        case peerId
        case ip
        case port
        case bitfield
        case amChoking
        case peerChoking
        case downloadSpeed
        case uploadSpeed
        case seeder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        peerId = try container.decodeLossyStringIfPresent(forKey: .peerId)
        ip = try container.decodeLossyString(forKey: .ip, defaultValue: "")
        port = try container.decodeLossyString(forKey: .port, defaultValue: "0")
        bitfield = try container.decodeLossyStringIfPresent(forKey: .bitfield)
        amChoking = try container.decodeLossyStringIfPresent(forKey: .amChoking)
        peerChoking = try container.decodeLossyStringIfPresent(forKey: .peerChoking)
        downloadSpeed = try container.decodeLossyStringIfPresent(forKey: .downloadSpeed)
        uploadSpeed = try container.decodeLossyStringIfPresent(forKey: .uploadSpeed)
        seeder = try container.decodeLossyStringIfPresent(forKey: .seeder)
    }
}

nonisolated struct Aria2BitTorrentInfo: Codable {
    let name: String?

    private enum CodingKeys: String, CodingKey {
        case name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeLossyStringIfPresent(forKey: .name)
    }
}

nonisolated struct Aria2BitTorrent: Codable {
    let announceList: [[String]]?
    let comment: String?
    let creationDate: String?
    let mode: String?
    let info: Aria2BitTorrentInfo?

    private enum CodingKeys: String, CodingKey {
        case announceList
        case comment
        case creationDate
        case mode
        case info
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let list = try? container.decodeIfPresent([[String]].self, forKey: .announceList) {
            announceList = list
        } else if let flat = try? container.decodeIfPresent([String].self, forKey: .announceList) {
            announceList = flat.map { [$0] }
        } else if let listObject = try? container.decodeIfPresent([[[String: String]]].self, forKey: .announceList) {
            let normalized = listObject.map { tier in
                tier.compactMap { item in
                    item["announce"] ?? item["uri"] ?? item["url"]
                }
            }.filter { !$0.isEmpty }
            announceList = normalized.isEmpty ? nil : normalized
        } else {
            announceList = nil
        }
        comment = try container.decodeLossyStringIfPresent(forKey: .comment)
        mode = try container.decodeLossyStringIfPresent(forKey: .mode)
        info = try? container.decodeIfPresent(Aria2BitTorrentInfo.self, forKey: .info)

        if let stringValue = try container.decodeIfPresent(String.self, forKey: .creationDate) {
            creationDate = stringValue
        } else if let intValue = try container.decodeIfPresent(Int64.self, forKey: .creationDate) {
            creationDate = String(intValue)
        } else {
            creationDate = nil
        }
    }
}

nonisolated struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = ""
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let string = value as? String {
            try container.encode(string)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else if let array = value as? [Any] {
            try container.encode(array.map { AnyCodable($0) })
        } else if let dict = value as? [String: Any] {
            try container.encode(dict.mapValues { AnyCodable($0) })
        } else {
            try container.encode("")
        }
    }
}

actor Aria2RPCService {
    static let shared = Aria2RPCService()

    private static let requestTimeout: TimeInterval = 30
    private static let resourceTimeout: TimeInterval = 60
    private static let maxRetryCount = 2

    private var rpcURL: URL
    private let session: URLSession
    private var requestID: Int = 0
    private var currentPort: Int

    init(rpcURL: URL? = nil) {
        let resolvedURL = rpcURL ?? URL(string: "http://localhost:16800/jsonrpc")!
        self.rpcURL = resolvedURL
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = Self.requestTimeout
        configuration.timeoutIntervalForResource = Self.resourceTimeout
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
        self.currentPort = resolvedURL.port ?? 16800
    }

    func updatePort(_ port: Int) {
        guard port != currentPort else { return }
        currentPort = port
        self.rpcURL = URL(string: "http://localhost:\(port)/jsonrpc")!
        Task {
            await MatrixDebugLogger.shared.log(
                event: "rpc.updatePort",
                metadata: [
                    "port": String(port),
                    "url": rpcURL.absoluteString
                ],
                level: .info
            )
        }
    }

    func getCurrentPort() -> Int {
        currentPort
    }
    
    private func generateID() -> String {
        requestID += 1
        return String(requestID)
    }

    nonisolated static func isTransientTransportError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }

        switch nsError.code {
        case NSURLErrorTimedOut,
             NSURLErrorCannotFindHost,
             NSURLErrorCannotConnectToHost,
             NSURLErrorNetworkConnectionLost:
            return true
        default:
            return false
        }
    }

    nonisolated static func missingGID(from message: String) -> String? {
        let prefix = "GID "
        let suffix = " is not found"
        guard message.hasPrefix(prefix), message.hasSuffix(suffix) else { return nil }
        return String(message.dropFirst(prefix.count).dropLast(suffix.count))
    }

    nonisolated static func isActiveDownloadNotFound(_ message: String) -> Bool {
        message.contains("Active Download not found")
    }

    nonisolated static func isDownloadResultNotFound(_ message: String) -> Bool {
        message.contains("Download Result not found")
            || message.contains("GID")
            && message.contains("is not found")
    }

    nonisolated private static func responsePreview(from data: Data) -> String? {
        guard !data.isEmpty else { return "<empty>" }

        let text = String(decoding: data.prefix(240), as: UTF8.self)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return text.isEmpty ? "<non-text \(data.count) bytes>" : text
    }
    
    private func sendRequest<T: Codable>(method: String, params: [Any] = [], usesAria2Namespace: Bool = true) async throws -> T {
        for attempt in 0...Self.maxRetryCount {
            do {
                let id = generateID()
                let resolvedMethod = usesAria2Namespace ? "aria2.\(method)" : method
                let request = Aria2Request(
                    jsonrpc: "2.0",
                    id: id,
                    method: resolvedMethod,
                    params: params.map { AnyCodable($0) }
                )

                var urlRequest = URLRequest(url: rpcURL)
                urlRequest.httpMethod = "POST"
                urlRequest.timeoutInterval = Self.requestTimeout
                urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                urlRequest.httpBody = try JSONEncoder().encode(request)

                await MatrixDebugLogger.shared.log(
                    event: "rpc.request",
                    metadata: [
                        "attempt": String(attempt),
                        "id": id,
                        "method": resolvedMethod,
                        "paramCount": String(params.count),
                        "port": String(currentPort),
                        "url": rpcURL.absoluteString
                    ],
                    level: .debug
                )

                let (data, response) = try await session.data(for: urlRequest)

                guard let httpResponse = response as? HTTPURLResponse else {
                    await MatrixDebugLogger.shared.log(
                        event: "rpc.invalidHTTPResponse",
                        metadata: [
                            "id": id,
                            "method": resolvedMethod,
                            "preview": Self.responsePreview(from: data) ?? "<nil>",
                            "status": "-1"
                        ],
                        level: .error
                    )
                    throw Aria2Error.invalidResponse
                }

                await MatrixDebugLogger.shared.log(
                    event: "rpc.response",
                    metadata: [
                        "bytes": String(data.count),
                        "id": id,
                        "method": resolvedMethod,
                        "preview": Self.responsePreview(from: data) ?? "<nil>",
                        "status": String(httpResponse.statusCode)
                    ],
                    level: .debug
                )

                let decodedResponse: Aria2Response<T>
                do {
                    decodedResponse = try JSONDecoder().decode(Aria2Response<T>.self, from: data)
                } catch {
                    await MatrixDebugLogger.shared.log(
                        event: "rpc.decodeError",
                        metadata: [
                            "error": error.localizedDescription,
                            "id": id,
                            "method": resolvedMethod,
                            "preview": Self.responsePreview(from: data) ?? "<nil>"
                        ],
                        level: .error
                    )
                    throw Aria2Error.decodingError(
                        underlying: error,
                        responsePreview: Self.responsePreview(from: data)
                    )
                }

                if let error = decodedResponse.error {
                    if httpResponse.statusCode != 200 {
                        await MatrixDebugLogger.shared.log(
                            event: "rpc.invalidHTTPResponse",
                            metadata: [
                                "id": id,
                                "method": resolvedMethod,
                                "preview": Self.responsePreview(from: data) ?? "<nil>",
                                "status": String(httpResponse.statusCode)
                            ],
                            level: .error
                        )
                    }
                    await MatrixDebugLogger.shared.log(
                        event: "rpc.rpcError",
                        metadata: [
                            "code": String(error.code),
                            "id": id,
                            "message": error.message,
                            "method": resolvedMethod
                        ],
                        level: .error
                    )
                    throw Aria2Error.rpcError(error.message)
                }

                guard httpResponse.statusCode == 200 else {
                    await MatrixDebugLogger.shared.log(
                        event: "rpc.invalidHTTPResponse",
                        metadata: [
                            "id": id,
                            "method": resolvedMethod,
                            "preview": Self.responsePreview(from: data) ?? "<nil>",
                            "status": String(httpResponse.statusCode)
                        ],
                        level: .error
                    )
                    throw Aria2Error.invalidResponse
                }

                guard let result = decodedResponse.result else {
                    await MatrixDebugLogger.shared.log(
                        event: "rpc.emptyResult",
                        metadata: [
                            "id": id,
                            "method": resolvedMethod
                        ],
                        level: .error
                    )
                    throw Aria2Error.invalidResponse
                }

                return result
            } catch {
                let shouldRetry = attempt < Self.maxRetryCount && Self.isTransientTransportError(error)
                await MatrixDebugLogger.shared.log(
                    event: "rpc.requestError",
                    metadata: [
                        "attempt": String(attempt),
                        "error": error.localizedDescription,
                        "method": usesAria2Namespace ? "aria2.\(method)" : method,
                        "retry": shouldRetry ? "true" : "false"
                    ],
                    level: .error
                )
                if shouldRetry {
                    try? await Task.sleep(for: .milliseconds(300 * (attempt + 1)))
                    continue
                }
                throw error
            }
        }

        throw Aria2Error.invalidResponse
    }

    private func statusParams(gid: String, keys: [String]?) -> [Any] {
        if let keys, !keys.isEmpty {
            return [gid, keys]
        }
        return [gid]
    }
    
    func addDownload(
        url: String,
        savePath: String? = nil,
        filename: String? = nil,
        threadCount: Int = 16,
        startImmediately: Bool = true
    ) async throws -> String {
        var options: [String: Any] = [
            "split": threadCount,
            "max-connection-per-server": min(threadCount, 16)
        ]
        
        if let savePath = savePath {
            options["dir"] = savePath
        }
        
        if let filename = filename {
            options["out"] = filename
        }

        if !startImmediately {
            options["pause"] = "true"
        }
        
        let params: [Any] = [[url], options]
        // addUri returns a string (GID) directly, not an object
        let gid: String = try await sendRequest(method: "addUri", params: params)
        return gid
    }
    
    func addTorrent(base64Torrent: String, savePath: String? = nil, startImmediately: Bool = true) async throws -> String {
        var options: [String: Any] = [:]
        if let savePath = savePath {
            options["dir"] = savePath
        }
        if !startImmediately {
            options["pause"] = "true"
        }
        
        // addTorrent takes: torrent, uris, options, position.
        // We don't supply web seed URIs here, so the second argument must be an empty array.
        let params: [Any] = [base64Torrent, [String](), options]
        // addTorrent returns a string (GID) directly
        let gid: String = try await sendRequest(method: "addTorrent", params: params)
        return gid
    }

    func addMetalink(metalink: String, savePath: String? = nil, startImmediately: Bool = true) async throws -> [String] {
        var options: [String: Any] = [:]
        if let savePath = savePath {
            options["dir"] = savePath
        }
        if !startImmediately {
            options["pause"] = "true"
        }

        let params: [Any] = [metalink, options]
        // addMetalink returns an array of strings (GIDs) directly
        let gids: [String] = try await sendRequest(method: "addMetalink", params: params)
        return gids
    }

    func getStatus(gid: String, keys: [String]? = nil) async throws -> Aria2Status {
        let params = statusParams(gid: gid, keys: keys)
        return try await sendRequest(method: "tellStatus", params: params)
    }

    func getStatusesBatch(gids: [String], keys: [String]? = nil) async throws -> (statuses: [Aria2Status], missingGIDs: [String]) {
        guard !gids.isEmpty else { return (statuses: [], missingGIDs: []) }

        let calls = gids.map { gid in
            [
                "methodName": "aria2.tellStatus",
                "params": statusParams(gid: gid, keys: keys)
            ]
        }
        let results: [Aria2MulticallItem<Aria2Status>] = try await sendRequest(
            method: "system.multicall",
            params: [calls],
            usesAria2Namespace: false
        )
        for (index, item) in results.enumerated() where item.error != nil {
            await MatrixDebugLogger.shared.log(
                event: "rpc.multicallItemError",
                metadata: [
                    "errorCode": String(item.error?.code ?? -1),
                    "errorMessage": item.error?.message ?? "<nil>",
                    "gid": gids.indices.contains(index) ? gids[index] : "<unknown>",
                    "index": String(index)
                ],
                level: .error
            )
        }
        let missingGIDs: [String] = results.compactMap { item in
            guard let error = item.error else { return nil }
            return Self.missingGID(from: error.message)
        }
        return (statuses: results.flatMap(\.values), missingGIDs: missingGIDs)
    }

    func getStatuses(gids: [String], keys: [String]? = nil) async throws -> [Aria2Status] {
        let result = try await getStatusesBatch(gids: gids, keys: keys)
        return result.statuses
    }

    func getFiles(gid: String) async throws -> [Aria2File] {
        let params: [Any] = [gid]
        return try await sendRequest(method: "getFiles", params: params)
    }

    func getPeers(gid: String) async throws -> [Aria2Peer] {
        let params: [Any] = [gid]
        return try await sendRequest(method: "getPeers", params: params)
    }

    func getOption(gid: String) async throws -> [String: String] {
        let params: [Any] = [gid]
        return try await sendRequest(method: "getOption", params: params)
    }

    func pauseDownload(gid: String) async throws -> String {
        let params: [Any] = [gid]
        // pause returns a string (GID) directly
        let resultGid: String = try await sendRequest(method: "pause", params: params)
        return resultGid
    }

    func resumeDownload(gid: String) async throws -> String {
        let params: [Any] = [gid]
        // unpause returns a string (GID) directly
        let resultGid: String = try await sendRequest(method: "unpause", params: params)
        return resultGid
    }

    func removeDownload(gid: String) async throws -> String {
        let params: [Any] = [gid]
        do {
            let resultGid: String = try await sendRequest(method: "remove", params: params)
            return resultGid
        } catch Aria2Error.rpcError(let message) where Self.isActiveDownloadNotFound(message) {
            await MatrixDebugLogger.shared.log(
                event: "rpc.removeDownload.alreadyInactive",
                metadata: [
                    "gid": gid,
                    "message": message
                ],
                level: .info
            )
            return gid
        }
    }

    func removeDownloadResult(gid: String) async throws -> String {
        let params: [Any] = [gid]
        do {
            let resultGid: String = try await sendRequest(method: "removeDownloadResult", params: params)
            return resultGid
        } catch Aria2Error.rpcError(let message) where Self.isDownloadResultNotFound(message) {
            await MatrixDebugLogger.shared.log(
                event: "rpc.removeDownloadResult.alreadyMissing",
                metadata: [
                    "gid": gid,
                    "message": message
                ],
                level: .info
            )
            return gid
        }
    }
    
    func getActiveDownloads(keys: [String]? = nil) async throws -> [Aria2Status] {
        let params: [Any] = if let keys, !keys.isEmpty { [keys] } else { [] }
        return try await sendRequest(method: "tellActive", params: params)
    }

    func getWaitingDownloads(offset: Int = 0, num: Int = 100, keys: [String]? = nil) async throws -> [Aria2Status] {
        var params: [Any] = [offset, num]
        if let keys, !keys.isEmpty {
            params.append(keys)
        }
        return try await sendRequest(method: "tellWaiting", params: params)
    }

    func getStoppedDownloads(offset: Int = 0, num: Int = 100, keys: [String]? = nil) async throws -> [Aria2Status] {
        var params: [Any] = [offset, num]
        if let keys, !keys.isEmpty {
            params.append(keys)
        }
        return try await sendRequest(method: "tellStopped", params: params)
    }
    
    func getGlobalStat() async throws -> Aria2GlobalStat {
        return try await sendRequest(method: "getGlobalStat")
    }
    
    func getVersion() async throws -> Aria2Version {
        return try await sendRequest(method: "getVersion")
    }
    
    func changeGlobalOption(options: [String: Any]) async throws {
        let params: [Any] = [options]
        let _: String = try await sendRequest(method: "changeGlobalOption", params: params)
    }

    func changeOption(gid: String, options: [String: Any]) async throws {
        let params: [Any] = [gid, options]
        let _: String = try await sendRequest(method: "changeOption", params: params)
    }

    func purgeDownloadResult() async throws -> String {
        let result: String = try await sendRequest(method: "purgeDownloadResult")
        return result
    }

    func forceSaveSession() async throws -> String {
        let result: String = try await sendRequest(method: "saveSession")
        return result
    }
}

nonisolated struct Aria2GlobalStat: Codable {
    let downloadSpeed: String
    let uploadSpeed: String
    let numActive: String
    let numWaiting: String
    let numStopped: String
    let numStoppedTotal: String

    private enum CodingKeys: String, CodingKey {
        case downloadSpeed
        case uploadSpeed
        case numActive
        case numWaiting
        case numStopped
        case numStoppedTotal
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        downloadSpeed = try container.decodeLossyString(forKey: .downloadSpeed, defaultValue: "0")
        uploadSpeed = try container.decodeLossyString(forKey: .uploadSpeed, defaultValue: "0")
        numActive = try container.decodeLossyString(forKey: .numActive, defaultValue: "0")
        numWaiting = try container.decodeLossyString(forKey: .numWaiting, defaultValue: "0")
        numStopped = try container.decodeLossyString(forKey: .numStopped, defaultValue: "0")
        numStoppedTotal = try container.decodeLossyString(forKey: .numStoppedTotal, defaultValue: "0")
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyString(forKey key: Key, defaultValue: String? = nil) throws -> String {
        if let value = try? decode(String.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int64.self, forKey: key) {
            return String(value)
        }
        if let value = try? decode(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decode(Double.self, forKey: key) {
            return String(value)
        }
        if let value = try? decode(Bool.self, forKey: key) {
            return value ? "true" : "false"
        }
        if let defaultValue {
            return defaultValue
        }
        throw DecodingError.typeMismatch(
            String.self,
            DecodingError.Context(codingPath: codingPath + [key], debugDescription: "Expected String/Int/Bool convertible value")
        )
    }

    func decodeLossyStringIfPresent(forKey key: Key) throws -> String? {
        if !contains(key) {
            return nil
        }
        if (try? decodeNil(forKey: key)) == true {
            return nil
        }
        return try decodeLossyString(forKey: key)
    }
}

nonisolated struct Aria2Version: Codable {
    let version: String
    let enabledFeatures: [String]?
}
