use std::collections::HashMap;
use std::fs::File;
use std::io::{Read, Cursor};
use std::path::Path;
use zip::ZipArchive;

use crate::error::AnkiError;

/// Decompress zstd-compressed data
fn decompress_zstd(data: &[u8]) -> Result<Vec<u8>, AnkiError> {
    // Check for zstd magic bytes: 28 B5 2F FD
    if data.len() < 4 || data[0..4] != [0x28, 0xB5, 0x2F, 0xFD] {
        // Not zstd compressed, return as-is
        return Ok(data.to_vec());
    }

    zstd::decode_all(data)
        .map_err(|e| AnkiError::DecompressionError(e.to_string()))
}

/// Detected Anki archive format
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AnkiFormat {
    /// Legacy format: collection.anki2 (SQLite, no compression)
    Legacy,
    /// Modern format: collection.anki21 (SQLite, no compression)
    Modern,
    /// Compressed format: collection.anki21b (zstd-compressed SQLite)
    Compressed,
}

impl AnkiFormat {
    /// Get the database filename for this format
    pub fn db_filename(&self) -> &'static str {
        match self {
            AnkiFormat::Legacy => "collection.anki2",
            AnkiFormat::Modern => "collection.anki21",
            AnkiFormat::Compressed => "collection.anki21b",
        }
    }
}

/// Anki archive wrapper for ZIP file access
pub struct AnkiArchive {
    archive: ZipArchive<Cursor<Vec<u8>>>,
    format: AnkiFormat,
}

impl AnkiArchive {
    /// Open an Anki archive from a file path
    pub fn open<P: AsRef<Path>>(path: P) -> Result<Self, AnkiError> {
        let path = path.as_ref();

        if !path.exists() {
            return Err(AnkiError::FileNotFound(path.display().to_string()));
        }

        // Read entire file into memory for random access
        let mut file = File::open(path)?;
        let mut data = Vec::new();
        file.read_to_end(&mut data)?;

        Self::from_bytes(data)
    }

    /// Open an Anki archive from raw bytes
    pub fn from_bytes(data: Vec<u8>) -> Result<Self, AnkiError> {
        let cursor = Cursor::new(data);
        let mut archive = ZipArchive::new(cursor)?;

        // Detect format by checking which database file exists
        let format = Self::detect_format(&mut archive)?;

        Ok(Self { archive, format })
    }

    /// Detect the Anki format by checking for database files
    fn detect_format(archive: &mut ZipArchive<Cursor<Vec<u8>>>) -> Result<AnkiFormat, AnkiError> {
        // Check in order of preference (newest format first)
        if archive.by_name("collection.anki21b").is_ok() {
            Ok(AnkiFormat::Compressed)
        } else if archive.by_name("collection.anki21").is_ok() {
            Ok(AnkiFormat::Modern)
        } else if archive.by_name("collection.anki2").is_ok() {
            Ok(AnkiFormat::Legacy)
        } else {
            Err(AnkiError::InvalidArchive)
        }
    }

    /// Get the detected format
    pub fn format(&self) -> AnkiFormat {
        self.format
    }

    /// Extract and decompress the database
    pub fn extract_database(&mut self) -> Result<Vec<u8>, AnkiError> {
        let db_name = self.format.db_filename();
        let format = self.format;

        let data = {
            let mut file = self.archive.by_name(db_name)?;
            let mut data = Vec::with_capacity(file.size() as usize);
            file.read_to_end(&mut data)?;
            data
        };

        // Decompress if using compressed format
        if format == AnkiFormat::Compressed {
            decompress_zstd(&data)
        } else {
            Ok(data)
        }
    }

    /// Extract the media JSON mapping file
    /// Returns a map of index (as string) -> filename
    pub fn extract_media_mapping(&mut self) -> Result<HashMap<String, String>, AnkiError> {
        match self.archive.by_name("media") {
            Ok(mut file) => {
                // Read as bytes first to handle potential encoding issues
                let mut data = Vec::new();
                file.read_to_end(&mut data)?;

                // Handle empty content
                if data.is_empty() {
                    return Ok(HashMap::new());
                }

                // Try to convert to string (lossy if needed)
                let content = String::from_utf8_lossy(&data);
                let content = content.trim();

                if content.is_empty() {
                    return Ok(HashMap::new());
                }

                // Parse JSON: {"0": "image.jpg", "1": "audio.mp3", ...}
                match serde_json::from_str(content) {
                    Ok(mapping) => Ok(mapping),
                    Err(_) => {
                        // Not valid JSON, might be binary format - return empty
                        Ok(HashMap::new())
                    }
                }
            }
            Err(zip::result::ZipError::FileNotFound) => {
                // No media file means no media
                Ok(HashMap::new())
            }
            Err(e) => Err(e.into()),
        }
    }

    /// Get a list of all file names in the archive
    pub fn file_names(&self) -> Vec<String> {
        self.archive.file_names().map(|s| s.to_string()).collect()
    }

    /// Extract raw data for a file by index (as used in media mapping)
    pub fn extract_file_by_index(&mut self, index: &str) -> Result<Option<Vec<u8>>, AnkiError> {
        match self.archive.by_name(index) {
            Ok(mut file) => {
                let mut data = Vec::with_capacity(file.size() as usize);
                file.read_to_end(&mut data)?;
                Ok(Some(data))
            }
            Err(zip::result::ZipError::FileNotFound) => Ok(None),
            Err(e) => Err(e.into()),
        }
    }

    /// Extract media data and decompress if needed
    pub fn extract_media(&mut self, index: &str) -> Result<Option<Vec<u8>>, AnkiError> {
        match self.extract_file_by_index(index)? {
            Some(data) => {
                // Decompress if zstd-compressed (decompress_zstd checks magic bytes)
                let decompressed = decompress_zstd(&data)?;
                Ok(Some(decompressed))
            }
            None => Ok(None),
        }
    }

    /// Get the number of files in the archive
    pub fn len(&self) -> usize {
        self.archive.len()
    }

    /// Check if archive is empty
    pub fn is_empty(&self) -> bool {
        self.archive.len() == 0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_zstd_magic_detection() {
        let zstd_data = vec![0x28, 0xB5, 0x2F, 0xFD, 0x00, 0x00];
        assert_eq!(&zstd_data[0..4], &[0x28, 0xB5, 0x2F, 0xFD]);

        let regular_data = vec![0x53, 0x51, 0x4C, 0x69]; // "SQLi"
        assert_ne!(&regular_data[0..4], &[0x28, 0xB5, 0x2F, 0xFD]);
    }
}
