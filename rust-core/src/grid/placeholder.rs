//! Kitty Unicode placeholder support (the `U+10EEEE` virtual-placement glyph).
//!
//! Kitty's "Unicode placeholder" feature lets a program reference an already
//! transmitted image *purely through ordinary text cells*, so the image survives
//! scrolling, copy/paste and reflow exactly like text. A placeholder cell is a
//! cell whose base grapheme is the placeholder code point [`PLACEHOLDER_CHAR`]
//! (`U+10EEEE`). The image it references and its position inside the image grid
//! are encoded in the cell's colors and combining diacritics:
//!
//! - **Image id** comes from the cell's *foreground* color. A 24-bit truecolor
//!   foreground encodes the id directly as `(r << 16) | (g << 8) | b`; a
//!   256-color (indexed) foreground encodes a small id `0..=255`.
//! - **Placement id** comes from the cell's *underline* color (same encoding),
//!   `None` when no underline color is set.
//! - **Row / Column** within the image's cell grid come from the trailing
//!   combining diacritics attached to the cell, mapped through kitty's published
//!   297-entry "rowcolumn-diacritics" table ([`ROWCOLUMN_DIACRITICS`]): the 1st
//!   diacritic is the row, the 2nd the column, and an optional 3rd carries the
//!   *high byte* of the image id (`id | (extra << 24)` — the "most significant
//!   byte" extension used when the foreground only holds 24 bits).
//!
//! # Honesty about depth
//!
//! This module decodes the *association* between a placeholder cell and an image
//! (id + placement id + which (row,col) tile of the image the cell stands for)
//! and surfaces it to Emacs via the existing per-cell `image_id` extra plus an
//! [`crate::grid::image::ImageNotification`]. It does **not** perform full
//! fit-to-rectangle image slicing/scaling: Emacs renders the whole referenced
//! image at the anchor rather than compositing each cell's exact sub-tile. The
//! row/column metadata is decoded and exposed so a future renderer can do exact
//! tiling, but the current display is an approximation.

use crate::types::color::Color;

/// The Kitty Unicode placeholder base code point (`U+10EEEE`).
///
/// A printed cell whose base character is this code point is treated as a
/// virtual image-placement anchor rather than a literal glyph.
pub const PLACEHOLDER_CHAR: char = '\u{10EEEE}';

/// Returns true when `c` is the Kitty Unicode placeholder base character.
#[inline]
#[must_use]
pub fn is_placeholder_char(c: char) -> bool {
    c == PLACEHOLDER_CHAR
}

