import CryptoKit
import Foundation

enum MediaType: String {
    case image = "images"
    case audio = "audio"

    static func from(extension ext: String) -> MediaType? {
        let lowercased = ext.lowercased()
        if ["jpg", "jpeg", "png", "gif", "webp", "bmp", "svg"].contains(lowercased) {
            return .image
        }
        if ["mp3", "wav", "m4a", "ogg", "flac", "aac", "opus"].contains(lowercased) {
            return .audio
        }
        return nil
    }
}

enum MediaStorage {

    /// Stores media data and returns the filename (hash-based with 2-char prefix sharding).
    /// If file already exists with same hash, returns existing path without re-writing.
    /// Returns: filename in format "ab/abcd1234...xyz.ext" or nil on failure
    static func store(_ data: Data, extension ext: String, type: MediaType) -> String? {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        // Compute SHA256 hash
        let hash = SHA256.hash(data: data)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

        // 2-char prefix for sharding: ab/abcd1234...xyz.ext
        let prefix = String(hashString.prefix(2))
        let filename = "\(hashString).\(ext.lowercased())"
        let relativePath = "\(prefix)/\(filename)"

        let typeDir = appSupport.appendingPathComponent("Saegim/\(type.rawValue)", isDirectory: true)
        let shardDir = typeDir.appendingPathComponent(prefix, isDirectory: true)
        let destURL = shardDir.appendingPathComponent(filename)

        // Skip if file already exists (deduplication)
        if fileManager.fileExists(atPath: destURL.path) {
            return relativePath
        }

        // Create shard directory if needed
        do {
            try fileManager.createDirectory(at: shardDir, withIntermediateDirectories: true)
            try data.write(to: destURL)
            return relativePath
        } catch {
            NSLog("MediaStorage: Failed to write media: %@", error.localizedDescription)
            return nil
        }
    }

    /// Stores media from a file URL. Returns filename or nil on failure.
    static func store(from sourceURL: URL, type: MediaType) -> String? {
        guard let data = try? Data(contentsOf: sourceURL) else {
            NSLog("MediaStorage: Failed to read source file: %@", sourceURL.path)
            return nil
        }
        let ext = sourceURL.pathExtension
        return store(data, extension: ext, type: type)
    }

    /// Resolves a saegim:// URL to a file system URL.
    /// Handles both old flat format (images/file.jpg) and new sharded format (images/ab/file.jpg)
    static func resolve(_ url: URL) -> URL? {
        guard url.scheme == "saegim" else {
            // Handle file:// or raw paths
            if url.scheme == "file" {
                return url
            }
            return URL(fileURLWithPath: url.absoluteString)
        }

        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        // saegim://images/ab/filename.jpg or saegim://images/filename.jpg (legacy)
        guard let host = url.host else { return nil }
        let path = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        let relativePath = "\(host)/\(path)"

        return appSupport.appendingPathComponent("Saegim/\(relativePath)")
    }

    /// Builds a saegim:// URL from a relative path and media type.
    static func buildURL(relativePath: String, type: MediaType) -> String {
        "saegim://\(type.rawValue)/\(relativePath)"
    }
}
