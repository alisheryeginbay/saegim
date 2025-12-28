use std::sync::Arc;

use crate::archive::AnkiArchive;
use crate::error::AnkiError;
use crate::models::AnkiMediaStore;

/// Known audio file extensions
const AUDIO_EXTENSIONS: &[&str] = &["mp3", "wav", "m4a", "ogg", "flac", "aac", "opus", "wma"];

/// Known image file extensions
const IMAGE_EXTENSIONS: &[&str] = &["jpg", "jpeg", "png", "gif", "webp", "bmp", "svg", "ico", "tiff"];

/// Magic bytes for file format detection
mod magic {
    pub const ZSTD: [u8; 4] = [0x28, 0xB5, 0x2F, 0xFD];
    pub const JPEG: [u8; 2] = [0xFF, 0xD8];
    pub const PNG: [u8; 8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    pub const GIF87: [u8; 6] = [0x47, 0x49, 0x46, 0x38, 0x37, 0x61];
    pub const GIF89: [u8; 6] = [0x47, 0x49, 0x46, 0x38, 0x39, 0x61];
    pub const WEBP: [u8; 4] = [0x52, 0x49, 0x46, 0x46]; // "RIFF" (need to check for WEBP at offset 8)
    pub const MP3_ID3: [u8; 3] = [0x49, 0x44, 0x33]; // "ID3"
    pub const OGG: [u8; 4] = [0x4F, 0x67, 0x67, 0x53]; // "OggS"
    pub const FLAC: [u8; 4] = [0x66, 0x4C, 0x61, 0x43]; // "fLaC"
    pub const WAV: [u8; 4] = [0x52, 0x49, 0x46, 0x46]; // "RIFF" (need to check for WAVE)
}

/// Media file type
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MediaType {
    Audio,
    Image,
    Unknown,
}

/// Determine media type from filename extension
pub fn media_type_from_extension(filename: &str) -> MediaType {
    let ext = filename
        .rsplit('.')
        .next()
        .unwrap_or("")
        .to_lowercase();

    if AUDIO_EXTENSIONS.contains(&ext.as_str()) {
        MediaType::Audio
    } else if IMAGE_EXTENSIONS.contains(&ext.as_str()) {
        MediaType::Image
    } else {
        MediaType::Unknown
    }
}

/// Check if data starts with zstd magic bytes
pub fn is_zstd_compressed(data: &[u8]) -> bool {
    data.len() >= 4 && data[0..4] == magic::ZSTD
}

/// Decompress zstd data
pub fn decompress_zstd(data: &[u8]) -> Result<Vec<u8>, AnkiError> {
    zstd::decode_all(data)
        .map_err(|e| AnkiError::DecompressionError(e.to_string()))
}

/// Validate that data looks like a valid image based on magic bytes
pub fn is_valid_image(data: &[u8]) -> bool {
    if data.len() < 8 {
        return false;
    }

    // JPEG
    if data.starts_with(&magic::JPEG) {
        return true;
    }

    // PNG
    if data.starts_with(&magic::PNG) {
        return true;
    }

    // GIF
    if data.starts_with(&magic::GIF87) || data.starts_with(&magic::GIF89) {
        return true;
    }

    // WebP (RIFF....WEBP)
    if data.starts_with(&magic::WEBP) && data.len() >= 12 && &data[8..12] == b"WEBP" {
        return true;
    }

    // BMP
    if data.len() >= 2 && data[0] == b'B' && data[1] == b'M' {
        return true;
    }

    // SVG (starts with < or whitespace then <)
    let trimmed: Vec<u8> = data.iter().copied().skip_while(|&b| b == b' ' || b == b'\t' || b == b'\n' || b == b'\r').take(5).collect();
    if trimmed.starts_with(b"<?xml") || trimmed.starts_with(b"<svg") {
        return true;
    }

    false
}

/// Validate that data looks like valid audio based on magic bytes
pub fn is_valid_audio(data: &[u8]) -> bool {
    if data.len() < 4 {
        return false;
    }

    // MP3 with ID3 tag
    if data.starts_with(&magic::MP3_ID3) {
        return true;
    }

    // MP3 sync word
    if data.len() >= 2 && data[0] == 0xFF && (data[1] & 0xE0) == 0xE0 {
        return true;
    }

    // OGG
    if data.starts_with(&magic::OGG) {
        return true;
    }

    // FLAC
    if data.starts_with(&magic::FLAC) {
        return true;
    }

    // WAV (RIFF....WAVE)
    if data.starts_with(&magic::WAV) && data.len() >= 12 && &data[8..12] == b"WAVE" {
        return true;
    }

    // M4A/AAC (starts with ftyp)
    if data.len() >= 8 && &data[4..8] == b"ftyp" {
        return true;
    }

    false
}

/// Process media files from the archive
pub fn process_media<F>(
    archive: &mut AnkiArchive,
    mut progress_callback: F,
) -> Result<Arc<AnkiMediaStore>, AnkiError>
where
    F: FnMut(usize, usize),
{
    let store = Arc::new(AnkiMediaStore::new());

    // Get media mapping (index -> filename)
    let mapping = archive.extract_media_mapping()?;
    let total = mapping.len();

    if total == 0 {
        return Ok(store);
    }

    let mut current = 0;

    for (index, filename) in &mapping {
        // Only process audio and image files
        let media_type = media_type_from_extension(filename);
        if media_type == MediaType::Unknown {
            current += 1;
            continue;
        }

        // Extract the file data
        if let Some(mut data) = archive.extract_media(index)? {
            // Decompress if zstd-compressed
            if is_zstd_compressed(&data) {
                match decompress_zstd(&data) {
                    Ok(decompressed) => {
                        data = decompressed;
                    }
                    Err(e) => {
                        log::warn!("Failed to decompress {}: {}", filename, e);
                        // Skip this file
                        current += 1;
                        continue;
                    }
                }
            }

            // Validate the file
            let is_valid = match media_type {
                MediaType::Image => is_valid_image(&data),
                MediaType::Audio => is_valid_audio(&data),
                MediaType::Unknown => false,
            };

            if is_valid {
                store.insert(filename.clone(), data);
            } else {
                // Still add it - the Swift side may handle it
                log::warn!(
                    "Media file {} may be invalid (header check failed)",
                    filename
                );
                store.insert(filename.clone(), data);
            }
        }

        current += 1;

        // Report progress every 100 files
        if current % 100 == 0 {
            progress_callback(current, total);
        }
    }

    // Final progress update
    progress_callback(current, total);

    Ok(store)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_media_type_detection() {
        assert_eq!(media_type_from_extension("audio.mp3"), MediaType::Audio);
        assert_eq!(media_type_from_extension("image.jpg"), MediaType::Image);
        assert_eq!(media_type_from_extension("image.PNG"), MediaType::Image);
        assert_eq!(media_type_from_extension("unknown.xyz"), MediaType::Unknown);
    }

    #[test]
    fn test_zstd_detection() {
        let zstd_data = vec![0x28, 0xB5, 0x2F, 0xFD, 0x00];
        assert!(is_zstd_compressed(&zstd_data));

        let regular_data = vec![0xFF, 0xD8, 0xFF, 0xE0];
        assert!(!is_zstd_compressed(&regular_data));
    }

    #[test]
    fn test_image_validation() {
        // JPEG
        let jpeg = vec![0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46];
        assert!(is_valid_image(&jpeg));

        // PNG
        let png = vec![0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
        assert!(is_valid_image(&png));

        // Invalid
        let invalid = vec![0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00];
        assert!(!is_valid_image(&invalid));
    }

    #[test]
    fn test_audio_validation() {
        // MP3 with ID3
        let mp3_id3 = vec![0x49, 0x44, 0x33, 0x04, 0x00];
        assert!(is_valid_audio(&mp3_id3));

        // WAV
        let wav = vec![0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, 0x57, 0x41, 0x56, 0x45];
        assert!(is_valid_audio(&wav));
    }
}