/// Kitty's "rowcolumn-diacritics" table.
///
/// Index `i` (0-based) into this slice is the row/column/extra value a given
/// combining diacritic encodes; the value is the diacritic's code point. To
/// decode a diacritic we reverse the mapping (find its position). This is the
/// canonical 297-entry table published by kitty
/// (`gen/rowcolumn-diacritics.txt`), embedded verbatim so decoding never depends
/// on an external file.
pub const ROWCOLUMN_DIACRITICS: [char; 297] = [
    '\u{0305}', '\u{030D}', '\u{030E}', '\u{0310}', '\u{0312}', '\u{033D}', '\u{033E}', '\u{033F}',
    '\u{0346}', '\u{034A}', '\u{034B}', '\u{034C}', '\u{0350}', '\u{0351}', '\u{0352}', '\u{0357}',
    '\u{035B}', '\u{0363}', '\u{0364}', '\u{0365}', '\u{0366}', '\u{0367}', '\u{0368}', '\u{0369}',
    '\u{036A}', '\u{036B}', '\u{036C}', '\u{036D}', '\u{036E}', '\u{036F}', '\u{0483}', '\u{0484}',
    '\u{0485}', '\u{0486}', '\u{0487}', '\u{0592}', '\u{0593}', '\u{0594}', '\u{0595}', '\u{0597}',
    '\u{0598}', '\u{0599}', '\u{059C}', '\u{059D}', '\u{059E}', '\u{059F}', '\u{05A0}', '\u{05A1}',
    '\u{05A8}', '\u{05A9}', '\u{05AB}', '\u{05AC}', '\u{05AF}', '\u{05C4}', '\u{0610}', '\u{0611}',
    '\u{0612}', '\u{0613}', '\u{0614}', '\u{0615}', '\u{0616}', '\u{0617}', '\u{0657}', '\u{0658}',
    '\u{0659}', '\u{065A}', '\u{065B}', '\u{065D}', '\u{065E}', '\u{06D6}', '\u{06D7}', '\u{06D8}',
    '\u{06D9}', '\u{06DA}', '\u{06DB}', '\u{06DC}', '\u{06DF}', '\u{06E0}', '\u{06E1}', '\u{06E2}',
    '\u{06E4}', '\u{06E7}', '\u{06E8}', '\u{06EB}', '\u{06EC}', '\u{0730}', '\u{0732}', '\u{0733}',
    '\u{0735}', '\u{0736}', '\u{073A}', '\u{073D}', '\u{073F}', '\u{0740}', '\u{0741}', '\u{0743}',
    '\u{0745}', '\u{0747}', '\u{0749}', '\u{074A}', '\u{07EB}', '\u{07EC}', '\u{07ED}', '\u{07EE}',
    '\u{07EF}', '\u{07F0}', '\u{07F1}', '\u{07F3}', '\u{0816}', '\u{0817}', '\u{0818}', '\u{0819}',
    '\u{081B}', '\u{081C}', '\u{081D}', '\u{081E}', '\u{081F}', '\u{0820}', '\u{0821}', '\u{0822}',
    '\u{0823}', '\u{0825}', '\u{0826}', '\u{0827}', '\u{0829}', '\u{082A}', '\u{082B}', '\u{082C}',
    '\u{082D}', '\u{0951}', '\u{0953}', '\u{0954}', '\u{0F82}', '\u{0F83}', '\u{0F86}', '\u{0F87}',
    '\u{135D}', '\u{135E}', '\u{135F}', '\u{17DD}', '\u{193A}', '\u{1A17}', '\u{1A75}', '\u{1A76}',
    '\u{1A77}', '\u{1A78}', '\u{1A79}', '\u{1A7A}', '\u{1A7B}', '\u{1A7C}', '\u{1B6B}', '\u{1B6D}',
    '\u{1B6E}', '\u{1B6F}', '\u{1B70}', '\u{1B71}', '\u{1B72}', '\u{1B73}', '\u{1CD0}', '\u{1CD1}',
    '\u{1CD2}', '\u{1CDA}', '\u{1CDB}', '\u{1CE0}', '\u{1DC0}', '\u{1DC1}', '\u{1DC3}', '\u{1DC4}',
    '\u{1DC5}', '\u{1DC6}', '\u{1DC7}', '\u{1DC8}', '\u{1DC9}', '\u{1DCB}', '\u{1DCC}', '\u{1DD1}',
    '\u{1DD2}', '\u{1DD3}', '\u{1DD4}', '\u{1DD5}', '\u{1DD6}', '\u{1DD7}', '\u{1DD8}', '\u{1DD9}',
    '\u{1DDA}', '\u{1DDB}', '\u{1DDC}', '\u{1DDD}', '\u{1DDE}', '\u{1DDF}', '\u{1DE0}', '\u{1DE1}',
    '\u{1DE2}', '\u{1DE3}', '\u{1DE4}', '\u{1DE5}', '\u{1DE6}', '\u{1DFE}', '\u{20D0}', '\u{20D1}',
    '\u{20D4}', '\u{20D5}', '\u{20D6}', '\u{20D7}', '\u{20DB}', '\u{20DC}', '\u{20E1}', '\u{20E7}',
    '\u{20E9}', '\u{20F0}', '\u{2CEF}', '\u{2CF0}', '\u{2CF1}', '\u{2DE0}', '\u{2DE1}', '\u{2DE2}',
    '\u{2DE3}', '\u{2DE4}', '\u{2DE5}', '\u{2DE6}', '\u{2DE7}', '\u{2DE8}', '\u{2DE9}', '\u{2DEA}',
    '\u{2DEB}', '\u{2DEC}', '\u{2DED}', '\u{2DEE}', '\u{2DEF}', '\u{2DF0}', '\u{2DF1}', '\u{2DF2}',
    '\u{2DF3}', '\u{2DF4}', '\u{2DF5}', '\u{2DF6}', '\u{2DF7}', '\u{2DF8}', '\u{2DF9}', '\u{2DFA}',
    '\u{2DFB}', '\u{2DFC}', '\u{2DFD}', '\u{2DFE}', '\u{2DFF}', '\u{A66F}', '\u{A67C}', '\u{A67D}',
    '\u{A6F0}', '\u{A6F1}', '\u{A8E0}', '\u{A8E1}', '\u{A8E2}', '\u{A8E3}', '\u{A8E4}', '\u{A8E5}',
    '\u{A8E6}', '\u{A8E7}', '\u{A8E8}', '\u{A8E9}', '\u{A8EA}', '\u{A8EB}', '\u{A8EC}', '\u{A8ED}',
    '\u{A8EE}', '\u{A8EF}', '\u{A8F0}', '\u{A8F1}', '\u{AAB0}', '\u{AAB2}', '\u{AAB3}', '\u{AAB7}',
    '\u{AAB8}', '\u{AABE}', '\u{AABF}', '\u{AAC1}', '\u{FE20}', '\u{FE21}', '\u{FE22}', '\u{FE23}',
    '\u{FE24}', '\u{FE25}', '\u{FE26}', '\u{10A0F}', '\u{10A38}', '\u{1D185}', '\u{1D186}',
    '\u{1D187}', '\u{1D188}', '\u{1D189}', '\u{1D1AA}', '\u{1D1AB}', '\u{1D1AC}', '\u{1D1AD}',
    '\u{1D242}', '\u{1D243}', '\u{1D244}',
];

