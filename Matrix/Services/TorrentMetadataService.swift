import Foundation

struct TorrentPreviewFile: Identifiable, Hashable {
    let index: Int
    let path: String
    let length: Int64

    var id: Int { index }
}

struct TorrentPreview: Hashable {
    let name: String
    let files: [TorrentPreviewFile]
    let trackers: [String]
}

enum TorrentMetadataError: LocalizedError {
    case invalidFormat
    case missingInfo

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid torrent metadata"
        case .missingInfo:
            return "Missing torrent info dictionary"
        }
    }
}

enum TorrentMetadataService {
    static func parse(fileURL: URL) throws -> TorrentPreview {
        let data = try Data(contentsOf: fileURL)
        var parser = BencodeParser(data: data)
        let rootValue = try parser.parse()
        guard let root = dictionary(from: rootValue),
              let info = dictionary(from: root["info"]) else {
            throw TorrentMetadataError.missingInfo
        }

        let name = string(from: info["name.utf-8"] ?? info["name"]) ?? fileURL.deletingPathExtension().lastPathComponent
        let files: [TorrentPreviewFile]
        if let fileList = list(from: info["files"]) {
            files = fileList.enumerated().compactMap { offset, value in
                guard let fileDict = dictionary(from: value),
                      let length = integer(from: fileDict["length"]) else {
                    return nil
                }

                let pathComponents = listOfStrings(from: fileDict["path.utf-8"] ?? fileDict["path"]) ?? []
                let path = ([name] + pathComponents).joined(separator: "/")
                return TorrentPreviewFile(index: offset + 1, path: path, length: length)
            }
        } else if let length = integer(from: info["length"]) {
            files = [TorrentPreviewFile(index: 1, path: name, length: length)]
        } else {
            files = []
        }

        var trackers = [String]()
        if let announce = string(from: root["announce"]) {
            trackers.append(announce)
        }
        if let announceList = list(from: root["announce-list"]) {
            trackers.append(contentsOf: announceList.flatMap { tier in
                listOfStrings(from: tier) ?? []
            })
        }

        return TorrentPreview(
            name: name,
            files: files,
            trackers: Array(NSOrderedSet(array: trackers).compactMap { $0 as? String })
        )
    }

    private static func integer(from value: BencodeValue?) -> Int64? {
        guard case .integer(let intValue)? = value else { return nil }
        return intValue
    }

    private static func dictionary(from value: BencodeValue?) -> [String: BencodeValue]? {
        guard case .dictionary(let dictionary)? = value else { return nil }
        return dictionary
    }

    private static func list(from value: BencodeValue?) -> [BencodeValue]? {
        guard case .list(let list)? = value else { return nil }
        return list
    }

    private static func string(from value: BencodeValue?) -> String? {
        guard case .bytes(let data)? = value else { return nil }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    private static func listOfStrings(from value: BencodeValue?) -> [String]? {
        guard case .list(let list)? = value else { return nil }
        return list.compactMap { string(from: $0) }
    }
}

private enum BencodeValue {
    case integer(Int64)
    case bytes(Data)
    case list([BencodeValue])
    case dictionary([String: BencodeValue])
}

private struct BencodeParser {
    let data: Data
    private var bytes: [UInt8] { Array(data) }
    private var count: Int { data.count }
    private var currentIndex = 0

    init(data: Data) {
        self.data = data
    }

    mutating func parse() throws -> BencodeValue {
        let value = try parseValue()
        guard currentIndex == count else {
            throw TorrentMetadataError.invalidFormat
        }
        return value
    }

    private mutating func parseValue() throws -> BencodeValue {
        guard currentIndex < count else { throw TorrentMetadataError.invalidFormat }
        switch bytes[currentIndex] {
        case UInt8(ascii: "i"):
            return try parseInteger()
        case UInt8(ascii: "l"):
            return try parseList()
        case UInt8(ascii: "d"):
            return try parseDictionary()
        case UInt8(ascii: "0")...UInt8(ascii: "9"):
            return try parseBytes()
        default:
            throw TorrentMetadataError.invalidFormat
        }
    }

    private mutating func parseInteger() throws -> BencodeValue {
        currentIndex += 1
        let start = currentIndex
        while currentIndex < count, bytes[currentIndex] != UInt8(ascii: "e") {
            currentIndex += 1
        }
        guard currentIndex < count,
              let string = String(data: data.subdata(in: start..<currentIndex), encoding: .utf8),
              let value = Int64(string) else {
            throw TorrentMetadataError.invalidFormat
        }
        currentIndex += 1
        return .integer(value)
    }

    private mutating func parseBytes() throws -> BencodeValue {
        let start = currentIndex
        while currentIndex < count, bytes[currentIndex] != UInt8(ascii: ":") {
            currentIndex += 1
        }
        guard currentIndex < count,
              let lengthString = String(data: data.subdata(in: start..<currentIndex), encoding: .utf8),
              let length = Int(lengthString) else {
            throw TorrentMetadataError.invalidFormat
        }
        currentIndex += 1
        let end = currentIndex + length
        guard end <= count else { throw TorrentMetadataError.invalidFormat }
        let value = data.subdata(in: currentIndex..<end)
        currentIndex = end
        return .bytes(value)
    }

    private mutating func parseList() throws -> BencodeValue {
        currentIndex += 1
        var values = [BencodeValue]()
        while currentIndex < count, bytes[currentIndex] != UInt8(ascii: "e") {
            values.append(try parseValue())
        }
        guard currentIndex < count else { throw TorrentMetadataError.invalidFormat }
        currentIndex += 1
        return .list(values)
    }

    private mutating func parseDictionary() throws -> BencodeValue {
        currentIndex += 1
        var dict = [String: BencodeValue]()
        while currentIndex < count, bytes[currentIndex] != UInt8(ascii: "e") {
            guard case .bytes(let keyData) = try parseBytes() else {
                throw TorrentMetadataError.invalidFormat
            }
            let value = try parseValue()
            let key = String(data: keyData, encoding: .utf8) ?? String(decoding: keyData, as: UTF8.self)
            dict[key] = value
        }
        guard currentIndex < count else { throw TorrentMetadataError.invalidFormat }
        currentIndex += 1
        return .dictionary(dict)
    }
}
