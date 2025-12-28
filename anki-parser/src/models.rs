use std::collections::HashMap;
use std::sync::{Arc, RwLock};

/// Progress states during parsing
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum AnkiProgress {
    Extracting,
    ReadingDecks,
    ReadingCards,
    ProcessingMedia,
    Complete,
}

/// Progress callback trait for Swift to implement
#[uniffi::export(callback_interface)]
pub trait AnkiProgressCallback: Send + Sync {
    fn on_progress(&self, progress: AnkiProgress);
}

/// Represents a deck with hierarchy support
#[derive(Debug, Clone, uniffi::Record)]
pub struct AnkiDeck {
    pub id: i64,
    /// Full name with "::" separators (e.g., "Parent::Child::Grandchild")
    pub name: String,
    /// Just the leaf name (e.g., "Grandchild")
    pub short_name: String,
}

impl AnkiDeck {
    /// Create a deck from its ID and full name
    pub fn from_name(id: i64, name: String) -> Self {
        let short_name = name
            .rsplit("::")
            .next()
            .unwrap_or(&name)
            .to_string();

        Self { id, name, short_name }
    }

    /// Check if this deck is a root deck (no parent)
    pub fn is_root(&self) -> bool {
        !self.name.contains("::")
    }

    /// Get the parent path (e.g., "Parent::Child" for "Parent::Child::Grandchild")
    pub fn parent_path(&self) -> Option<String> {
        let parts: Vec<&str> = self.name.split("::").collect();
        if parts.len() > 1 {
            Some(parts[..parts.len() - 1].join("::"))
        } else {
            None
        }
    }
}

/// Represents a single card with its fields
#[derive(Debug, Clone, uniffi::Record)]
pub struct AnkiCard {
    pub id: i64,
    pub note_id: i64,
    pub deck_id: i64,
    /// Card fields (front, back, extra, etc.)
    pub fields: Vec<String>,
    /// Media file references found in the card
    pub media_references: Vec<String>,
}

/// Media store for accessing media files
#[derive(Debug, uniffi::Object)]
pub struct AnkiMediaStore {
    /// Map of original filename -> file data
    data: RwLock<HashMap<String, Vec<u8>>>,
    /// Ordered list of filenames
    filenames_list: RwLock<Vec<String>>,
}

impl AnkiMediaStore {
    pub fn new() -> Self {
        Self {
            data: RwLock::new(HashMap::new()),
            filenames_list: RwLock::new(Vec::new()),
        }
    }

    /// Add media data to the store
    pub fn insert(&self, filename: String, data: Vec<u8>) {
        let mut store = self.data.write().unwrap();
        let mut filenames = self.filenames_list.write().unwrap();

        if !store.contains_key(&filename) {
            filenames.push(filename.clone());
        }
        store.insert(filename, data);
    }

    /// Add just the filename (for lazy loading)
    pub fn add_filename(&self, filename: String) {
        let store = self.data.read().unwrap();
        let mut filenames = self.filenames_list.write().unwrap();

        if !store.contains_key(&filename) && !filenames.contains(&filename) {
            filenames.push(filename);
        }
    }
}

#[uniffi::export]
impl AnkiMediaStore {
    /// Get all media filenames
    pub fn filenames(&self) -> Vec<String> {
        self.filenames_list.read().unwrap().clone()
    }

    /// Get data for a specific media file
    pub fn data_for(&self, filename: String) -> Option<Vec<u8>> {
        self.data.read().unwrap().get(&filename).cloned()
    }

    /// Get the number of media files
    pub fn count(&self) -> u32 {
        self.filenames_list.read().unwrap().len() as u32
    }
}

impl Default for AnkiMediaStore {
    fn default() -> Self {
        Self::new()
    }
}

/// Main collection container returned after parsing
#[derive(Debug, uniffi::Record)]
pub struct AnkiCollection {
    /// All decks in the collection
    pub decks: Vec<AnkiDeck>,
    /// Root-level decks only (no parent)
    pub root_decks: Vec<AnkiDeck>,
    /// Cards grouped by deck ID (as string key for UniFFI compatibility)
    pub cards_by_deck: HashMap<String, Vec<AnkiCard>>,
    /// Media store for accessing media files
    pub media: Arc<AnkiMediaStore>,
}

impl AnkiCollection {
    pub fn new(
        decks: Vec<AnkiDeck>,
        cards_by_deck: HashMap<i64, Vec<AnkiCard>>,
        media: Arc<AnkiMediaStore>,
    ) -> Self {
        // Find root decks
        let root_decks: Vec<AnkiDeck> = decks
            .iter()
            .filter(|d| d.is_root())
            .cloned()
            .collect();

        // Convert deck ID keys to strings for UniFFI
        let cards_by_deck_str: HashMap<String, Vec<AnkiCard>> = cards_by_deck
            .into_iter()
            .map(|(k, v)| (k.to_string(), v))
            .collect();

        Self {
            decks,
            root_decks,
            cards_by_deck: cards_by_deck_str,
            media,
        }
    }
}
