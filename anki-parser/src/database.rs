use std::collections::HashMap;
use std::path::PathBuf;

use regex::Regex;
use rusqlite::{Connection, OpenFlags};
use serde_json::Value;

use crate::error::AnkiError;
use crate::models::{AnkiCard, AnkiDeck};

/// Batch size for processing cards (for progress reporting)
const BATCH_SIZE: usize = 1000;

/// Anki database wrapper
pub struct AnkiDatabase {
    conn: Connection,
    _temp_path: Option<PathBuf>,
}

impl AnkiDatabase {
    /// Open a database from raw bytes
    /// Creates a temporary file since rusqlite needs a file path
    pub fn open_from_bytes(data: &[u8]) -> Result<Self, AnkiError> {
        // Create a temp file for the database
        let temp_dir = std::env::temp_dir();
        let temp_path = temp_dir.join(format!("anki_import_{}.db", std::process::id()));

        std::fs::write(&temp_path, data)?;

        let conn = Connection::open_with_flags(
            &temp_path,
            OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
        )?;

        Ok(Self {
            conn,
            _temp_path: Some(temp_path),
        })
    }

    /// Parse all decks from the database
    pub fn parse_decks(&self) -> Result<Vec<AnkiDeck>, AnkiError> {
        // Try modern schema first (Anki 2.1.50+) - decks table with blob data
        if let Ok(decks) = self.parse_decks_modern() {
            if !decks.is_empty() {
                return Ok(decks);
            }
        }

        // Fall back to legacy schema - JSON in col table
        self.parse_decks_legacy()
    }

    /// Parse decks from modern schema (Anki 2.1.50+)
    /// In newer versions, decks are stored in a separate 'decks' table
    /// The 'name' column may be text or binary (protobuf)
    fn parse_decks_modern(&self) -> Result<Vec<AnkiDeck>, AnkiError> {
        let mut decks = Vec::new();

        // Check if decks table exists
        let table_exists: bool = self.conn.query_row(
            "SELECT COUNT(*) > 0 FROM sqlite_master WHERE type='table' AND name='decks'",
            [],
            |row| row.get(0),
        ).unwrap_or(false);

        if !table_exists {
            return Ok(decks);
        }

        // Modern Anki stores deck data in a 'decks' table
        // Both id and name might be stored as blobs in some versions
        let mut stmt = self.conn.prepare(
            "SELECT id, name FROM decks"
        )?;

        let rows = stmt.query_map([], |row| {
            // Handle id - might be integer or blob
            let id: i64 = match row.get_ref(0)? {
                rusqlite::types::ValueRef::Integer(i) => i,
                rusqlite::types::ValueRef::Blob(bytes) => {
                    // Try to parse as little-endian i64
                    if bytes.len() >= 8 {
                        i64::from_le_bytes(bytes[..8].try_into().unwrap_or([0; 8]))
                    } else {
                        0
                    }
                }
                _ => 0,
            };

            // Handle name - might be text or blob (protobuf)
            let name_bytes: Vec<u8> = match row.get_ref(1)? {
                rusqlite::types::ValueRef::Text(bytes) => bytes.to_vec(),
                rusqlite::types::ValueRef::Blob(bytes) => bytes.to_vec(),
                _ => Vec::new(),
            };

            Ok((id, name_bytes))
        })?;

        for row_result in rows {
            let (id, name_bytes) = row_result?;

            if id == 0 {
                continue;
            }

            // Try to decode as UTF-8 string
            let name = match String::from_utf8(name_bytes.clone()) {
                Ok(s) => s,
                Err(_) => {
                    // Not UTF-8, try to extract name from protobuf
                    extract_name_from_protobuf(&name_bytes)
                        .unwrap_or_default()
                }
            };

            if !name.is_empty() {
                decks.push(AnkiDeck::from_name(id, name));
            }
        }

        // Sort by hierarchy depth
        decks.sort_by(|a, b| {
            let a_depth = a.name.matches("::").count();
            let b_depth = b.name.matches("::").count();
            a_depth.cmp(&b_depth).then_with(|| a.name.cmp(&b.name))
        });

        Ok(decks)
    }