/// Decode a single combining diacritic into its row/column/extra index.
///
/// Returns the 0-based position of `c` in [`ROWCOLUMN_DIACRITICS`], or `None`
/// when `c` is not one of kitty's rowcolumn diacritics.
#[inline]
#[must_use]
pub fn diacritic_value(c: char) -> Option<u32> {
    ROWCOLUMN_DIACRITICS
        .iter()
        .position(|&d| d == c)
        .map(|p| p as u32)
}

/// Decode an image id from a placeholder cell's *foreground* color.
///
/// - Truecolor (`Color::Rgb`): the 24 bits are the id, `(r<<16)|(g<<8)|b`.
/// - Indexed (`Color::Indexed`): the palette index `0..=255` is the id.
/// - `Color::Default`: no id encoded (malformed placeholder) → `None`.
///
/// An id of `0` is treated as "no id" (kitty image ids are positive).
#[inline]
#[must_use]
pub fn image_id_from_color(fg: Color) -> Option<u32> {
    let id = match fg {
        Color::Rgb(r, g, b) => (u32::from(r) << 16) | (u32::from(g) << 8) | u32::from(b),
        Color::Indexed(idx) => u32::from(idx),
        // A standard 16-color (Named) foreground encodes a tiny id 0..=15 via
        // the palette index (NamedColor is #[repr(u8)] = its index).
        Color::Named(named) => u32::from(named as u8),
        Color::Default => return None,
    };
    (id != 0).then_some(id)
}

/// Decode an optional placement id from the cell's *underline* color.
///
/// Uses the same color→u32 mapping as [`image_id_from_color`]; `Color::Default`
/// (no underline color) means "no explicit placement id".
#[inline]
#[must_use]
pub fn placement_id_from_color(underline: Color) -> Option<u32> {
    match underline {
        Color::Rgb(r, g, b) => Some((u32::from(r) << 16) | (u32::from(g) << 8) | u32::from(b)),
        Color::Indexed(idx) => Some(u32::from(idx)),
        Color::Named(named) => Some(u32::from(named as u8)),
        Color::Default => None,
    }
}

