//! Anki Parser - High-performance Anki .apkg/.colpkg parser
//!
//! This library provides fast parsing of Anki flashcard packages with:
//! - ZIP archive extraction
//! - SQLite database parsing
//! - zstd decompression for modern Anki formats
//! - Media file handling
//! - HTML to Markdown conversion
//!
//! Designed for integration with Swift via UniFFI bindings.

pub mod archive;
pub mod database;
pub mod error;
pub mod html;
pub mod media;
pub mod models;


use archive::AnkiArchive;
use database::AnkiDatabase;
use error::AnkiError;
use models::{AnkiCollection, AnkiDeck, AnkiProgress, AnkiProgressCallback};

// Re-export main types
pub use error::AnkiError as Error;
pub use models::{AnkiCard as Card, AnkiCollection as Collection, AnkiDeck as Deck};

/// Parse an Anki .apkg or .colpkg file
///
/// # Arguments
/// * `file_path` - Path to the .apkg or .colpkg file
/// * `progress_callback` - Callback to report parsing progress
///
/// # Returns
/// * `AnkiCollection` containing all decks, cards, and media
///
/// # Errors
/// * `AnkiError::FileNotFound` - File does not exist
/// * `AnkiError::InvalidArchive` - Not a valid Anki archive
/// * `AnkiError::DatabaseError` - Error reading SQLite database
/// * `AnkiError::DecompressionError` - Error decompressing zstd data
#[uniffi::export]
pub fn parse_anki_file(
    file_path: String,
    progress_callback: Box<dyn AnkiProgressCallback>,
) -> Result<AnkiCollection, AnkiError> {
    // Phase 1: Extract archive
    progress_callback.on_progress(AnkiProgress::Extracting);
    let mut archive = AnkiArchive::open(&file_path)?;

    // Phase 2: Parse database
    progress_callback.on_progress(AnkiProgress::ReadingDecks);
    let db_data = archive.extract_database()?;
    let db = AnkiDatabase::open_from_bytes(&db_data)?;

    // Parse decks
    let mut decks = db.parse_decks()?;

    // Phase 3: Parse cards
    progress_callback.on_progress(AnkiProgress::ReadingCards);
    let cards_by_deck = db.parse_cards(|_current, _total| {
        // Could add more granular progress here
    })?;

    // Create a set of known deck IDs
    let known_deck_ids: std::collections::HashSet<i64> = decks.iter().map(|d| d.id).collect();

    // Check for missing decks and create them from card deck IDs
    for deck_id in cards_by_deck.keys() {
        if !known_deck_ids.contains(deck_id) {
            // Create a placeholder deck for orphaned cards
            decks.push(AnkiDeck::from_name(*deck_id, format!("Deck {}", deck_id)));
        }
    }

    // Phase 4: Process media
    progress_callback.on_progress(AnkiProgress::ProcessingMedia);
    let media = media::process_media(&mut archive, |_current, _total| {
        // Could add more granular progress here
    })?;

    // Phase 5: Complete
    progress_callback.on_progress(AnkiProgress::Complete);

    Ok(AnkiCollection::new(decks, cards_by_deck, media))
}

/// Clean HTML content to Markdown
///
/// This function is exported for Swift to use if needed for additional processing.
/// Converts:
/// - [sound:file.mp3] → [🔊 file.mp3](media:file.mp3)
/// - <img src="file.jpg"> → ![file.jpg](media:file.jpg)
/// - HTML tags → stripped or converted to newlines
/// - HTML entities → decoded
#[uniffi::export]
pub fn clean_html_to_markdown(html: String) -> String {
    html::clean_html(&html)
}

// Setup UniFFI scaffolding using proc-macros
uniffi::setup_scaffolding!();

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU32, Ordering};
    use std::sync::Arc;

    struct TestProgressCallback {
        progress_count: AtomicU32,
    }

    impl AnkiProgressCallback for TestProgressCallback {
        fn on_progress(&self, _progress: AnkiProgress) {
            self.progress_count.fetch_add(1, Ordering::SeqCst);
        }
    }

    #[test]
    fn test_clean_html() {
        let result = clean_html_to_markdown("Hello <b>World</b>".to_string());
        assert_eq!(result, "Hello World");
    }

    #[test]
    fn test_sound_conversion() {
        let result = clean_html_to_markdown("[sound:test.mp3]".to_string());
        assert_eq!(result, "[🔊 test.mp3](media:test.mp3)");
    }
}