    /// Parse decks from legacy schema (pre-2.1.50)
    /// Decks stored as JSON in the 'col' table
    fn parse_decks_legacy(&self) -> Result<Vec<AnkiDeck>, AnkiError> {
        // Decks are stored as JSON in the `col` table
        let decks_json: Option<String> = self.conn.query_row(
            "SELECT decks FROM col",
            [],
            |row| row.get(0),
        ).ok();

        let decks_json = match decks_json {
            Some(json) if !json.trim().is_empty() => json,
            _ => {
                // No decks JSON, return empty vec
                return Ok(Vec::new());
            }
        };

        let decks_value: Value = serde_json::from_str(&decks_json)?;
        let mut decks = Vec::new();

        if let Value::Object(decks_map) = decks_value {
            for (id_str, deck_value) in decks_map {
                let id: i64 = id_str.parse().unwrap_or(0);

                // Skip the default deck with ID 1 if it has no cards
                // (Anki always has a "Default" deck)

                let name = deck_value["name"]
                    .as_str()
                    .unwrap_or("")
                    .to_string();

                // Skip empty names
                if name.is_empty() {
                    continue;
                }

                decks.push(AnkiDeck::from_name(id, name));
            }
        }

        // Sort by hierarchy depth (parents before children)
        decks.sort_by(|a, b| {
            let a_depth = a.name.matches("::").count();
            let b_depth = b.name.matches("::").count();
            a_depth.cmp(&b_depth).then_with(|| a.name.cmp(&b.name))
        });

        Ok(decks)
    }

    /// Get the total number of cards in the database
    pub fn card_count(&self) -> Result<usize, AnkiError> {
        let count: i64 = self.conn.query_row(
            "SELECT COUNT(*) FROM cards",
            [],
            |row| row.get(0),
        )?;
        Ok(count as usize)
    }

