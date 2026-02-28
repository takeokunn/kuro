//! Cell and attribute types

use super::color::Color;
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
    /// Underline text
    pub underline: bool,
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
            underline: false,
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
    pub fn reset(&mut self) {
        *self = Self::default();
    }
}

/// A single cell in the terminal grid
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Cell {
    /// Character at this position
    pub c: char,
    /// SGR attributes
    pub attrs: SgrAttributes,
    /// Cell width (for Unicode/CJK support)
    pub width: CellWidth,
    /// Hyperlink ID (if any)
    pub hyperlink_id: Option<String>,
}

impl Cell {
    /// Create a new cell with the given character
    pub fn new(c: char) -> Self {
        Self {
            c,
            attrs: SgrAttributes::default(),
            width: CellWidth::Half,
            hyperlink_id: None,
        }
    }

    /// Create a new cell with character and attributes
    pub fn with_attrs(c: char, attrs: SgrAttributes) -> Self {
        Self {
            c,
            attrs,
            width: CellWidth::Half,
            hyperlink_id: None,
        }
    }

    /// Set hyperlink ID
    pub fn with_hyperlink(mut self, id: String) -> Self {
        self.hyperlink_id = Some(id);
        self
    }
}

impl Default for Cell {
    fn default() -> Self {
        Self::new(' ')
    }
}

impl PartialEq for Cell {
    fn eq(&self, other: &Self) -> bool {
        self.c == other.c
            && self.attrs == other.attrs
            && self.width == other.width
            && self.hyperlink_id == other.hyperlink_id
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cell_default() {
        let cell = Cell::default();
        assert_eq!(cell.c, ' ');
        assert_eq!(cell.attrs.foreground, Color::Default);
    }

    #[test]
    fn test_cell_new() {
        let cell = Cell::new('A');
        assert_eq!(cell.c, 'A');
        assert_eq!(cell.attrs.bold, false);
    }

    #[test]
    fn test_cell_with_attrs() {
        let mut attrs = SgrAttributes::default();
        attrs.bold = true;
        attrs.foreground = Color::Rgb(255, 0, 0);

        let cell = Cell::with_attrs('B', attrs);
        assert_eq!(cell.c, 'B');
        assert!(cell.attrs.bold);
        assert_eq!(cell.attrs.foreground, Color::Rgb(255, 0, 0));
    }

    #[test]
    fn test_sgr_reset() {
        let mut attrs = SgrAttributes::default();
        attrs.bold = true;
        attrs.italic = true;

        attrs.reset();
        assert!(!attrs.bold);
        assert!(!attrs.italic);
        assert_eq!(attrs.foreground, Color::Default);
    }

    #[test]
    fn test_cell_equality() {
        let cell1 = Cell::new('A');
        let cell2 = Cell::new('A');
        assert_eq!(cell1, cell2);

        let mut attrs = SgrAttributes::default();
        attrs.bold = true;
        let cell3 = Cell::with_attrs('A', attrs);
        assert_ne!(cell1, cell3);
    }
}
