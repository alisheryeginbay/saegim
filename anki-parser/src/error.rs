use thiserror::Error;

/// Error types that can occur during Anki file parsing
#[derive(Debug, Error, uniffi::Error)]
pub enum AnkiError {
    #[error("File not found: {0}")]
    FileNotFound(String),

    #[error("Invalid archive format")]
    InvalidArchive,

    #[error("Database error: {0}")]
    DatabaseError(String),

    #[error("Decompression error: {0}")]
    DecompressionError(String),

    #[error("Media error: {0}")]
    MediaError(String),

    #[error("JSON parsing error: {0}")]
    JsonError(String),

    #[error("I/O error: {0}")]
    IoError(String),
}

impl From<std::io::Error> for AnkiError {
    fn from(e: std::io::Error) -> Self {
        if e.kind() == std::io::ErrorKind::NotFound {
            AnkiError::FileNotFound(e.to_string())
        } else {
            AnkiError::IoError(e.to_string())
        }
    }
}

impl From<zip::result::ZipError> for AnkiError {
    fn from(e: zip::result::ZipError) -> Self {
        match e {
            zip::result::ZipError::FileNotFound => AnkiError::InvalidArchive,
            zip::result::ZipError::InvalidArchive(_) => AnkiError::InvalidArchive,
            _ => AnkiError::IoError(e.to_string()),
        }
    }
}

impl From<rusqlite::Error> for AnkiError {
    fn from(e: rusqlite::Error) -> Self {
        AnkiError::DatabaseError(e.to_string())
    }
}

impl From<serde_json::Error> for AnkiError {
    fn from(e: serde_json::Error) -> Self {
        AnkiError::JsonError(e.to_string())
    }
}