    /// Parse all cards with their notes
    /// Returns cards grouped by deck ID
    pub fn parse_cards<F>(
        &self,
        mut progress_callback: F,
    ) -> Result<HashMap<i64, Vec<AnkiCard>>, AnkiError>
    where
        F: FnMut(usize, usize),
    {
        let total = self.card_count()?;
        let mut cards_by_deck: HashMap<i64, Vec<AnkiCard>> = HashMap::new();

        // Regex patterns for extracting media references
        let sound_regex = Regex::new(r"\[sound:([^\]]+)\]").unwrap();
        let img_regex = Regex::new(r#"<img[^>]+src=["']?([^"'\s>]+)["']?"#).unwrap();

        // Query cards joined with notes
        let mut stmt = self.conn.prepare(
            "SELECT c.id, c.nid, c.did, n.flds
             FROM cards c
             JOIN notes n ON c.nid = n.id"
        )?;

        let mut current = 0;
        let rows = stmt.query_map([], |row| {
            let id: i64 = row.get(0)?;
            let note_id: i64 = row.get(1)?;
            let deck_id: i64 = row.get(2)?;
            // Get fields - handle both Text and Blob column types
            let fields_str: String = match row.get_ref(3)? {
                rusqlite::types::ValueRef::Text(bytes) => {
                    String::from_utf8_lossy(bytes).into_owned()
                }
                rusqlite::types::ValueRef::Blob(bytes) => {
                    String::from_utf8_lossy(bytes).into_owned()
                }
                _ => String::new(),
            };
            Ok((id, note_id, deck_id, fields_str))
        })?;

        for row_result in rows {
            let (id, note_id, deck_id, fields_str) = row_result?;

            // Fields are separated by 0x1f (unit separator)
            let fields: Vec<String> = fields_str
                .split('\x1f')
                .map(|s| s.to_string())
                .collect();

            // Extract media references from all fields
            let media_references = extract_media_references(&fields, &sound_regex, &img_regex);

            let card = AnkiCard {
                id,
                note_id,
                deck_id,
                fields,
                media_references,
            };

            cards_by_deck
                .entry(deck_id)
                .or_default()
                .push(card);

            current += 1;

            // Report progress every BATCH_SIZE cards
            if current % BATCH_SIZE == 0 {
                progress_callback(current, total);
            }
        }

        // Final progress update
        progress_callback(current, total);

        Ok(cards_by_deck)
    }
}

impl Drop for AnkiDatabase {
    fn drop(&mut self) {
        // Clean up temp file
        if let Some(ref path) = self._temp_path {
            let _ = std::fs::remove_file(path);
        }
    }
}

/// Extract deck name from protobuf-encoded data
/// Anki 2.1.50+ stores deck data as protobuf in the 'decks' table
/// The name field is typically field 2 (wire type 2 = length-delimited)
fn extract_name_from_protobuf(data: &[u8]) -> Option<String> {
    // Protobuf field tag for field 2, wire type 2 (LEN) = (2 << 3) | 2 = 0x12
    const NAME_FIELD_TAG: u8 = 0x12;

    let mut i = 0;
    while i < data.len() {
        let tag = data[i];
        i += 1;

        if i >= data.len() {
            break;
        }

        let wire_type = tag & 0x07;

        if tag == NAME_FIELD_TAG {
            // This is the name field - read length-prefixed string
            let len = data[i] as usize;
            i += 1;

            if i + len <= data.len() {
                if let Ok(name) = String::from_utf8(data[i..i + len].to_vec()) {
                    return Some(name);
                }
            }
        } else {
            // Skip this field based on wire type
            match wire_type {
                0 => {
                    // Varint - skip until MSB is 0
                    while i < data.len() && (data[i] & 0x80) != 0 {
                        i += 1;
                    }
                    i += 1;
                }
                1 => {
                    // 64-bit fixed
                    i += 8;
                }
                2 => {
                    // Length-delimited
                    if i < data.len() {
                        let len = data[i] as usize;
                        i += 1 + len;
                    }
                }
                5 => {
                    // 32-bit fixed
                    i += 4;
                }
                _ => {
                    // Unknown wire type, try to continue
                    i += 1;
                }
            }
        }
    }

    None
}

/// Extract media references from card fields
fn extract_media_references(
    fields: &[String],
    sound_regex: &Regex,
    img_regex: &Regex,
) -> Vec<String> {
    let mut refs = Vec::new();

    for field in fields {
        // Extract [sound:filename.mp3] references
        for cap in sound_regex.captures_iter(field) {
            if let Some(filename) = cap.get(1) {
                refs.push(filename.as_str().to_string());
            }
        }

        // Extract <img src="filename.jpg"> references
        for cap in img_regex.captures_iter(field) {
            if let Some(filename) = cap.get(1) {
                refs.push(filename.as_str().to_string());
            }
        }
    }

    refs
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_media_references() {
        let sound_regex = Regex::new(r"\[sound:([^\]]+)\]").unwrap();
        let img_regex = Regex::new(r#"<img[^>]+src=["']?([^"'\s>]+)["']?"#).unwrap();

        let fields = vec![
            "[sound:audio.mp3] Some text".to_string(),
            "<img src=\"image.jpg\">".to_string(),
            "Plain text".to_string(),
            "[sound:korean_audio.wav]<img src='photo.png'>".to_string(),
        ];

        let refs = extract_media_references(&fields, &sound_regex, &img_regex);

        assert_eq!(refs.len(), 4);
        assert!(refs.contains(&"audio.mp3".to_string()));
        assert!(refs.contains(&"image.jpg".to_string()));
        assert!(refs.contains(&"korean_audio.wav".to_string()));
        assert!(refs.contains(&"photo.png".to_string()));
    }

    #[test]
    fn test_deck_hierarchy() {
        let deck = AnkiDeck::from_name(1, "Parent::Child::Grandchild".to_string());
        assert_eq!(deck.short_name, "Grandchild");
        assert_eq!(deck.parent_path(), Some("Parent::Child".to_string()));
        assert!(!deck.is_root());

        let root_deck = AnkiDeck::from_name(2, "RootDeck".to_string());
        assert_eq!(root_deck.short_name, "RootDeck");
        assert_eq!(root_deck.parent_path(), None);
        assert!(root_deck.is_root());
    }
}
