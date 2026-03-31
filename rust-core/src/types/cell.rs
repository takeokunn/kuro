//! Cell and attribute types

use super::color::Color;
use compact_str::CompactString;
use serde::{Deserialize, Serialize};

/// SGR boolean attribute flags — packed into a single byte per cell.
///
/// Using one `u8` bitfield instead of eight `bool` fields reduces
/// `SgrAttributes` by 7 bytes per instance.  With a 24×80 terminal
/// (1 920 cells), this saves ~13 KiB per screen buffer.
#[derive(Clone, Copy, PartialEq, Eq)]
pub struct SgrFlags(u8);

impl SgrFlags {
    /// SGR 1: Bold / increased intensity
    pub const BOLD: Self = Self(0b0000_0001);
    /// SGR 2: Faint / decreased intensity
    pub const DIM: Self = Self(0b0000_0010);
    /// SGR 3: Italic
    pub const ITALIC: Self = Self(0b0000_0100);
    /// SGR 5: Blink (slow)
    pub const BLINK_SLOW: Self = Self(0b0000_1000);
    /// SGR 6: Blink (rapid)
    pub const BLINK_FAST: Self = Self(0b0001_0000);
    /// SGR 7: Inverse / reverse video
    pub const INVERSE: Self = Self(0b0010_0000);
    /// SGR 8: Concealed / hidden
    pub const HIDDEN: Self = Self(0b0100_0000);
    /// SGR 9: Crossed-out / strikethrough
    pub const STRIKETHROUGH: Self = Self(0b1000_0000);

    /// Return the raw `u8` bit pattern.
    #[inline]
    pub fn bits(self) -> u8 {
        self.0
    }

    /// Construct from a raw `u8` bit pattern.
    #[inline]
    pub fn from_bits_truncate(bits: u8) -> Self {
        Self(bits)
    }

    /// Return `true` if all bits in `other` are set in `self`.
    #[inline]
    pub const fn contains(self, other: Self) -> bool {
        self.0 & other.0 == other.0
    }

    /// Set all bits in `other`.
    #[inline]
    pub fn insert(&mut self, other: Self) {
        self.0 |= other.0;
    }

    /// Clear all bits in `other`.
    #[inline]
    pub fn remove(&mut self, other: Self) {
        self.0 &= !other.0;
    }

    /// Set or clear bits in `other` depending on `val`.
    #[inline]
    pub fn set(&mut self, other: Self, val: bool) {
        if val {
            self.insert(other);
        } else {
            self.remove(other);
        }
    }

    /// Return `true` if no bits are set.
    #[inline]
    pub fn is_empty(self) -> bool {
        self.0 == 0
    }
}

impl Default for SgrFlags {
    #[inline]
    fn default() -> Self {
        Self(0)
    }
}

impl std::fmt::Debug for SgrFlags {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "SgrFlags({:#010b})", self.0)
    }
}

impl std::ops::BitOr for SgrFlags {
    type Output = Self;
    #[inline]
    fn bitor(self, rhs: Self) -> Self {
        Self(self.0 | rhs.0)
    }
}

impl std::ops::BitOrAssign for SgrFlags {
    #[inline]
    fn bitor_assign(&mut self, rhs: Self) {
        self.0 |= rhs.0;
    }
}

impl std::ops::BitAnd for SgrFlags {
    type Output = Self;
    #[inline]
    fn bitand(self, rhs: Self) -> Self {
        Self(self.0 & rhs.0)
    }
}

impl std::ops::BitAndAssign for SgrFlags {
    #[inline]
    fn bitand_assign(&mut self, rhs: Self) {
        self.0 &= rhs.0;
    }
}

impl std::ops::Not for SgrFlags {
    type Output = Self;
    #[inline]
    fn not(self) -> Self {
        Self(!self.0)
    }
}

impl Serialize for SgrFlags {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        self.bits().serialize(s)
    }
}

impl<'de> Deserialize<'de> for SgrFlags {
    fn deserialize<D: serde::Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let bits = u8::deserialize(d)?;
        Ok(Self::from_bits_truncate(bits))
    }
}

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
    /// Boolean style flags (bold, dim, italic, blink, inverse, hidden, strikethrough)
    pub flags: SgrFlags,
    /// Underline style (none/straight/double/curly/dotted/dashed)
    pub underline_style: UnderlineStyle,
    /// Underline color (SGR 58/59)
    pub underline_color: Color,
}

