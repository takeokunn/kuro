//! Cell and attribute types

use super::color::Color;
use compact_str::CompactString;
use serde::{Deserialize, Serialize};

/// Cell width for Unicode/CJK character support
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum CellWidth {
    /// Single-width character (ASCII, most symbols)
    #[default]
    Half,
    /// Wide character (CJK, emoji, etc.) - occupies two cells
    Full,
    /// Placeholder for second cell of wide character
    Wide,
}

/// Underline style for SGR 4:x sub-parameters
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum UnderlineStyle {
    /// No underline (default)
    #[default]
    None,
    /// Single straight line (SGR 4 or 4:1)
    Straight,
    /// Double line (SGR 4:2 or SGR 21)
    Double,
    /// Curly/wavy line (SGR 4:3, undercurl)
    Curly,
    /// Dotted line (SGR 4:4)
    Dotted,
    /// Dashed line (SGR 4:5)
    Dashed,
}

/// SGR (Select Graphic Rendition) attributes for a cell
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct SgrAttributes {
    /// Foreground color
    pub foreground: Color,
    /// Background color
    pub background: Color,
    /// Bold text
    pub bold: bool,
    /// Dim text
    pub dim: bool,
    /// Italic text
    pub italic: bool,
    /// Underline style (replaces the old `underline: bool`)
    pub underline_style: UnderlineStyle,
    /// Underline color (SGR 58/59)
    pub underline_color: Color,
    /// Blink (slow)
    pub blink_slow: bool,
    /// Blink (rapid)
    pub blink_fast: bool,
    /// Inverse/reverse video
    pub inverse: bool,
    /// Hidden/conceal
    pub hidden: bool,
    /// Strikethrough
    pub strikethrough: bool,
}

impl Default for SgrAttributes {
    fn default() -> Self {
        Self {
            foreground: Color::Default,
            background: Color::Default,
            bold: false,
            dim: false,
            italic: false,
            underline_style: UnderlineStyle::None,
            underline_color: Color::Default,
            blink_slow: false,
            blink_fast: false,
            inverse: false,
            hidden: false,
            strikethrough: false,
        }
    }
}

impl SgrAttributes {
    /// Reset all attributes to default
    #[inline(always)]
    pub fn reset(&mut self) {
        *self = Self::default();
    }

    /// Returns true if any underline style is active
    #[inline(always)]
    pub fn underline(&self) -> bool {
        self.underline_style != UnderlineStyle::None
    }
}

/// A single cell in the terminal grid
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Cell {
    /// Grapheme cluster at this position (may include combining characters)
    pub(crate) grapheme: CompactString,
    /// SGR attributes
    pub(crate) attrs: SgrAttributes,
    /// Cell width (for Unicode/CJK support)
    pub(crate) width: CellWidth,
    /// Hyperlink ID (if any)
    pub(crate) hyperlink_id: Option<String>,
    /// Image ID for Kitty Graphics Protocol (if any)
    pub(crate) image_id: Option<u32>,
}

impl Cell {
    /// Create a new cell with the given character
    #[inline(always)]
    pub fn new(c: char) -> Self {
        Self {
            grapheme: CompactString::new(c.to_string()),
            attrs: SgrAttributes::default(),
            width: CellWidth::Half,
            hyperlink_id: None,
            image_id: None,
        }
    }

    /// Create a new cell with character and attributes
    #[inline(always)]
    pub fn with_attrs(c: char, attrs: SgrAttributes) -> Self {
        Self {
            grapheme: CompactString::new(c.to_string()),
            attrs,
            width: CellWidth::Half,
            hyperlink_id: None,
            image_id: None,
        }
    }

    /// Set hyperlink ID
    #[inline(always)]
    pub fn with_hyperlink(mut self, id: String) -> Self {
        self.hyperlink_id = Some(id);
        self
    }

    /// Append a combining character to this cell's grapheme cluster.
    ///
    /// Combining characters are zero-width Unicode scalars (U+0300–U+036F,
    /// U+1AB0–U+1AFF, etc.) that attach visually to the preceding base glyph.
    /// We cap the grapheme at 8 Unicode scalars (1 base + 7 combining) to
    /// prevent memory exhaustion from adversarial or broken terminal output
    /// that emits a stream of zero-width characters into the same cell.
    /// Real grapheme clusters virtually never exceed 4 scalars; 8 is generous.
    #[inline]
    pub fn push_combining(&mut self, c: char) {
        // self.grapheme.chars().count() would be O(n) but graphemes are tiny;
        // compare byte length against a generous bound instead for O(1) check.
        // Cap at 32 bytes total: 1 base + up to 7 combining scalars × ≤4 bytes each.
        // Check that the new char fits before pushing to avoid exceeding the cap.
        if self.grapheme.len() + c.len_utf8() <= 32 {
            self.grapheme.push(c);
        }
    }

