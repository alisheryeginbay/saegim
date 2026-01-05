import CryptoKit
import Foundation
import Supabase

enum MediaFormat: String {
    // Images
    case jpeg = "jpg"
    case png = "png"
    case gif = "gif"
    case webp = "webp"
    case bmp = "bmp"
    // Audio
    case mp3 = "mp3"
    case wav = "wav"
    case m4a = "m4a"
    case ogg = "ogg"
    case flac = "flac"

    var isAudio: Bool {
        switch self {
        case .mp3, .wav, .m4a, .ogg, .flac: true
        case .jpeg, .png, .gif, .webp, .bmp: false
        }
    }

    /// Detect format from magic bytes. Returns nil if unrecognized.
    static func detect(from data: Data) -> MediaFormat? {
        guard data.count >= 12 else { return nil }

        let bytes = [UInt8](data.prefix(12))

        // JPEG: FF D8 FF
        if bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
            return .jpeg
        }

        // PNG: 89 50 4E 47 0D 0A 1A 0A
        if bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
            return .png
        }

        // GIF: 47 49 46 38 (GIF8)
        if bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38 {
            return .gif
        }

        // BMP: 42 4D (BM)
        if bytes[0] == 0x42 && bytes[1] == 0x4D {
            return .bmp
        }

        // WebP: RIFF....WEBP
        if bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
            bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50 {
            return .webp
        }

        // WAV: RIFF....WAVE
        if bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
            bytes[8] == 0x57 && bytes[9] == 0x41 && bytes[10] == 0x56 && bytes[11] == 0x45 {
            return .wav
        }

        // MP3: FF FB, FF FA, FF F3 (frame sync) or ID3 tag
        if (bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0) ||
            (bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) {
            return .mp3
        }

        // FLAC: 66 4C 61 43 (fLaC)
        if bytes[0] == 0x66 && bytes[1] == 0x4C && bytes[2] == 0x61 && bytes[3] == 0x43 {
            return .flac
        }

        // OGG: 4F 67 67 53 (OggS)
        if bytes[0] == 0x4F && bytes[1] == 0x67 && bytes[2] == 0x67 && bytes[3] == 0x53 {
            return .ogg
        }

        // M4A/AAC: ftyp at offset 4
        if bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70 {
            return .m4a
        }

        return nil
    }
}

enum MediaStorage {
    private static let mediaDir = "media"

    /// Stores media data and returns the relative path (hash-based with 2-char prefix sharding).
    /// Detects format from magic bytes. Returns nil if format unrecognized or on failure.
    /// Returns: relative path in format "ab/abcd1234...xyz.ext" or nil on failure
    static func store(_ data: Data) -> String? {
        guard let format = MediaFormat.detect(from: data) else {
            NSLog("MediaStorage: Unrecognized media format (size: %d bytes)", data.count)
            return nil
        }
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        // Compute SHA256 hash
        let hash = SHA256.hash(data: data)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

        // 2-char prefix for sharding: ab/abcd1234...xyz.ext
        let prefix = String(hashString.prefix(2))
        let filename = "\(hashString).\(format.rawValue)"
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
        return store(data)
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

    // MARK: - Cloud Storage (Supabase)

    private static let storageBucket = "media"

    /// Uploads media to Supabase Storage. Returns the storage path or nil on failure.
    /// Storage path format: {userId}/{hash}.{ext}
    static func uploadToCloud(_ data: Data, userId: UUID) async throws -> String? {
        guard let format = MediaFormat.detect(from: data) else {
            NSLog("MediaStorage: Unrecognized media format for cloud upload")
            return nil
        }

        // Compute hash for filename
        let hash = SHA256.hash(data: data)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        let filename = "\(hashString).\(format.rawValue)"
        let storagePath = "\(userId.uuidString)/\(filename)"

        let client = await SupabaseManager.shared.client

        // Check if file already exists
        do {
            let files = try await client.storage.from(storageBucket).list(path: "\(userId.uuidString)/", options: .init(search: filename))
            if !files.isEmpty {
                return storagePath
            }
        } catch {
            // File doesn't exist or inaccessible, continue to upload
        }

        // Upload the file
        do {
            let mimeType = format.isAudio ? "audio/\(format.rawValue)" : "image/\(format.rawValue)"
            _ = try await client.storage.from(storageBucket).upload(
                path: storagePath,
                file: data,
                options: FileOptions(contentType: mimeType)
            )
            return storagePath
        } catch {
            NSLog("MediaStorage: Failed to upload to cloud: %@", error.localizedDescription)
            throw error
        }
    }

    /// Downloads media from Supabase Storage. Returns the local relative path or nil on failure.
    static func downloadFromCloud(storagePath: String) async throws -> String? {
        let client = await SupabaseManager.shared.client

        do {
            let data = try await client.storage.from(storageBucket).download(path: storagePath)

            // Store locally and return the relative path
            return store(data)
        } catch {
            NSLog("MediaStorage: Failed to download from cloud: %@", error.localizedDescription)
            throw error
        }
    }

    /// Gets a signed URL for cloud media. Valid for 1 hour.
    static func getCloudURL(storagePath: String) async throws -> URL {
        let client = await SupabaseManager.shared.client

        let signedURL = try await client.storage.from(storageBucket).createSignedURL(
            path: storagePath,
            expiresIn: 3600
        )
        return signedURL
    }

    /// Syncs local media to cloud. Call this after storing media locally.
    static func syncToCloud(relativePath: String, userId: UUID) async throws -> String? {
        guard let fileURL = resolveLocalPath(relativePath) else { return nil }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }

        return try await uploadToCloud(data, userId: userId)
    }

    /// Resolves a relative path to an absolute local file URL.
    private static func resolveLocalPath(_ relativePath: String) -> URL? {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport.appendingPathComponent("Saegim/\(mediaDir)/\(relativePath)")
    }

    /// Checks if a file exists locally.
    static func existsLocally(relativePath: String) -> Bool {
        guard let url = resolveLocalPath(relativePath) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Ensures media is available locally, downloading from cloud if needed.
    static func ensureLocal(relativePath: String, storagePath: String) async throws -> URL? {
        // Check if already exists locally
        if let localURL = resolveLocalPath(relativePath),
           FileManager.default.fileExists(atPath: localURL.path) {
            return localURL
        }

        // Download from cloud
        if let downloadedPath = try await downloadFromCloud(storagePath: storagePath) {
            return resolveLocalPath(downloadedPath)
        }

        return nil
    }
}