impl Default for SgrAttributes {
    fn default() -> Self {
        Self {
            foreground: Color::Default,
            background: Color::Default,
            flags: SgrFlags::default(),
            underline_style: UnderlineStyle::None,
            underline_color: Color::Default,
        }
    }
}

impl SgrAttributes {
    /// Reset all attributes to default
    #[inline]
    pub fn reset(&mut self) {
        *self = Self::default();
    }

    /// Returns true if any underline style is active
    #[inline]
    #[must_use]
    pub fn underline(&self) -> bool {
        self.underline_style != UnderlineStyle::None
    }
}

/// Extended cell data for rarely-used features (hyperlinks, images).
/// Stored behind `Option<Box<CellExtras>>` to keep the common Cell small.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CellExtras {
    /// Hyperlink ID (if any)
    pub hyperlink_id: Option<String>,
    /// Image ID for Kitty Graphics Protocol (if any)
    pub image_id: Option<u32>,
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
    /// Extended data (hyperlinks, images) — None for 99.9% of cells
    pub(crate) extras: Option<Box<CellExtras>>,
}

impl Cell {
    /// Create a new cell with the given character
    #[inline]
    #[must_use]
    pub fn new(c: char) -> Self {
        let mut buf = [0u8; 4];
        let s = c.encode_utf8(&mut buf);
        Self {
            grapheme: CompactString::new(s),
            attrs: SgrAttributes::default(),
            width: CellWidth::Half,
            extras: None,
        }
    }

    /// Create a new cell with character, attributes, and width
    #[inline]
    #[must_use]
    pub fn with_char_and_width(c: char, attrs: SgrAttributes, width: CellWidth) -> Self {
        let mut buf = [0u8; 4];
        let s = c.encode_utf8(&mut buf);
        Self {
            grapheme: CompactString::new(s),
            attrs,
            width,
            extras: None,
        }
    }

    /// Create a new cell with character and attributes
    #[inline]
    #[must_use]
    pub fn with_attrs(c: char, attrs: SgrAttributes) -> Self {
        let mut buf = [0u8; 4];
        let s = c.encode_utf8(&mut buf);
        Self {
            grapheme: CompactString::new(s),
            attrs,
            width: CellWidth::Half,
            extras: None,
        }
    }

    /// Set hyperlink ID
    #[inline]
    #[must_use]
    pub fn with_hyperlink(mut self, id: String) -> Self {
        self.set_hyperlink_id(Some(id));
        self
    }

    /// Get hyperlink ID (if any)
    #[inline]
    #[must_use]
    pub fn hyperlink_id(&self) -> Option<&str> {
        self.extras.as_ref().and_then(|e| e.hyperlink_id.as_deref())
    }

    /// Get image ID (if any)
    #[inline]
    #[must_use]
    pub fn image_id(&self) -> Option<u32> {
        self.extras.as_ref().and_then(|e| e.image_id)
    }

    /// Set hyperlink ID, allocating or deallocating extras as needed
    #[inline]
    pub fn set_hyperlink_id(&mut self, id: Option<String>) {
        if id.is_none() && self.extras.as_ref().is_none_or(|e| e.image_id.is_none()) {
            self.extras = None;
        } else {
            let extras = self.extras.get_or_insert_with(|| {
                Box::new(CellExtras {
                    hyperlink_id: None,
                    image_id: None,
                })
            });
            extras.hyperlink_id = id;
        }
    }

    /// Set image ID, allocating or deallocating extras as needed
    #[inline]
    pub fn set_image_id(&mut self, id: Option<u32>) {
        if id.is_none()
            && self
                .extras
                .as_ref()
                .is_none_or(|e| e.hyperlink_id.is_none())
        {
            self.extras = None;
        } else {
            let extras = self.extras.get_or_insert_with(|| {
                Box::new(CellExtras {
                    hyperlink_id: None,
                    image_id: None,
                })
            });
            extras.image_id = id;
        }
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
    #[inline]
    #[must_use]
    pub fn char(&self) -> char {
        self.grapheme.chars().next().unwrap_or(' ')
    }

    /// Get the full grapheme cluster string (may include combining characters)
    #[inline]
    #[must_use]
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
            extras: None,
        }
    }
}

impl PartialEq for Cell {
    fn eq(&self, other: &Self) -> bool {
        self.grapheme == other.grapheme
            && self.attrs == other.attrs
            && self.width == other.width
            && self.extras == other.extras
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
        assert!(!cell.attrs.flags.contains(SgrFlags::BOLD));
    }

