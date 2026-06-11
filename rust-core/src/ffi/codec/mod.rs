//! Color and attribute encoding for FFI data transfer
//!
//! This module provides encoding functions for converting terminal state
//! (colors, SGR attributes, cell data) into compact integer representations
//! suitable for FFI transfer to Emacs Lisp.
//!
//! # Encoding formats
//!
//! ## Color encoding (u32)
//! - `0xFF000000` ([`COLOR_DEFAULT_SENTINEL`]): `Color::Default` (distinct from true black)
//! - Bit 31 set ([`COLOR_NAMED_MARKER`] `| index`): Named color (index 0-15)
//! - Bit 30 set ([`COLOR_INDEXED_MARKER`] `| index`): Indexed color (index 0-255)
//! - Lower 24 bits only: RGB packed as `(R << 16) | (G << 8) | B`
//!
//! ## Attribute encoding (u64)
//! Bitmask of SGR boolean flags:
//! - Bit 0 (`0x001`): bold
//! - Bit 1 (`0x002`): dim
//! - Bit 2 (`0x004`): italic
//! - Bit 3 (`0x008`, [`ATTRS_UNDERLINE_BIT`]): underline (any style)
//! - Bits 9-11 (shift [`ATTRS_STYLE_SHIFT`]): underline style (0-5)
//! - Bit 4 (`0x010`): blink slow
//! - Bit 5 (`0x020`): blink fast
//! - Bit 6 (`0x040`): inverse
//! - Bit 7 (`0x080`): hidden
//! - Bit 8 (`0x100`): strikethrough
//!
//! # Module layout
//!
//! | Submodule      | Contents                                              |
//! |----------------|-------------------------------------------------------|
//! | [`color`]      | Color/attr constants and `encode_color`/`encode_attrs`|
//! | [`line`]       | `EncodePool`, `encode_line*` entry points             |
//! | [`binary`]     | `encode_screen_binary`, hash functions                |
//! | [`hyperlinks`] | `encode_hyperlink_ranges`                             |

mod binary;
mod color;
mod hyperlinks;
mod line;

// Color encoding
pub use color::{
    encode_attrs, encode_color, ATTRS_STYLE_SHIFT, ATTRS_UNDERLINE_BIT,
    COLOR_DEFAULT_SENTINEL, COLOR_INDEXED_MARKER, COLOR_NAMED_MARKER,
    RGB_G_SHIFT, RGB_R_SHIFT,
};

// Line encoding
pub use line::encode_line;
pub(crate) use line::{
    encode_line_into_buf, encode_line_with_pool, EncodePool, EncodedLine,
};

// Binary frame encoding + hash
pub(crate) use binary::{
    compute_row_hash_from_encoded, compute_row_hash_from_pool, encode_screen_binary,
    BINARY_FORMAT_VERSION,
};
#[cfg(test)]
pub(crate) use binary::compute_row_hash;

// Hyperlink ranges
pub use hyperlinks::encode_hyperlink_ranges;

#[cfg(test)]
#[path = "../tests/codec.rs"]
mod tests;
