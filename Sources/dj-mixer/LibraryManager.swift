import Foundation

// MARK: - Library Persistence

struct LibraryManager {
    static let `default` = LibraryManager()
    
    private var libraryURL: URL {
        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("dj-mixer")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("library.json")
    }
    
    func load() -> Library {
        guard let data = try? Data(contentsOf: libraryURL),
              let lib = try? JSONDecoder().decode(Library.self, from: data) else {
            return Library()
        }
        return lib
    }
    
    func save(_ library: Library) {
        guard let data = try? JSONEncoder().encode(library) else { return }
        try? data.write(to: libraryURL, options: .atomic)
    }
}

struct Library: Codable {
    var tracks: [TrackRecord] = []
    var playlists: [PlaylistRecord] = []
}

struct TrackRecord: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var bookmarkData: Data  // security-scoped bookmark
    var duration: TimeInterval
    var added: Date
    
    func resolveURL() -> URL? {
        var stale = false
        return try? URL(resolvingBookmarkData: bookmarkData,
                        options: .withSecurityScope,
                        relativeTo: nil,
                        bookmarkDataIsStale: &stale)
    }
    
    static func from(url: URL, duration: TimeInterval) -> Self? {
        guard let data = try? url.bookmarkData(options: .withSecurityScope,
                                                includingResourceValuesForKeys: nil,
                                                relativeTo: nil) else { return nil }
        return TrackRecord(id: UUID(), name: url.lastPathComponent,
                          bookmarkData: data, duration: duration, added: Date())
    }
}

struct PlaylistRecord: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var trackIds: [UUID]
    var created: Date
}
