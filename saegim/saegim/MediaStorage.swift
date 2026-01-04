import CryptoKit
import Foundation

enum MediaStorage {
    private static let mediaDir = "media"

    private static let supportedImageExtensions = ["jpg", "jpeg", "png", "gif", "webp", "bmp", "svg"]
    private static let supportedAudioExtensions = ["mp3", "wav", "m4a", "ogg", "flac", "aac", "opus"]

    /// Check if a file extension is a supported media type.
    static func isSupported(extension ext: String) -> Bool {
        let lowercased = ext.lowercased()
        return supportedImageExtensions.contains(lowercased) || supportedAudioExtensions.contains(lowercased)
    }

    /// Check if a file extension is an audio type.
    static func isAudio(extension ext: String) -> Bool {
        supportedAudioExtensions.contains(ext.lowercased())
    }

    /// Stores media data and returns the relative path (hash-based with 2-char prefix sharding).
    /// If file already exists with same hash, returns existing path without re-writing.
    /// Returns: relative path in format "ab/abcd1234...xyz.ext" or nil on failure
    static func store(_ data: Data, extension ext: String) -> String? {
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

        let baseDir = appSupport.appendingPathComponent("Saegim/\(mediaDir)", isDirectory: true)
        let shardDir = baseDir.appendingPathComponent(prefix, isDirectory: true)
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

    /// Stores media from a file URL. Returns relative path or nil on failure.
    static func store(from sourceURL: URL) -> String? {
        guard let data = try? Data(contentsOf: sourceURL) else {
            NSLog("MediaStorage: Failed to read source file: %@", sourceURL.path)
            return nil
        }
        let ext = sourceURL.pathExtension
        return store(data, extension: ext)
    }

    /// Resolves a saegim:// URL to a file system URL.
    static func resolve(_ url: URL) -> URL? {
        guard url.scheme == "saegim" else {
            if url.scheme == "file" {
                return url
            }
            return URL(fileURLWithPath: url.absoluteString)
        }

        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        // saegim://media/ab/hash.ext -> Saegim/media/ab/hash.ext
        guard let host = url.host, host == mediaDir else { return nil }
        let path = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        return appSupport.appendingPathComponent("Saegim/\(mediaDir)/\(path)")
    }

    /// Builds a saegim:// URL from a relative path.
    static func buildURL(relativePath: String) -> String {
        "saegim://\(mediaDir)/\(relativePath)"
    }
}
