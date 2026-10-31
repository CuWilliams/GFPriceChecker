//
//  BackupFormat.swift
//  GFCore
//
//  Moved from GFPriceChecker/Services/DataBackupService.swift on 2026-10-31 (#70).
//

import Foundation

/// A backup that can't be read as this version of the format
public enum BackupFormatError: Error, Equatable, Sendable {
    /// The file decoded, but declares a version other than `BackupFormat.version`
    case incompatibleVersion(String)
}

/// The coder settings and version gate for `BackupData`
///
/// ISO 8601 dates with one-second resolution, sorted keys, and decimals as strings. A
/// backup is accepted only if its `version` is exactly `BackupFormat.version`.
public enum BackupFormat {

    /// The format version written to, and required of, every backup
    public static let version = "1.0"

    // MARK: - Coders

    /// The encoder for writing a backup: ISO 8601 dates, pretty-printed, sorted keys
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    /// The decoder for reading a backup: ISO 8601 dates
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Encodes a backup for writing to a file
    public static func encode(_ backup: BackupData) throws -> Data {
        try makeEncoder().encode(backup)
    }

    /// Decodes a backup and checks its version
    ///
    /// - Throws: `DecodingError` if the data isn't a backup, and
    ///   `BackupFormatError.incompatibleVersion` if it is one of another version
    public static func decode(_ data: Data) throws -> BackupData {
        let backup = try makeDecoder().decode(BackupData.self, from: data)

        guard backup.version == version else {
            throw BackupFormatError.incompatibleVersion(backup.version)
        }

        return backup
    }

    // MARK: - Decimals

    /// A decimal as the backup writes it: `Decimal.description`, which is locale-independent
    public static func string(from decimal: Decimal) -> String {
        "\(decimal)"
    }

    /// A decimal read from a backup string, or `nil` if it isn't wholly a plain decimal
    ///
    /// Strict, and not trimmed: a backup is machine-written, and `string(from:)` has only ever
    /// written `-`, digits and a `.`. Every backup known to exist reads the same as it did
    /// under `Decimal(string:)`, including both `Tools/Demo` datasets.
    public static func decimal(from string: String) -> Decimal? {
        PlainDecimal(string)?.value
    }
}
