import Foundation
import AVFoundation

// MARK: - Library Persistence (file copy — no security-scoped bookmarks)

private let fm = FileManager.default

private var appDir: URL {
    let d = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("dj-mixer", isDirectory: true)
    try? fm.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

private var samplesDir: URL {
    let d = appDir.appendingPathComponent("samples", isDirectory: true)
    try? fm.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

private var metaURL: URL {
    appDir.appendingPathComponent("library.json")
}

struct LibraryManager {
    static let `default` = LibraryManager()
    
    func load() -> Library {
        guard let data = try? Data(contentsOf: metaURL),
              let lib = try? JSONDecoder().decode(Library.self, from: data) else {
            return Library()
        }
        return lib
    }
    
    func save(_ library: Library) {
        guard let data = try? JSONEncoder().encode(library) else { return }
        try? data.write(to: metaURL, options: .atomic)
    }
    
    /// Copy an audio file into the samples directory for permanent storage.
    /// Returns the TrackRecord with the local path as the identifier.
    func ingest(url: URL) -> TrackRecord? {
        let ext = url.pathExtension.isEmpty ? "mp3" : url.pathExtension
        let trackId = UUID()
        let dest = samplesDir.appendingPathComponent("\(trackId.uuidString).\(ext)")
        do {
            try fm.copyItem(at: url, to: dest)
        } catch {
            // If copy fails (e.g. cross-device), try coordinate reading
            do {
                let data = try Data(contentsOf: url)
                try data.write(to: dest)
            } catch {
                print("ingest fail: \(error)")
                return nil
            }
        }
        
        // get duration
        let comp = AVURLAsset(url: dest).duration
        let dur = CMTimeGetSeconds(comp)
        
        return TrackRecord(id: trackId, name: url.lastPathComponent,
                          localPath: dest.path, duration: dur.isNaN ? 0 : dur,
                          added: Date())
    }
}

struct Library: Codable {
    var tracks: [TrackRecord] = []
    var playlists: [PlaylistRecord] = []
}

struct TrackRecord: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var localPath: String  // path to the copy in samples dir
    var duration: TimeInterval
    var added: Date
    
    var url: URL? {
        let u = URL(fileURLWithPath: localPath)
        return fm.isReadableFile(atPath: localPath) ? u : nil
    }
}

struct PlaylistRecord: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var trackIds: [UUID]
    var created: Date
}
