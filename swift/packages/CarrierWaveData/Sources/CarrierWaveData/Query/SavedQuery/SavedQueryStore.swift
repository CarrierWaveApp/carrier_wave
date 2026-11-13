import Foundation
import OSLog

public actor SavedQueryStore {
    // MARK: Lifecycle

    public init(directory: URL) {
        self.directory = directory
    }

    // MARK: Public

    public enum ImportError: Error, Equatable {
        case schemaTooNew(authored: Int, supported: Int)
        case decodeFailed
    }

    public func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func list() throws -> [SavedQuery] {
        try ensureDirectory()
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        let queryURLs = urls.filter { $0.pathExtension == "cwquery" }
        var loaded: [SavedQuery] = []
        for url in queryURLs {
            do {
                let data = try Data(contentsOf: url)
                let query = try SavedQueryCoder.decode(data)
                loaded.append(query)
            } catch {
                logger.error("Failed to load \(url.lastPathComponent, privacy: .public): \(error)")
            }
        }
        return loaded.sorted { $0.createdAt < $1.createdAt }
    }

    public func save(_ query: SavedQuery) throws {
        try ensureDirectory()
        let url = fileURL(for: query)
        let data = try SavedQueryCoder.encode(query)
        try data.write(to: url, options: .atomic)
    }

    public func delete(_ query: SavedQuery) throws {
        let url = fileURL(for: query)
        try FileManager.default.removeItem(at: url)
    }

    public func importQuery(_ query: SavedQuery) throws -> SavedQuery {
        if query.schemaVersion > QuerySchemaVersion.current {
            throw ImportError.schemaTooNew(
                authored: query.schemaVersion,
                supported: QuerySchemaVersion.current
            )
        }
        var copy = query
        copy.id = UUID()
        copy.createdAt = Date()
        try save(copy)
        return copy
    }

    // MARK: Private

    private let directory: URL
    private let logger = Logger(subsystem: "com.fullduplex.shared", category: "SavedQueryStore")

    private func fileURL(for query: SavedQuery) -> URL {
        let safe = query.name.replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent("\(safe)-\(query.id.uuidString).cwquery")
    }
}