    /// Get the first (base) character of the grapheme cluster (backward compat)
    #[inline(always)]
    pub fn char(&self) -> char {
        self.grapheme.chars().next().unwrap_or(' ')
    }

    /// Get the full grapheme cluster string (may include combining characters)
    #[inline]
    pub fn grapheme(&self) -> &str {
        self.grapheme.as_str()
    }
}

impl Default for Cell {
    fn default() -> Self {
        Self {
            grapheme: CompactString::new(" "),
            attrs: SgrAttributes::default(),
            width: CellWidth::Half,
            hyperlink_id: None,
            image_id: None,
        }
    }
}

impl PartialEq for Cell {
    fn eq(&self, other: &Self) -> bool {
        self.grapheme == other.grapheme
            && self.attrs == other.attrs
            && self.width == other.width
            && self.hyperlink_id == other.hyperlink_id
            && self.image_id == other.image_id
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cell_default() {
        let cell = Cell::default();
        assert_eq!(cell.grapheme.as_str(), " ");
        assert_eq!(cell.attrs.foreground, Color::Default);
    }

    #[test]
    fn test_cell_new() {
        let cell = Cell::new('A');
        assert_eq!(cell.grapheme.as_str(), "A");
        assert!(!cell.attrs.bold);
    }

    #[test]
    fn test_cell_with_attrs() {
        let attrs = SgrAttributes {
            bold: true,
            foreground: Color::Rgb(255, 0, 0),
            ..Default::default()
        };

        let cell = Cell::with_attrs('B', attrs);
        assert_eq!(cell.grapheme.as_str(), "B");
        assert!(cell.attrs.bold);
        assert_eq!(cell.attrs.foreground, Color::Rgb(255, 0, 0));
    }

    #[test]
    fn test_sgr_reset() {
        let mut attrs = SgrAttributes { bold: true, italic: true, ..Default::default() };

        attrs.reset();
        assert!(!attrs.bold);
        assert!(!attrs.italic);
        assert_eq!(attrs.foreground, Color::Default);
    }

    #[test]
    fn test_cell_image_id_defaults_to_none() {
        let cell_default = Cell::default();
        assert_eq!(cell_default.image_id, None);

        let cell_new = Cell::new('X');
        assert_eq!(cell_new.image_id, None);
    }

    #[test]
    fn test_cell_equality() {
        let cell1 = Cell::new('A');
        let cell2 = Cell::new('A');
        assert_eq!(cell1, cell2);

        let attrs = SgrAttributes { bold: true, ..Default::default() };
        let cell3 = Cell::with_attrs('A', attrs);
        assert_ne!(cell1, cell3);
    }

    #[test]
    fn test_cell_with_hyperlink() {
        // A freshly created cell has no hyperlink
        let cell = Cell::new('A');
        assert_eq!(cell.hyperlink_id, None);

        // with_hyperlink sets the hyperlink_id to the given String
        let linked_cell = cell.with_hyperlink("https://example.com".to_string());
        assert_eq!(
            linked_cell.hyperlink_id,
            Some("https://example.com".to_string())
        );

        // Replacing an existing hyperlink with a different one works correctly
        let relinked = linked_cell.with_hyperlink("https://other.com".to_string());
        assert_eq!(relinked.hyperlink_id, Some("https://other.com".to_string()));

        // Other fields are preserved after setting a hyperlink
        assert_eq!(relinked.char(), 'A');
        assert_eq!(relinked.width, CellWidth::Half);
        assert!(!relinked.attrs.bold);
    }

    #[test]
    fn test_underline_style_default_is_none() {
        let attrs = SgrAttributes::default();
        assert_eq!(attrs.underline_style, UnderlineStyle::None);
        assert!(!attrs.underline());
    }

    #[test]
    fn test_underline_helper_method() {
        let mut attrs = SgrAttributes::default();
        assert!(!attrs.underline());
        attrs.underline_style = UnderlineStyle::Straight;
        assert!(attrs.underline());
        attrs.underline_style = UnderlineStyle::Curly;
        assert!(attrs.underline());
        attrs.underline_style = UnderlineStyle::None;
        assert!(!attrs.underline());
    }

    #[test]
    fn test_underline_color_default() {
        let attrs = SgrAttributes::default();
        assert_eq!(attrs.underline_color, Color::Default);
    }
}