    #[test]
    fn test_cell_with_attrs() {
        let attrs = SgrAttributes {
            flags: SgrFlags::BOLD,
            foreground: Color::Rgb(255, 0, 0),
            ..Default::default()
        };

        let cell = Cell::with_attrs('B', attrs);
        assert_eq!(cell.grapheme.as_str(), "B");
        assert!(cell.attrs.flags.contains(SgrFlags::BOLD));
        assert_eq!(cell.attrs.foreground, Color::Rgb(255, 0, 0));
    }

    #[test]
    fn test_sgr_reset() {
        let mut attrs = SgrAttributes {
            flags: SgrFlags::BOLD | SgrFlags::ITALIC,
            ..Default::default()
        };

        attrs.reset();
        assert!(!attrs.flags.contains(SgrFlags::BOLD));
        assert!(!attrs.flags.contains(SgrFlags::ITALIC));
        assert_eq!(attrs.foreground, Color::Default);
    }

    #[test]
    fn test_cell_image_id_defaults_to_none() {
        let cell_default = Cell::default();
        assert_eq!(cell_default.image_id(), None);

        let cell_new = Cell::new('X');
        assert_eq!(cell_new.image_id(), None);
    }

    #[test]
    fn test_cell_equality() {
        let cell1 = Cell::new('A');
        let cell2 = Cell::new('A');
        assert_eq!(cell1, cell2);

        let attrs = SgrAttributes {
            flags: SgrFlags::BOLD,
            ..Default::default()
        };
        let cell3 = Cell::with_attrs('A', attrs);
        assert_ne!(cell1, cell3);
    }

