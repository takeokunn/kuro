//! Cell and attribute types

use std::sync::Arc;

use super::color::Color;
use compact_str::CompactString;

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

/// Cell width for Unicode/CJK character support
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
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
///
/// `#[repr(u8)]` with sequential discriminants allows `encode_attrs` in
/// `ffi/codec.rs` to cast directly to `u64` instead of using a 5-arm match
/// table.  The discriminant values (0-5) match the wire encoding exactly.
#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum UnderlineStyle {
    /// No underline (default)
    #[default]
    None = 0,
    /// Single straight line (SGR 4 or 4:1)
    Straight = 1,
    /// Double line (SGR 4:2 or SGR 21)
    Double = 2,
    /// Curly/wavy line (SGR 4:3, undercurl)
    Curly = 3,
    /// Dotted line (SGR 4:4)
    Dotted = 4,
    /// Dashed line (SGR 4:5)
    Dashed = 5,
}

/// SGR (Select Graphic Rendition) attributes for a cell
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
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
    /// SGR 53: overline
    pub overline: bool,
    /// SGR 73: superscript
    pub superscript: bool,
    /// SGR 75: subscript
    pub subscript: bool,
}

impl Default for SgrAttributes {
    fn default() -> Self {
        Self {
            foreground: Color::Default,
            background: Color::Default,
            flags: SgrFlags::default(),
            underline_style: UnderlineStyle::None,
            underline_color: Color::Default,
            overline: false,
            superscript: false,
            subscript: false,
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

    /// Returns `true` when every attribute is at its terminal default value.
    ///
    /// Used in [`fill_encode_pool`] as a fast path that skips four
    /// `encode_color`/`encode_attrs` calls for the common case of
    /// unstyled cells (shell prompts, plain text, man-page output, etc.).
    ///
    /// The test order is cheapest-first to short-circuit early:
    /// `flags` and `underline_style` are integer/discriminant comparisons;
    /// color comparisons come last.
    #[inline]
    #[must_use]
    pub fn is_all_default(&self) -> bool {
        self.flags.is_empty()
            && self.underline_style == UnderlineStyle::None
            && !self.overline
            && !self.superscript
            && !self.subscript
            && self.foreground == Color::Default
            && self.background == Color::Default
            && self.underline_color == Color::Default
    }
}

/// Extended cell data for rarely-used features (hyperlinks, images).
/// Stored behind `Option<Box<CellExtras>>` to keep the common Cell small.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CellExtras {
    /// Hyperlink ID (if any)
    pub hyperlink_id: Option<Arc<str>>,
    /// Image ID for Kitty Graphics Protocol (if any)
    pub image_id: Option<u32>,
}

/// A single cell in the terminal grid
#[derive(Debug, Clone)]
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
    pub fn with_hyperlink(mut self, id: Arc<str>) -> Self {
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
    pub fn set_hyperlink_id(&mut self, id: Option<Arc<str>>) {
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
include!("cell_tests.rs");
