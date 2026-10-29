import Foundation

public protocol DataStore: Sendable {
    func load() throws -> AppData?
    func save(_ data: AppData) throws
    func erase() throws
}

/// Saves `AppData` as a JSON file. On iOS the file is encrypted while the phone is locked.
public struct FileDataStore: DataStore {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Application Support/Worth/worth.json. It's included in device backups so manual assets,
    /// rules and history beyond SimpleFIN's 90-day window survive a phone upgrade.
    public static func standard() throws -> FileDataStore {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("Worth", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return FileDataStore(url: dir.appendingPathComponent("worth.json"))
    }

    public func load() throws -> AppData? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try Self.decoder.decode(AppData.self, from: data)
    }

    public func save(_ appData: AppData) throws {
        let data = try Self.encoder.encode(appData)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: [.atomic])
        #endif
    }

    public func erase() throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

public final class InMemoryDataStore: DataStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: AppData?

    public init(_ data: AppData? = nil) {
        stored = data
    }

    public func load() throws -> AppData? { lock.withLock { stored } }
    public func save(_ data: AppData) throws { lock.withLock { stored = data } }
    public func erase() throws { lock.withLock { stored = nil } }
}

/// Where API credentials live. The app uses the iOS keychain; tests use memory.
public protocol SecretStore: Sendable {
    func secret(for key: String) -> String?
    func setSecret(_ value: String?, for key: String) throws
}

public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    public init(_ values: [String: String] = [:]) {
        self.values = values
    }

    public func secret(for key: String) -> String? { lock.withLock { values[key] } }

    public func setSecret(_ value: String?, for key: String) throws {
        lock.withLock { values[key] = value }
    }
}

public enum SecretKey {
    public static let simpleFINAccessURL = "simplefin.accessURL"
}
