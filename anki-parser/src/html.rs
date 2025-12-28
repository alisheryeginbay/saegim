use regex::Regex;

/// Convert HTML field content to Markdown-like text
///
/// This handles:
/// - [sound:filename.mp3] → [🔊 filename.mp3](media:filename.mp3)
/// - <img src="filename.jpg"> → ![filename.jpg](media:filename.jpg)
/// - <br>, <br/> → \n
/// - <div>, </div>, <p>, </p> → \n
/// - <span>, <b>, <i>, <u>, <strong>, <em> → removed
/// - HTML entities → decoded
/// - Multiple newlines → normalized
///
/// The `media:` prefix is a placeholder that Swift will replace with actual saegim:// URLs
pub fn clean_html(html: &str) -> String {
    let mut text = html.to_string();

    // Convert Anki sound references [sound:filename.mp3] to markdown audio
    // Using media: prefix as placeholder for Swift to replace
    let sound_regex = Regex::new(r"\[sound:([^\]]+)\]").unwrap();
    text = sound_regex
        .replace_all(&text, |caps: &regex::Captures| {
            let filename = &caps[1];
            format!("[🔊 {}](media:{})", filename, filename)
        })
        .to_string();

    // Convert <img src="filename"> to markdown image
    let img_regex = Regex::new(r#"<img[^>]+src=["']?([^"'\s>]+)["']?[^>]*>"#).unwrap();
    text = img_regex
        .replace_all(&text, |caps: &regex::Captures| {
            let filename = &caps[1];
            format!("![{}](media:{})", filename, filename)
        })
        .to_string();

    // Replace <br>, <br/>, <br /> with newlines
    let br_regex = Regex::new(r"<br\s*/?>").unwrap();
    text = br_regex.replace_all(&text, "\n").to_string();

    // Replace block elements with newlines
    let div_open_regex = Regex::new(r"<div[^>]*>").unwrap();
    text = div_open_regex.replace_all(&text, "").to_string();

    let div_close_regex = Regex::new(r"</div>").unwrap();
    text = div_close_regex.replace_all(&text, "\n").to_string();

    let p_open_regex = Regex::new(r"<p[^>]*>").unwrap();
    text = p_open_regex.replace_all(&text, "").to_string();

    let p_close_regex = Regex::new(r"</p>").unwrap();
    text = p_close_regex.replace_all(&text, "\n").to_string();

    // Remove inline formatting tags
    let span_regex = Regex::new(r"</?span[^>]*>").unwrap();
    text = span_regex.replace_all(&text, "").to_string();

    let format_regex = Regex::new(r"</?(?:b|i|u|strong|em|font|a)[^>]*>").unwrap();
    text = format_regex.replace_all(&text, "").to_string();

    // Remove any remaining HTML tags
    let tag_regex = Regex::new(r"<[^>]+>").unwrap();
    text = tag_regex.replace_all(&text, "").to_string();

    // Decode HTML entities
    text = decode_html_entities(&text);

    // Normalize whitespace
    text = text.trim().to_string();

    // Collapse multiple newlines into at most two
    let multi_newline_regex = Regex::new(r"\n{3,}").unwrap();
    text = multi_newline_regex.replace_all(&text, "\n\n").to_string();

    text
}

/// Decode common HTML entities
fn decode_html_entities(text: &str) -> String {
    let mut result = text.to_string();

    // Common entities
    let entities = [
        ("&nbsp;", " "),
        ("&amp;", "&"),
        ("&lt;", "<"),
        ("&gt;", ">"),
        ("&quot;", "\""),
        ("&apos;", "'"),
        ("&#39;", "'"),
        ("&mdash;", "—"),
        ("&ndash;", "–"),
        ("&hellip;", "…"),
        ("&copy;", "©"),
        ("&reg;", "®"),
        ("&trade;", "™"),
        ("&laquo;", "«"),
        ("&raquo;", "»"),
        ("&bull;", "•"),
        ("&middot;", "·"),
        ("&times;", "×"),
        ("&divide;", "÷"),
        ("&plusmn;", "±"),
        ("&deg;", "°"),
        ("&prime;", "′"),
        ("&Prime;", "″"),
    ];

    for (entity, replacement) in entities {
        result = result.replace(entity, replacement);
    }

    // Numeric entities (&#NNN; and &#xHHH;)
    let decimal_regex = Regex::new(r"&#(\d+);").unwrap();
    result = decimal_regex
        .replace_all(&result, |caps: &regex::Captures| {
            let code: u32 = caps[1].parse().unwrap_or(0);
            char::from_u32(code).map(|c| c.to_string()).unwrap_or_default()
        })
        .to_string();

    let hex_regex = Regex::new(r"&#[xX]([0-9a-fA-F]+);").unwrap();
    result = hex_regex
        .replace_all(&result, |caps: &regex::Captures| {
            let code = u32::from_str_radix(&caps[1], 16).unwrap_or(0);
            char::from_u32(code).map(|c| c.to_string()).unwrap_or_default()
        })
        .to_string();

    result
}

/// Process all fields in a card, cleaning HTML
pub fn process_card_fields(fields: &[String]) -> Vec<String> {
    fields.iter().map(|f| clean_html(f)).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sound_conversion() {
        let html = "Word [sound:pronunciation.mp3]";
        let result = clean_html(html);
        assert_eq!(result, "Word [🔊 pronunciation.mp3](media:pronunciation.mp3)");
    }

    #[test]
    fn test_image_conversion() {
        let html = "Picture: <img src=\"image.jpg\">";
        let result = clean_html(html);
        assert_eq!(result, "Picture: ![image.jpg](media:image.jpg)");
    }

    #[test]
    fn test_br_conversion() {
        let html = "Line 1<br>Line 2<br/>Line 3";
        let result = clean_html(html);
        assert_eq!(result, "Line 1\nLine 2\nLine 3");
    }

    #[test]
    fn test_div_conversion() {
        let html = "<div>Paragraph 1</div><div>Paragraph 2</div>";
        let result = clean_html(html);
        assert!(result.contains("Paragraph 1"));
        assert!(result.contains("Paragraph 2"));
    }

    #[test]
    fn test_html_entities() {
        let html = "Tom &amp; Jerry &lt;3";
        let result = clean_html(html);
        assert_eq!(result, "Tom & Jerry <3");
    }

    #[test]
    fn test_strip_formatting() {
        let html = "<b>Bold</b> and <i>italic</i>";
        let result = clean_html(html);
        assert_eq!(result, "Bold and italic");
    }

    #[test]
    fn test_complex_card() {
        let html = r#"<div><b>Question:</b> What is this?</div>
<div>[sound:audio.mp3]</div>
<div><img src="picture.png"></div>"#;
        let result = clean_html(html);
        assert!(result.contains("Question:"));
        assert!(result.contains("[🔊 audio.mp3](media:audio.mp3)"));
        assert!(result.contains("![picture.png](media:picture.png)"));
    }

    #[test]
    fn test_numeric_entities() {
        let html = "&#65;&#66;&#67; and &#x41;&#x42;&#x43;";
        let result = clean_html(html);
        assert_eq!(result, "ABC and ABC");
    }
}
