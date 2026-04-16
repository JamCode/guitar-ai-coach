import Foundation

struct SheetEntry: Identifiable, Equatable, Hashable {
    let id: String
    var displayName: String
    var storedFileNames: [String]
    let addedAtMs: Int
    var serverPageCount: Int?
    var parseStatus: String
    var parsedUpdatedAtMs: Int?

    var pageCount: Int { serverPageCount ?? storedFileNames.count }
}

enum SheetParseStatus: String, CaseIterable {
    case rawOnly
    case draft
    case ready
}

struct SheetSegment: Equatable {
    var chords: [String]
    var melody: String
    var lyrics: String
}

struct SheetParsedData: Equatable {
    let sheetId: String
    var parseStatus: SheetParseStatus
    var originalKey: String
    var segments: [SheetSegment]
    let updatedAtMs: Int

    var hasContent: Bool {
        segments.contains { !$0.chords.isEmpty || !$0.melody.isEmpty || !$0.lyrics.isEmpty }
    }
}

extension SheetEntry {
    func toJSON() -> [String: Any] {
        var out: [String: Any] = [
            "id": id,
            "displayName": displayName,
            "storedFileNames": storedFileNames,
            "addedAtMs": addedAtMs,
            "parseStatus": parseStatus
        ]
        if let serverPageCount { out["serverPageCount"] = serverPageCount }
        if let parsedUpdatedAtMs { out["parsedUpdatedAtMs"] = parsedUpdatedAtMs }
        return out
    }

    static func fromJSON(_ raw: Any?) -> SheetEntry? {
        guard let raw = raw as? [String: Any] else { return nil }
        guard let id = raw["id"] as? String, let dn = raw["displayName"] as? String else { return nil }
        guard let addedAtMs = toInt(raw["addedAtMs"]) else { return nil }
        let parseStatus = (raw["parseStatus"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? SheetParseStatus.rawOnly.rawValue
        let parsedUpdatedAtMs = toInt(raw["parsedUpdatedAtMs"])
        let serverPageCount = toInt(raw["serverPageCount"])

        if let names = raw["storedFileNames"] as? [String] {
            let filtered = names.filter { !$0.isEmpty }
            if !filtered.isEmpty {
                return SheetEntry(
                    id: id,
                    displayName: dn,
                    storedFileNames: filtered,
                    addedAtMs: addedAtMs,
                    serverPageCount: serverPageCount,
                    parseStatus: parseStatus,
                    parsedUpdatedAtMs: parsedUpdatedAtMs
                )
            }
        }

        if let legacy = raw["storedFileName"] as? String, !legacy.isEmpty {
            return SheetEntry(
                id: id,
                displayName: dn,
                storedFileNames: [legacy],
                addedAtMs: addedAtMs,
                serverPageCount: serverPageCount,
                parseStatus: parseStatus,
                parsedUpdatedAtMs: parsedUpdatedAtMs
            )
        }

        if let serverPageCount, serverPageCount > 0 {
            return SheetEntry(
                id: id,
                displayName: dn,
                storedFileNames: [],
                addedAtMs: addedAtMs,
                serverPageCount: serverPageCount,
                parseStatus: parseStatus,
                parsedUpdatedAtMs: parsedUpdatedAtMs
            )
        }
        return nil
    }
}

extension SheetSegment {
    func toJSON() -> [String: Any] {
        ["chords": chords, "melody": melody, "lyrics": lyrics]
    }

    static func fromJSON(_ raw: Any?) -> SheetSegment {
        guard let raw = raw as? [String: Any] else {
            return SheetSegment(chords: [], melody: "", lyrics: "")
        }
        let chords = (raw["chords"] as? [String])?.filter { !$0.isEmpty } ?? []
        let melody = raw["melody"] as? String ?? ""
        let lyrics = raw["lyrics"] as? String ?? ""
        return SheetSegment(chords: chords, melody: melody, lyrics: lyrics)
    }
}

extension SheetParsedData {
    func toJSON() -> [String: Any] {
        [
            "sheetId": sheetId,
            "parseStatus": parseStatus.rawValue,
            "originalKey": originalKey,
            "segments": segments.map { $0.toJSON() },
            "updatedAtMs": updatedAtMs
        ]
    }

    func toJSONString() throws -> String {
        let data = try JSONSerialization.data(withJSONObject: toJSON(), options: [])
        guard let out = String(data: data, encoding: .utf8) else {
            throw SheetLibraryError.encodingFailed
        }
        return out
    }

    static func fromJSON(_ raw: Any?) -> SheetParsedData? {
        guard let raw = raw as? [String: Any] else { return nil }
        guard let sheetId = raw["sheetId"] as? String, !sheetId.isEmpty else { return nil }
        guard let originalKey = raw["originalKey"] as? String, !originalKey.isEmpty else { return nil }
        guard let updatedAtMs = toInt(raw["updatedAtMs"]) else { return nil }
        let statusRaw = raw["parseStatus"] as? String ?? SheetParseStatus.ready.rawValue
        let status = SheetParseStatus(rawValue: statusRaw) ?? .ready
        let segments = (raw["segments"] as? [Any] ?? []).map { SheetSegment.fromJSON($0) }
        return SheetParsedData(
            sheetId: sheetId,
            parseStatus: status,
            originalKey: originalKey,
            segments: segments,
            updatedAtMs: updatedAtMs
        )
    }
}

private func toInt(_ raw: Any?) -> Int? {
    if let v = raw as? Int { return v }
    if let v = raw as? NSNumber { return v.intValue }
    return nil
}
