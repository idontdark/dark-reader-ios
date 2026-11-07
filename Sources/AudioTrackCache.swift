import Foundation
import CryptoKit

enum AudioTrackCache {
    static func file(_ book: AudioBook) -> URL {
        let hash = SHA256.hash(data: Data(book.id.utf8)).map { String(format: "%02x",$0) }.joined()
        return FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("AudioTracks",isDirectory:true).appendingPathComponent(hash + ".json")
    }
    static func load(_ book: AudioBook) -> [AudioChapter]? {
        guard let data = try? Data(contentsOf:file(book)) else { return nil }
        return try? JSONDecoder().decode([AudioChapter].self,from:data)
    }
    static func save(_ chapters: [AudioChapter], for book: AudioBook) {
        let url = file(book)
        try? FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        if let data = try? JSONEncoder().encode(chapters) { try? data.write(to:url,options:.atomic) }
    }
}