/// Decoded association between a Unicode-placeholder cell and an image.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PlaceholderInfo {
    /// Referenced image id (with any high-byte diacritic extension applied).
    pub image_id: u32,
    /// Optional placement id decoded from the underline color.
    pub placement_id: Option<u32>,
    /// Row within the image's cell grid (1st diacritic; 0 if absent).
    pub img_row: u32,
    /// Column within the image's cell grid (2nd diacritic; 0 if absent).
    pub img_col: u32,
}

/// A contiguous rectangular run of Unicode-placeholder cells that all reference
/// the *same* image and placement, with a regular tile grid — i.e. one
/// renderable image region.
///
/// This is the descriptor surfaced to Emacs so it can fetch the referenced PNG
/// once and slice it into per-cell tiles ("fit-to-rectangle"). It records where
/// on screen the placeholder rectangle sits ([`screen_row`](Self::screen_row) /
/// [`screen_col`](Self::screen_col)), its size in cells
/// ([`cell_cols`](Self::cell_cols) × [`cell_rows`](Self::cell_rows)), the tile
/// origin within the image grid ([`img_row`](Self::img_row) /
/// [`img_col`](Self::img_col)), and the full image-grid extent the rectangle
/// maps to ([`img_rows`](Self::img_rows) × [`img_cols`](Self::img_cols)) so
/// Emacs can compute each cell's `(slice X Y W H)`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PlaceholderRegion {
    /// Referenced image id (shared by every cell in the region).
    pub image_id: u32,
    /// Placement id shared by the region (`0` when no explicit placement).
    pub placement_id: u32,
    /// Top-left screen row of the rectangle (0-based).
    pub screen_row: usize,
    /// Top-left screen column of the rectangle (0-based).
    pub screen_col: usize,
    /// Width of the rectangle in terminal columns.
    pub cell_cols: usize,
    /// Height of the rectangle in terminal rows.
    pub cell_rows: usize,
    /// Image-grid row of the top-left tile (from the 1st diacritic).
    pub img_row: u32,
    /// Image-grid column of the top-left tile (from the 2nd diacritic).
    pub img_col: u32,
    /// Number of distinct image-grid rows the rectangle spans.
    pub img_rows: u32,
    /// Number of distinct image-grid columns the rectangle spans.
    pub img_cols: u32,
}

/// Decode a placeholder cell from its grapheme and colors.
///
/// `grapheme` is the cell's full grapheme cluster: the base [`PLACEHOLDER_CHAR`]
/// followed by 0..=3 rowcolumn diacritics. Returns `None` for a malformed
/// placeholder — most importantly, a placeholder whose foreground encodes no
/// image id (id 0 / default color) is ignored.
#[must_use]
pub fn decode_placeholder(grapheme: &str, fg: Color, underline: Color) -> Option<PlaceholderInfo> {
    let mut chars = grapheme.chars();
    if chars.next() != Some(PLACEHOLDER_CHAR) {
        return None;
    }

    // A placeholder with no decodable image id in the foreground is malformed
    // and must be ignored (rather than associating with a bogus image 0).
    let mut image_id = image_id_from_color(fg)?;

    // 1st diacritic = row, 2nd = column, 3rd = high byte of the image id.
    let img_row = chars.next().and_then(diacritic_value).unwrap_or(0);
    let img_col = chars.next().and_then(diacritic_value).unwrap_or(0);
    if let Some(extra) = chars.next().and_then(diacritic_value) {
        // High byte extension: most significant 8 bits of the (up to 32-bit) id.
        // The diacritic table has 297 entries, so `extra` can exceed 255; the
        // kitty spec defines this field as a single byte, so mask to 8 bits.
        // (Without the mask, `extra << 24` for values 256..=296 would silently
        // drop bits and corrupt the *lower* 24 bits of the id.)
        image_id |= (extra & 0xFF) << 24;
    }

    Some(PlaceholderInfo {
        image_id,
        placement_id: placement_id_from_color(underline),
        img_row,
        img_col,
    })
}

#[cfg(test)]
#[path = "placeholder/tests.rs"]
mod tests;
