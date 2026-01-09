-- Migration: Server-side timestamps for conflict resolution
-- This ensures consistent modified_at timestamps regardless of device clock drift

-- Create function to update modified_at on INSERT or UPDATE
CREATE OR REPLACE FUNCTION update_modified_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.modified_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply trigger to cards table
DROP TRIGGER IF EXISTS set_modified_at_cards ON cards;
CREATE TRIGGER set_modified_at_cards
    BEFORE INSERT OR UPDATE ON cards
    FOR EACH ROW
    EXECUTE FUNCTION update_modified_at();

-- Apply trigger to decks table
DROP TRIGGER IF EXISTS set_modified_at_decks ON decks;
CREATE TRIGGER set_modified_at_decks
    BEFORE INSERT OR UPDATE ON decks
    FOR EACH ROW
    EXECUTE FUNCTION update_modified_at();

-- Apply trigger to media table (if it has modified_at)
-- Note: Current schema doesn't have modified_at on media, but adding for future-proofing
-- DROP TRIGGER IF EXISTS set_modified_at_media ON media;
-- CREATE TRIGGER set_modified_at_media
--     BEFORE INSERT OR UPDATE ON media
--     FOR EACH ROW
--     EXECUTE FUNCTION update_modified_at();

COMMENT ON FUNCTION update_modified_at IS 'Automatically sets modified_at to server time on INSERT or UPDATE';
