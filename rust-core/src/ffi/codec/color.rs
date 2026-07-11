//! Color and attribute encoding constants and functions.
//!
//! Converts [`Color`] and [`SgrAttributes`] into compact u32/u64 values
//! suitable for FFI transfer to Emacs Lisp.  See the parent module for the
//! full encoding format specification.

use crate::types::cell::SgrAttributes;
use crate::types::color::Color;

// -------------------------------------------------------------------------
// Color encoding constants
// -------------------------------------------------------------------------

/// Sentinel value for `Color::Default` in the u32 FFI encoding.
///
/// Cannot be confused with any RGB value because the upper byte `0xFF` is
/// never set by RGB (`r << 16 | g << 8 | b` uses at most 24 bits) and the
/// named/indexed markers use bits 31 and 30 respectively, not `0xFF…`.
pub const COLOR_DEFAULT_SENTINEL: u32 = 0xFF00_0000;

/// Bit-31 marker for `Color::Named` in the u32 FFI encoding.
///
/// `encode_color(Color::Named(c))` produces `COLOR_NAMED_MARKER | c.index()`.
pub const COLOR_NAMED_MARKER: u32 = 0x8000_0000;

/// Bit-30 marker for `Color::Indexed` in the u32 FFI encoding.
///
/// `encode_color(Color::Indexed(i))` produces `COLOR_INDEXED_MARKER | i`.
pub const COLOR_INDEXED_MARKER: u32 = 0x4000_0000;

/// Bit shift for the red channel in RGB packing: `r << RGB_R_SHIFT`.
pub const RGB_R_SHIFT: u32 = 16;

/// Bit shift for the green channel in RGB packing: `g << RGB_G_SHIFT`.
pub const RGB_G_SHIFT: u32 = 8;

// -------------------------------------------------------------------------
// Attribute encoding constants
// -------------------------------------------------------------------------

/// Bitmask that selects the three SGR flag bits that map directly (bold, dim,
/// italic) before the underline-bit insertion gap.
///
/// `SgrFlags` bits 0-2 (BOLD, DIM, ITALIC) map to encode bits 0-2 unchanged.
pub(super) const ATTRS_LOW_BITS_MASK: u64 = 0x07;

/// Right-shift applied to the upper `SgrFlags` bits (BLINK_SLOW … STRIKETHROUGH,
/// i.e. original bits 3-7) before they are placed at encode bits 4-8, making
/// room for the underline flag at bit 3.
pub(super) const ATTRS_HIGH_BITS_RSHIFT: u32 = 3;

/// Left-shift that moves the upper `SgrFlags` bits into their final encode
/// positions (bits 4-8) after the right-shift above.
pub(super) const ATTRS_HIGH_BITS_LSHIFT: u32 = 4;

/// Bit position of the "any underline active" flag in the encoded `u64`.
pub const ATTRS_UNDERLINE_BIT: u64 = 0x008;

/// Bit position (shift) of the 3-bit underline style field in the encoded `u64`.
pub const ATTRS_STYLE_SHIFT: u32 = 9;

/// Bit position of the "overline" flag (SGR 53/55) in the encoded `u64`.
/// Must match `kuro--sgr-flag-overline` (`#x1000`) in `kuro-faces-attrs.el`.
pub const ATTRS_OVERLINE_BIT: u64 = 0x1000;

/// Bit position of the "superscript" flag (SGR 73) — bit 13.
/// Must match `kuro--sgr-flag-superscript` (`#x2000`) in `kuro-faces-attrs.el`.
pub const ATTRS_SUPERSCRIPT_BIT: u64 = 0x2000;

/// Bit position of the "subscript" flag (SGR 75) — bit 14.
/// Must match `kuro--sgr-flag-subscript` (`#x4000`) in `kuro-faces-attrs.el`.
pub const ATTRS_SUBSCRIPT_BIT: u64 = 0x4000;

// -------------------------------------------------------------------------
// Encoding functions
// -------------------------------------------------------------------------

/// Encode a `Color` value as a `u32` for FFI transfer.
///
/// The encoding uses sentinel/marker bits to distinguish color variants
/// without ambiguity:
/// - `Color::Default` → [`COLOR_DEFAULT_SENTINEL`]
/// - `Color::Named(c)` → [`COLOR_NAMED_MARKER`] `| index`
/// - `Color::Indexed(i)` → [`COLOR_INDEXED_MARKER`] `| i`
/// - `Color::Rgb(r, g, b)` → `(r << RGB_R_SHIFT) | (g << RGB_G_SHIFT) | b` (can be 0 = true black)
#[inline(always)]
#[must_use = "encode result must be used for FFI transfer to Emacs Lisp"]
pub fn encode_color(color: &Color) -> u32 {
    match color {
        Color::Default => COLOR_DEFAULT_SENTINEL,
        Color::Named(named) => COLOR_NAMED_MARKER | u32::from(named.index()),
        Color::Indexed(idx) => COLOR_INDEXED_MARKER | u32::from(*idx),
        Color::Rgb(r, g, b) => encode_rgb(*r, *g, *b),
    }
}

#[inline(always)]
fn encode_rgb(red: u8, green: u8, blue: u8) -> u32 {
    (u32::from(red) << RGB_R_SHIFT) | (u32::from(green) << RGB_G_SHIFT) | u32::from(blue)
}

/// Encode `SgrAttributes` as a `u64` bitmask for FFI transfer.
///
/// Each boolean SGR attribute maps to a dedicated bit position.
/// The underline style is encoded in bits [`ATTRS_STYLE_SHIFT`]-11 as a 3-bit integer.
/// Bit 12 ([`ATTRS_OVERLINE_BIT`]) encodes the overline flag (SGR 53/55).
#[inline]
#[must_use = "encode result must be used for FFI transfer to Emacs Lisp"]
pub fn encode_attrs(attrs: &SgrAttributes) -> u64 {
    // SgrFlags layout:  BOLD=0, DIM=1, ITALIC=2, BLINK_SLOW=3, BLINK_FAST=4, INVERSE=5, HIDDEN=6, STRIKETHROUGH=7
    // Encode layout:    bold=0, dim=1,  italic=2, underline=3,  blink_slow=4, blink_fast=5, inverse=6, hidden=7, strike=8
    // Bits 0-2 (ATTRS_LOW_BITS_MASK) map directly; bits 3-7 shift left by 1
    // (ATTRS_HIGH_BITS_RSHIFT / ATTRS_HIGH_BITS_LSHIFT) to make room for the underline flag at bit 3.
    let raw = u64::from(attrs.flags.bits());
    let mut bits =
        (raw & ATTRS_LOW_BITS_MASK) | ((raw >> ATTRS_HIGH_BITS_RSHIFT) << ATTRS_HIGH_BITS_LSHIFT);
    if attrs.underline() {
        bits |= ATTRS_UNDERLINE_BIT;
    }
    bits |= u64::from(attrs.underline_style.wire_code()) << ATTRS_STYLE_SHIFT;
    if attrs.overline() {
        bits |= ATTRS_OVERLINE_BIT;
    }
    if attrs.superscript() {
        bits |= ATTRS_SUPERSCRIPT_BIT;
    }
    if attrs.subscript() {
        bits |= ATTRS_SUBSCRIPT_BIT;
    }
    bits
}