    #[test]
    fn test_cell_with_hyperlink() {
        // A freshly created cell has no hyperlink
        let cell = Cell::new('A');
        assert_eq!(cell.hyperlink_id(), None);

        // with_hyperlink sets the hyperlink_id to the given String
        let linked_cell = cell.with_hyperlink("https://example.com".to_owned());
        assert_eq!(linked_cell.hyperlink_id(), Some("https://example.com"));

        // Replacing an existing hyperlink with a different one works correctly
        let relinked = linked_cell.with_hyperlink("https://other.com".to_owned());
        assert_eq!(relinked.hyperlink_id(), Some("https://other.com"));

        // Other fields are preserved after setting a hyperlink
        assert_eq!(relinked.char(), 'A');
        assert_eq!(relinked.width, CellWidth::Half);
        assert!(!relinked.attrs.flags.contains(SgrFlags::BOLD));
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

    #[test]
    fn test_cell_default_is_space_with_half_width() {
        let cell = Cell::default();
        assert_eq!(cell.char(), ' ');
        assert_eq!(cell.width, CellWidth::Half);
        assert!(cell.extras.is_none());
        assert_eq!(cell.attrs, SgrAttributes::default());
    }

    #[test]
    fn test_cell_new_ascii_stores_char_and_no_extras() {
        let cell = Cell::new('Z');
        assert_eq!(cell.char(), 'Z');
        assert_eq!(cell.grapheme.as_str(), "Z");
        assert!(cell.extras.is_none());
    }

    #[test]
    fn test_cell_new_cjk_wide_char() {
        // '中' is a wide CJK character; Cell::new does NOT auto-detect width,
        // but with_char_and_width can be used.  Test that the char is stored.
        let cell = Cell::with_char_and_width('中', SgrAttributes::default(), CellWidth::Full);
        assert_eq!(cell.char(), '中');
        assert_eq!(cell.width, CellWidth::Full);
    }

    #[test]
    fn test_cell_char_getter_roundtrip() {
        for ch in ['a', 'Z', '!', '\u{1F600}'] {
            let cell = Cell::new(ch);
            assert_eq!(cell.char(), ch);
        }
    }

    #[test]
    fn test_set_hyperlink_id_some_stores_id() {
        let mut cell = Cell::new('A');
        cell.set_hyperlink_id(Some("https://example.com".to_owned()));
        assert_eq!(cell.hyperlink_id(), Some("https://example.com"));
    }

    #[test]
    fn test_set_hyperlink_id_none_clears_but_keeps_image() {
        let mut cell = Cell::new('A');
        // Set both ids
        cell.set_hyperlink_id(Some("link".to_owned()));
        cell.set_image_id(Some(42));
        // Clear hyperlink — image should survive
        cell.set_hyperlink_id(None);
        assert_eq!(cell.hyperlink_id(), None);
        assert_eq!(cell.image_id(), Some(42));
    }

    #[test]
    fn test_set_image_id_some_stores_id() {
        let mut cell = Cell::new('A');
        cell.set_image_id(Some(99));
        assert_eq!(cell.image_id(), Some(99));
    }

    #[test]
    fn test_set_image_id_none_clears_but_keeps_hyperlink() {
        let mut cell = Cell::new('A');
        cell.set_hyperlink_id(Some("link".to_owned()));
        cell.set_image_id(Some(7));
        // Clear image — hyperlink should survive
        cell.set_image_id(None);
        assert_eq!(cell.image_id(), None);
        assert_eq!(cell.hyperlink_id(), Some("link"));
    }

    #[test]
    fn test_cell_extras_none_when_no_ids() {
        let cell = Cell::new('A');
        // Neither hyperlink nor image set → extras must be None
        assert!(cell.extras.is_none());
        assert_eq!(cell.hyperlink_id(), None);
        assert_eq!(cell.image_id(), None);
    }

    #[test]
    fn test_sgr_reset_clears_all_fields() {
        let mut attrs = SgrAttributes {
            foreground: Color::Rgb(1, 2, 3),
            background: Color::Indexed(5),
            flags: SgrFlags::BOLD | SgrFlags::ITALIC | SgrFlags::STRIKETHROUGH,
            underline_style: UnderlineStyle::Curly,
            underline_color: Color::Rgb(0, 0, 0),
        };
        attrs.reset();
        assert_eq!(attrs, SgrAttributes::default());
        assert!(attrs.flags.is_empty());
        assert_eq!(attrs.foreground, Color::Default);
        assert_eq!(attrs.background, Color::Default);
        assert_eq!(attrs.underline_style, UnderlineStyle::None);
        assert_eq!(attrs.underline_color, Color::Default);
    }

    // SGR attribute tests (logically belong to SgrAttributes in cell.rs)

    #[test]
    fn test_sgr_attributes_default_has_no_flags() {
        let attrs = SgrAttributes::default();
        assert!(attrs.flags.is_empty());
        assert_eq!(attrs.foreground, Color::Default);
        assert_eq!(attrs.background, Color::Default);
    }

    #[test]
    fn test_sgr_attributes_bold_flag() {
        let attrs = SgrAttributes {
            flags: SgrFlags::BOLD,
            ..Default::default()
        };
        assert!(attrs.flags.contains(SgrFlags::BOLD));
        assert!(!attrs.flags.contains(SgrFlags::ITALIC));
    }

    #[test]
    fn test_sgr_attributes_bold_and_italic() {
        let attrs = SgrAttributes {
            flags: SgrFlags::BOLD | SgrFlags::ITALIC,
            ..Default::default()
        };
        assert!(attrs.flags.contains(SgrFlags::BOLD));
        assert!(attrs.flags.contains(SgrFlags::ITALIC));
    }

    #[test]
    fn test_sgr_attributes_256_color_fg() {
        let attrs = SgrAttributes {
            foreground: Color::Indexed(200),
            ..Default::default()
        };
        assert_eq!(attrs.foreground, Color::Indexed(200));
    }

    #[test]
    fn test_sgr_attributes_rgb_fg_stores_components() {
        let attrs = SgrAttributes {
            foreground: Color::Rgb(10, 20, 30),
            ..Default::default()
        };
        assert_eq!(attrs.foreground, Color::Rgb(10, 20, 30));
        if let Color::Rgb(r, g, b) = attrs.foreground {
            assert_eq!(r, 10);
            assert_eq!(g, 20);
            assert_eq!(b, 30);
        } else {
            panic!("expected Color::Rgb");
        }
    }

    #[test]
    fn test_underline_style_default_is_none_variant() {
        let attrs = SgrAttributes::default();
        assert_eq!(attrs.underline_style, UnderlineStyle::None);
    }

    #[test]
    fn test_sgr_attributes_equality() {
        let a = SgrAttributes {
            flags: SgrFlags::BOLD,
            foreground: Color::Rgb(1, 2, 3),
            ..Default::default()
        };
        let b = SgrAttributes {
            flags: SgrFlags::BOLD,
            foreground: Color::Rgb(1, 2, 3),
            ..Default::default()
        };
        assert_eq!(a, b);
        let c = SgrAttributes {
            flags: SgrFlags::DIM,
            ..Default::default()
        };
        assert_ne!(a, c);
    }
}
